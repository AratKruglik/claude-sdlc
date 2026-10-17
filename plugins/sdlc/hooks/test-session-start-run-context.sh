#!/usr/bin/env bash
# Test harness for session-start-run-context.sh (SessionStart resume reminder).
#
# Run: bash plugins/sdlc/hooks/test-session-start-run-context.sh
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${HOOK_DIR}/session-start-run-context.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-session-ctx.XXXXXX")
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

context() { [ -n "$1" ] && printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

iso_offset() {
    local off="$1" gnu_expr=""
    case "$off" in
        -*M) gnu_expr="${off#-}"; gnu_expr="${gnu_expr%M} minutes ago" ;;
        -*H) gnu_expr="${off#-}"; gnu_expr="${gnu_expr%H} hours ago" ;;
    esac
    if [ -n "$gnu_expr" ] && date -u -d "$gnu_expr" +"%Y-%m-%dT%H:%M:%S+00:00" 2>/dev/null; then
        return 0
    fi
    date -u -v"$off" +"%Y-%m-%dT%H:%M:%S+00:00"
}

fresh_project() {
    PROJ="${TMP_ROOT}/$1"
    rm -rf "$PROJ"
    mkdir -p "$PROJ/.claude"
}

# $1 = project, $2 = updated_at, $3 = schema_version
write_state() {
    jq -cn --arg ts "$2" --argjson v "${3:-2}" '{schema_version:$v, task_slug:"add-billing", started_at:$ts, updated_at:$ts,
        git_flow:{branch_name:"feature/add-billing"},
        phase_status:{business_analysis:"completed","development/backend":"planned",qa:"pending",security:"pending",documentation:"pending"}}' \
        > "$1/.claude/.sdlc-run-active.json"
}

run_hook() {
    bash "$HOOK" <<EOF
{"hook_event_name":"SessionStart","cwd":"$1","session_id":"s1","source":"$2"}
EOF
}

echo "=== session-start-run-context ==="
echo

fresh_project "none"
assert_eq "no state file -> silent" "" "$(run_hook "$PROJ" compact)"

fresh_project "fresh-compact"
write_state "$PROJ" "$(iso_offset -10M)"
OUT=$(run_hook "$PROJ" compact)
CTX=$(context "$OUT")
assert_contains "fresh state on compact -> names the task" 'task "add-billing"' "$CTX"
assert_contains "fresh state on compact -> names the branch" "feature/add-billing" "$CTX"
assert_contains "fresh state on compact -> progress count" "1/5 phase steps completed" "$CTX"
assert_contains "fresh state on compact -> next unfinished step" "next unfinished: development/backend (planned)" "$CTX"
assert_contains "fresh state on compact -> points at --resume" "/sdlc:start --resume" "$CTX"

fresh_project "fresh-startup"
write_state "$PROJ" "$(iso_offset -10M)"
assert_contains "fresh state on startup -> reminder" "SDLC run in progress" "$(context "$(run_hook "$PROJ" startup)")"

fresh_project "fresh-clear"
write_state "$PROJ" "$(iso_offset -10M)"
assert_eq "source=clear -> silent (not a resume situation)" "" "$(run_hook "$PROJ" clear)"

fresh_project "stale"
write_state "$PROJ" "$(iso_offset -8H)"
assert_eq "stale state -> silent" "" "$(run_hook "$PROJ" compact)"

fresh_project "v1"
write_state "$PROJ" "$(iso_offset -10M)" 1
assert_eq "v1 marker -> silent (not resumable)" "" "$(run_hook "$PROJ" compact)"

echo
printf '%d passed, %d failed\n' "$pass_count" "$fail_count"
[ "$fail_count" -eq 0 ]
