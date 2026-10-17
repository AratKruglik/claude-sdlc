#!/usr/bin/env bash
# Test harness for phase-output-guard.sh (SubagentStop handoff-contract guard).
#
# Every case builds a throwaway project under a temp root with its own state file and
# _usage.jsonl. Nothing touches the real repo.
#
# Run: bash plugins/sdlc/hooks/test-phase-output-guard.sh
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GUARD="${HOOK_DIR}/phase-output-guard.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-phase-guard.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

pass_count=0
fail_count=0

assert_eq() {
    local case_name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        pass_count=$((pass_count + 1)); printf 'PASS  %-68s = %s\n' "$case_name" "$actual"
    else
        fail_count=$((fail_count + 1)); printf 'FAIL  %-68s expected %q, got %q\n' "$case_name" "$expected" "$actual"
    fi
}

assert_contains() {
    local case_name="$1" needle="$2" haystack="$3"
    case "$haystack" in
        *"$needle"*) pass_count=$((pass_count + 1)); printf 'PASS  %-68s contains %q\n' "$case_name" "$needle" ;;
        *) fail_count=$((fail_count + 1)); printf 'FAIL  %-68s missing %q in %q\n' "$case_name" "$needle" "$haystack" ;;
    esac
}

decision() { [ -n "$1" ] && printf '%s' "$1" | jq -r '.decision // "none"' 2>/dev/null || echo none; }
reason()   { printf '%s' "$1" | jq -r '.reason // ""' 2>/dev/null; }

now_iso() { date -u +"%Y-%m-%dT%H:%M:%S+00:00"; }

# Sets the global PROJ.
fresh_project() {
    PROJ="${TMP_ROOT}/$1"
    rm -rf "$PROJ"
    mkdir -p "$PROJ/.claude" "$PROJ/docs/plans/demo"
}

write_state() {
    printf '{"schema_version":2,"task_slug":"demo","started_at":"%s","updated_at":"%s","git_flow":{"task_type":"feature","base_branch":"main"}}\n' \
        "$(now_iso)" "$(now_iso)" > "$1/.claude/.sdlc-run-active.json"
}

