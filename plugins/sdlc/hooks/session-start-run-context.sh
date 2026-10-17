#!/usr/bin/env bash
# SessionStart hook: remind a session that an SDLC run is in progress in this project.
#
# After a compaction, a resume or a fresh start, the orchestrator has lost its skill text and
# its CONTEXT, but the state file still holds every decision. Three lines of context here save
# a confused session from re-running Steps 0a–2 (or starting a second run) before it finds
# the file on its own.
#
# Contract:
#   - Prints ONLY when a fresh (updated_at < 6h) schema v2 state file exists under the
#     payload cwd, for sources startup / resume / compact. Every other case is silent: this
#     fires in every Claude Code session on the machine, and unconditional output would be
#     context paid by all of them.
#   - Read-only. Fails open on every error.
set -uo pipefail

# shellcheck source=_telemetry-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_telemetry-lib.sh"

quiet() { exit 0; }

payload=$(cat 2>/dev/null) || quiet
[ -n "$payload" ] || quiet
command -v jq >/dev/null 2>&1 || quiet
[ "$(json_get "$payload" "hook_event_name")" = "SessionStart" ] || quiet

case "$(json_get "$payload" "source")" in
    startup|resume|compact) ;;
    *) quiet ;;
esac

root=$(resolve_project_root "$payload")
state=$(fresh_state_json "$root") || quiet

text=$(printf '%s' "$state" | jq -r '
    select((.schema_version // 1) >= 2)
    | (.phase_status // {}) as $ps
    | ($ps | length) as $total
    | ([ $ps | to_entries[] | select(.value | IN("completed","skipped","skipped-cost-cap")) ] | length) as $done
    | ([ $ps | to_entries[] | select(.value | IN("completed","skipped","skipped-cost-cap") | not) ] | first) as $next
    | "SDLC run in progress: task \"\(.task_slug)\" on branch \(.git_flow.branch_name // "?"), \($done)/\($total) phase steps completed; next unfinished: \(if $next == null then "none" else "\($next.key) (\($next.value))" end). Continue with /sdlc:start --resume (orchestrator Step R), which re-loads the pipeline-orchestrator skill."' 2>/dev/null)
[ -n "$text" ] || quiet

jq -cn --arg t "$text" '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$t}}'
exit 0
