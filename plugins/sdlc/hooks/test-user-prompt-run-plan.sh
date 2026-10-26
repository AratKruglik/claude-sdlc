#!/usr/bin/env bash
# Test harness for the UserPromptSubmit hook user-prompt-run-plan.sh.
#
# Every case feeds a synthetic hook payload on stdin with cwd pointing at a throwaway git
# repository, so nothing touches the real repo. The planner runs for real against this
# checkout's plugins/ directory with caches redirected to the temp root.
#
# Run: bash plugins/sdlc/hooks/test-user-prompt-run-plan.sh
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${HOOK_DIR}/user-prompt-run-plan.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not available"; exit 0; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-prompt-hook.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

# The planner resolves these from the environment, so the test never writes to ~/.claude.
export CLAUDE_PLUGIN_DATA="$TMP_ROOT/plugin-data"

pass_count=0
fail_count=0

assert_eq() {
    local case_name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        pass_count=$((pass_count + 1)); printf 'PASS  %-64s = %s\n' "$case_name" "$actual"
    else
        fail_count=$((fail_count + 1)); printf 'FAIL  %-64s expected %q, got %q\n' "$case_name" "$expected" "$actual"
    fi
}

assert_contains() {
    local case_name="$1" needle="$2" haystack="$3"
    case "$haystack" in
        *"$needle"*) pass_count=$((pass_count + 1)); printf 'PASS  %-64s contains %q\n' "$case_name" "$needle" ;;
        *) fail_count=$((fail_count + 1)); printf 'FAIL  %-64s missing %q\n' "$case_name" "$needle" ;;
    esac
}

PROJ="$TMP_ROOT/proj"
mkdir -p "$PROJ/.claude"
git -C "$PROJ" init -q 2>/dev/null
git -C "$PROJ" symbolic-ref HEAD refs/heads/main
printf 'seed\n' > "$PROJ/README.md"
git -C "$PROJ" -c user.email=t@example.com -c user.name=Test add README.md
git -C "$PROJ" -c user.email=t@example.com -c user.name=Test -c commit.gpgsign=false commit -q -m seed

run_hook() {
    jq -cn --arg p "$1" --arg cwd "$PROJ" '{hook_event_name: "UserPromptSubmit", prompt: $p, cwd: $cwd}' | bash "$HOOK" 2>/dev/null
}

context_of() { printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // ""'; }
plan_of() { context_of "$1" | sed -n 2p; }

echo "=== user-prompt-run-plan.sh ==="
echo

assert_eq "unrelated prompt: silent"            "" "$(run_hook "explain this function")"
assert_eq "other sdlc command: silent"          "" "$(run_hook "/sdlc:doctor")"
assert_eq "prefix lookalike: silent"            "" "$(run_hook "/sdlc:starter thing")"
assert_eq "empty payload: silent"               "" "$(printf '' | bash "$HOOK" 2>/dev/null)"
assert_eq "malformed payload: silent"           "" "$(printf 'not json' | bash "$HOOK" 2>/dev/null)"

out=$(run_hook "/sdlc:start Add healthz endpoint --type=feature")
assert_eq "start: event name"                   "UserPromptSubmit" "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName')"
assert_contains "start: marker present"         "SDLC RUN PLAN" "$(context_of "$out")"
assert_contains "start: end marker present"     "=== END RUN PLAN ===" "$(context_of "$out")"
assert_eq "start: plan is JSON"                 "true" "$(plan_of "$out" | jq -r 'type == "object"')"
assert_eq "start: arguments forwarded"          "add-healthz-endpoint" "$(plan_of "$out" | jq -r '.task_slug')"
assert_eq "start: flag forwarded"               "feature" "$(plan_of "$out" | jq -r '.flags.type')"
assert_eq "start: cwd used as repo"             "$(cd "$PROJ" && pwd -P)" "$(plan_of "$out" | jq -r '.repo')"
assert_eq "start: not headless by default"      "false" "$(plan_of "$out" | jq -r '.headless_mode')"

out=$(run_hook "   /sdlc:start Fix typo")
assert_eq "leading whitespace: still matches"   "fix-typo" "$(plan_of "$out" | jq -r '.task_slug')"

out=$(run_hook "/sdlc:start")
assert_eq "bare command: plan still emitted"    "" "$(plan_of "$out" | jq -r '.description')"

out=$(SDLC_NONINTERACTIVE=true run_hook "/sdlc:start Add metrics")
assert_eq "headless env: forwarded"             "true" "$(plan_of "$out" | jq -r '.headless_mode')"

out=$(CLAUDE_PLUGIN_OPTION_NONINTERACTIVE=true run_hook "/sdlc:start Add metrics")
assert_eq "headless option: forwarded"          "true" "$(plan_of "$out" | jq -r '.headless_mode')"

out=$(SDLC_NONINTERACTIVE=false CLAUDE_PLUGIN_OPTION_NONINTERACTIVE=true run_hook "/sdlc:start Add metrics")
assert_eq "env wins over option"                "false" "$(plan_of "$out" | jq -r '.headless_mode')"

printf '# Conventions\n\nBranches follow feature/<ticket>-<slug> and this is a very long explanatory sentence that keeps going on and on about branch naming so that the hook has something longer than two hundred characters to truncate when it forwards the documented-convention hit to the orchestrator in the run plan context block.\n' > "$PROJ/CONTRIBUTING.md"
out=$(run_hook "/sdlc:start Add metrics")
assert_eq "convention hit text capped"          "true" "$(plan_of "$out" | jq -r '[.git_flow.documented_convention_hits[].text | length] | max <= 201')"

out=$(run_hook "/sdlc:start Add metrics")
assert_eq "unread diagnostics dropped"          "null" "$(plan_of "$out" | jq -c '.stack.all_profiles')"
assert_eq "context fits the cap"                "true" "$(context_of "$out" | jq -Rs 'length <= 9500')"

out=$(SDLC_RUN_PLAN_CONTEXT_CAP=500 CLAUDE_PLUGIN_DATA="$TMP_ROOT/data" run_hook "/sdlc:start Add metrics")
assert_contains "over the cap: pointer to the file" "Read $TMP_ROOT/data/run-plan/session.json once" "$(context_of "$out")"
assert_eq "over the cap: file holds the plan"   "add-metrics" "$(jq -r '.task_slug' "$TMP_ROOT/data/run-plan/session.json" 2>/dev/null)"

mkdir -p "$PROJ/plugins/sdlc/scripts" "$PROJ/plugins/evil-plugin"
printf '#!/usr/bin/env bash\n' > "$PROJ/plugins/sdlc/scripts/run-plan.sh"
printf -- '---\nstack: evil-injected-stack\npriority: 999\ndetect:\n  any: ["*"]\n---\n' > "$PROJ/plugins/evil-plugin/stack.md"
out=$(run_hook "/sdlc:start Add metrics")
case "$out" in *evil-injected-stack*) fail_count=$((fail_count + 1)); printf 'FAIL  untrusted cwd plugins treated as the plugin dev root\n' ;; *) pass_count=$((pass_count + 1)); printf 'PASS  untrusted cwd plugins are not treated as the dev root\n' ;; esac

echo
printf '%d passed, %d failed\n' "$pass_count" "$fail_count"
[ "$fail_count" -eq 0 ]