# $1 = project, $2 = agent_type, $3 = description, $4 = agent_id
write_dispatch() {
    local log="$1/docs/plans/demo/_usage.jsonl" ts
    ts=$(now_iso)
    jq -cn --arg ts "$ts" --arg at "$2" --arg d "$3" '{event:"pending",ts:$ts,agent_type:$at,description:$d,
        phase:(if ($d|startswith("Phase ")) then ($d|sub("^Phase [^:]*: ";"")|sub(" — .*$";"")|sub(" \\[pass:.*$";"")) else null end),
        aspect:(($d|capture(" — (?<a>[^ \\[]+)")|.a) // null),
        pass:(($d|capture("\\[pass:(?<p>[^\\]]+)\\]")|.p) // null)}' >> "$log"
    jq -cn --arg ts "$ts" --arg at "$2" --arg id "$4" '{event:"start",ts:$ts,agent_id:$id,agent_type:$at}' >> "$log"
}

# $1 = project, $2 = agent_type, $3 = agent_id, $4 = last message, $5 = stop_hook_active
run_guard() {
    bash "$GUARD" <<EOF
{"hook_event_name":"SubagentStop","cwd":"$1","session_id":"s1","agent_id":"$3","agent_type":"$2","stop_hook_active":${5:-false},"last_assistant_message":$(printf '%s' "$4" | jq -Rs .)}
EOF
}

QA_OK='FRAMEWORK: Vitest
TESTS: added=4 passing=4 failing=0 skipped=0
COVERAGE: ~85% on changed code
ITERATIONS_USED: 1
STATUS: complete
OPEN_ISSUES: []'

echo "=== phase-output-guard ==="
echo

fresh_project "no-state"
write_dispatch "$PROJ" "sdlc:qa-engineer" "Phase 3/4: qa" "a1"
OUT=$(run_guard "$PROJ" "sdlc:qa-engineer" "a1" "nothing here")
assert_eq "no run state -> quiet" "none" "$(decision "$OUT")"

fresh_project "nested"
write_state "$PROJ"
write_dispatch "$PROJ" "Explore" "Find similar features" "a2"
OUT=$(run_guard "$PROJ" "Explore" "a2" "some exploration")
assert_eq "nested dispatch (free-form description) -> quiet" "none" "$(decision "$OUT")"

fresh_project "already-blocked"
write_state "$PROJ"
write_dispatch "$PROJ" "sdlc:qa-engineer" "Phase 3/4: qa" "a3"
OUT=$(run_guard "$PROJ" "sdlc:qa-engineer" "a3" "nothing here" true)
assert_eq "stop_hook_active -> quiet (never block twice)" "none" "$(decision "$OUT")"

fresh_project "qa-ok"
write_state "$PROJ"
write_dispatch "$PROJ" "sdlc:qa-engineer" "Phase 3/4: qa" "a4"
printf '# QA Report\n' > "$PROJ/docs/plans/demo/03-qa.md"
OUT=$(run_guard "$PROJ" "sdlc:qa-engineer" "a4" "$QA_OK")
assert_eq "qa: file present + required lines -> quiet" "none" "$(decision "$OUT")"

fresh_project "qa-aspect-ok"
write_state "$PROJ"
write_dispatch "$PROJ" "sdlc:qa-engineer" "Phase 3/4: qa — frontend" "a4b"
printf '# QA Report\n' > "$PROJ/docs/plans/demo/03-qa-frontend.md"
OUT=$(run_guard "$PROJ" "sdlc:qa-engineer" "a4b" "$QA_OK")
assert_eq "qa aspect fan-out: aspect-suffixed file is accepted" "none" "$(decision "$OUT")"

fresh_project "qa-missing-file"
write_state "$PROJ"
write_dispatch "$PROJ" "sdlc:qa-engineer" "Phase 3/4: qa" "a5"
OUT=$(run_guard "$PROJ" "sdlc:qa-engineer" "a5" "$QA_OK")
assert_eq "qa: deliverable missing -> block" "block" "$(decision "$OUT")"
assert_contains "qa: reason names the expected path" "docs/plans/demo/03-qa.md" "$(reason "$OUT")"

fresh_project "sec-clean-empty"
write_state "$PROJ"
write_dispatch "$PROJ" "sdlc:security-analyst" "Phase 3/4: security" "a6"
printf '# Security Review\n' > "$PROJ/docs/plans/demo/04-security.md"
OUT=$(run_guard "$PROJ" "sdlc:security-analyst" "a6" 'ISSUES_FOUND: critical=0 high=0 medium=0 low=0
MUST_FIX: []
RECOMMENDATIONS: []
ENTRY_POINTS_CHECKED: none
CALLERS_TRACED: none
STATUS: clean')
assert_eq "security: clean with no entry points / callers -> block" "block" "$(decision "$OUT")"
assert_contains "security: reason explains fact-forcing" "ENTRY_POINTS_CHECKED" "$(reason "$OUT")"

fresh_project "sec-clean-real"
write_state "$PROJ"
write_dispatch "$PROJ" "sdlc:security-analyst" "Phase 3/4: security" "a7"
printf '# Security Review\n' > "$PROJ/docs/plans/demo/04-security.md"
OUT=$(run_guard "$PROJ" "sdlc:security-analyst" "a7" 'ISSUES_FOUND: critical=0 high=0 medium=0 low=0
MUST_FIX: []
RECOMMENDATIONS: []
ENTRY_POINTS_CHECKED: [routes/api.php, app/Http/Controllers/BillingController.php]
CALLERS_TRACED: [BillingService::charge]
STATUS: clean')
assert_eq "security: clean with real analysis -> quiet" "none" "$(decision "$OUT")"

fresh_project "dev-missing-line"
write_state "$PROJ"
write_dispatch "$PROJ" "laravel-plugin:laravel-architect" "Phase 2/4: development — backend [pass:implement]" "a8"
printf '# Development\n' > "$PROJ/docs/plans/demo/02-development-backend.md"
OUT=$(run_guard "$PROJ" "laravel-plugin:laravel-architect" "a8" 'FILES CREATED: [app/Actions/Foo.php]
DECISIONS: - one
BLOCKERS:')
assert_eq "development implement: missing FILES MODIFIED -> block" "block" "$(decision "$OUT")"
assert_contains "development implement: reason names the missing label" "FILES MODIFIED:" "$(reason "$OUT")"

fresh_project "dev-plan-ok"
write_state "$PROJ"
write_dispatch "$PROJ" "laravel-plugin:laravel-architect" "Phase 2/4: development — backend [pass:plan]" "a9"
printf '# Plan\n' > "$PROJ/docs/plans/demo/02-development-plan-backend.md"
OUT=$(run_guard "$PROJ" "laravel-plugin:laravel-architect" "a9" "Planned files: a, b")
assert_eq "development plan: file present, no mandatory lines -> quiet" "none" "$(decision "$OUT")"

fresh_project "oversized"
write_state "$PROJ"
write_dispatch "$PROJ" "sdlc:qa-engineer" "Phase 3/4: qa" "a10"
printf '# QA Report\n' > "$PROJ/docs/plans/demo/03-qa.md"
BIG="$QA_OK
$(head -c 13000 /dev/zero | tr '\0' 'x')"
OUT=$(run_guard "$PROJ" "sdlc:qa-engineer" "a10" "$BIG")
assert_eq "oversized compact summary -> block" "block" "$(decision "$OUT")"
assert_contains "oversized: reason states the 3000-token budget" "3000" "$(reason "$OUT")"

fresh_project "fifo"
write_state "$PROJ"
write_dispatch "$PROJ" "sdlc:qa-engineer" "Phase 3/4: qa — backend" "b1"
write_dispatch "$PROJ" "sdlc:qa-engineer" "Phase 3/4: qa — frontend" "b2"
printf '# QA\n' > "$PROJ/docs/plans/demo/03-qa-backend.md"
OUT=$(run_guard "$PROJ" "sdlc:qa-engineer" "b2" "$QA_OK")
assert_eq "FIFO pairing: second start maps to second pending (frontend file missing)" "block" "$(decision "$OUT")"
assert_contains "FIFO pairing: reason names the frontend path" "03-qa-frontend.md" "$(reason "$OUT")"

echo
printf '%d passed, %d failed\n' "$pass_count" "$fail_count"
[ "$fail_count" -eq 0 ]
