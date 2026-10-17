#!/usr/bin/env bash
# SubagentStop hook: run the stack's typecheck/lint over what an architect just changed.
#
# Invoked with the check command as arguments, from the stack plugin's hooks.json:
#
#   bash post-implement-check.sh --lang node -- node_modules/.bin/tsc --noEmit
#   bash post-implement-check.sh --lang php --service-hint php -- ./vendor/bin/phpstan analyse
#
# `--lang` and `--service-hint` go to _runner-lib.sh, which decides whether the stack applies
# to this project and whether the tool runs locally or inside a running compose service.
#
# Contract:
#   - Active ONLY while a fresh .claude/.sdlc-run-active.json exists. Outside a run, silent.
#   - Runs once per finished architect, batched — not per edit. A per-edit typecheck reports
#     errors the next edit was about to fix, which trains everyone to ignore it.
#   - Skips silently when the language does not apply or the tool is neither installed locally
#     nor inside a running compose service: a missing `tsc` is a project that does not use it,
#     not a finding.
#   - Output goes to `systemMessage`, capped at 40 lines. It is advice for the orchestrator's
#     3e validation, never a block. SubagentStop cannot deny a permission; it can return
#     `decision: block` to keep the subagent running (phase-output-guard.sh does that for the
#     handoff contract), but a type error is deliberately left for the orchestrator to route
#     into a retry rather than forced on the agent here.
#   - Fails open on every error, including a non-zero exit from the check itself.
set -uo pipefail

MAX_LINES=40

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_telemetry-lib.sh
. "${HOOK_DIR}/_telemetry-lib.sh"
# shellcheck source=_runner-lib.sh
. "${HOOK_DIR}/_runner-lib.sh"

quiet() { exit 0; }

lang="any"; hint=""
while [ $# -gt 0 ]; do
    case "$1" in
        --lang)         lang="${2:-any}"; shift 2 ;;
        --service-hint) hint="${2:-}"; shift 2 ;;
        --)             shift; break ;;
        *)              break ;;
    esac
done

[ "$#" -gt 0 ] || quiet

payload=$(cat 2>/dev/null) || quiet
[ -n "$payload" ] || quiet
json_tool >/dev/null || quiet
[ "$(json_get "$payload" "hook_event_name")" = "SubagentStop" ] || quiet

root=$(resolve_project_root "$payload")
state=$(fresh_state_json "$root") || quiet

base=$(json_get "$state" "git_flow.base_branch")
[ -n "$base" ] || quiet

command -v git >/dev/null 2>&1 || quiet
changed=$(cd "$root" 2>/dev/null && git diff --name-only "${base}...HEAD" 2>/dev/null) || quiet
[ -n "$changed" ] || quiet

# Resolution runs against the project root so a project-relative command (./vendor/bin/phpstan,
# node_modules/.bin/tsc) means "not installed" and "not this project's toolchain" are the same
# silent answer, and a tool that only lives in a compose service still gets its one batched run.
runner_resolve "$lang" "$root" "$hint" "$@" || quiet

output=$(runner_exec "$root" "$@" 2>&1) && quiet
[ -n "$output" ] || quiet

agent=$(bare_agent "$(json_get "$payload" "agent_type")")
trimmed=$(printf '%s\n' "$output" | head -n "$MAX_LINES")
total=$(printf '%s\n' "$output" | wc -l | tr -d ' ')
if [ "$total" -gt "$MAX_LINES" ]; then
    trimmed="${trimmed}
… ${total} lines total; re-run \`$*\` for the rest."
fi

message="Post-implement check after ${agent:-the architect} (\`$*\`) reported problems:

${trimmed}

These are diagnostics, not a verdict: some may come from work another aspect has not finished.
Treat them as a retry hint for this aspect's implement-pass validation."

if command -v jq >/dev/null 2>&1; then
    jq -cn --arg m "$message" '{systemMessage:$m}'
else
    python3 -c 'import json,sys; print(json.dumps({"systemMessage":sys.argv[1]},separators=(",",":")))' "$message" 2>/dev/null || exit 0
fi
exit 0
