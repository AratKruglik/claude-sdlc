#!/usr/bin/env bash
# PreToolUse(Agent) + SubagentStart hook: append dispatch events to the run's usage log.
#
# Contract: purely additive side effect, never surfaced to the model.
#   - Prints NOTHING to stdout (an empty PreToolUse response means "allow"; SubagentStart
#     is notification-only). Both events fire in every Claude Code session on the
#     machine, so any output here would be context injected into unrelated sessions.
#   - Writes only when a FRESH .claude/.sdlc-run-active.json exists under the payload
#     cwd (then CLAUDE_PROJECT_DIR). Outside a pipeline run this hook is a no-op.
#   - Fails open silently: no jq and no python3, unreadable marker, unwritable log →
#     exit 0 with nothing written.
#
# Rows (one JSON object per line, appended to docs/plans/{task_slug}/_usage.jsonl):
#   PreToolUse    → {"event":"pending","ts","agent_type","description","phase","aspect","pass"}
#   SubagentStart → {"event":"start","ts","agent_id","agent_type"}
# `agent_type` is always the bare name (plugin prefix stripped). `phase` is null when
# the description does not follow the orchestrator's `Phase N/M: …` contract — that is
# how nested dispatches (superpowers skills, Explore) are recognised by usage-report.sh.
set -uo pipefail

# shellcheck source=_telemetry-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_telemetry-lib.sh"

payload=$(cat 2>/dev/null) || exit 0
[ -n "$payload" ] || exit 0

tool=$(json_tool) || exit 0

event=$(json_get "$payload" "hook_event_name")
root=$(resolve_project_root "$payload")
slug=$(active_task_slug "$root") || exit 0
log=$(usage_log_path "$root" "$slug") || exit 0
ts=$(now_iso)

case "$event" in
    PreToolUse)
        [ "$(json_get "$payload" "tool_name")" = "Agent" ] || exit 0
        agent_type=$(bare_agent "$(json_get "$payload" "tool_input.subagent_type")")
        [ -n "$agent_type" ] || exit 0
        description=$(json_get "$payload" "tool_input.description")
        parse_description "$description"
        if [ "$tool" = jq ]; then
            row=$(jq -cn --arg ts "$ts" --arg at "$agent_type" --arg d "$description" \
                --arg ph "$PARSED_PHASE" --arg as "$PARSED_ASPECT" --arg pa "$PARSED_PASS" \
                '{event:"pending", ts:$ts, agent_type:$at, description:$d,
                  phase:(if $ph=="" then null else $ph end),
                  aspect:(if $as=="" then null else $as end),
                  pass:(if $pa=="" then null else $pa end)}')
        else
            row=$(python3 -c '
import json, sys
ts, at, d, ph, as_, pa = sys.argv[1:7]
print(json.dumps({"event":"pending","ts":ts,"agent_type":at,"description":d,
    "phase":ph or None,"aspect":as_ or None,"pass":pa or None}, separators=(",",":")))
' "$ts" "$agent_type" "$description" "$PARSED_PHASE" "$PARSED_ASPECT" "$PARSED_PASS")
        fi
        ;;
    SubagentStart)
        agent_id=$(json_get "$payload" "agent_id")
        agent_type=$(bare_agent "$(json_get "$payload" "agent_type")")
        [ -n "$agent_id" ] || exit 0
        if [ "$tool" = jq ]; then
            row=$(jq -cn --arg ts "$ts" --arg id "$agent_id" --arg at "$agent_type" \
                '{event:"start", ts:$ts, agent_id:$id, agent_type:$at}')
        else
            row=$(python3 -c '
import json, sys
print(json.dumps({"event":"start","ts":sys.argv[1],"agent_id":sys.argv[2],"agent_type":sys.argv[3]}, separators=(",",":")))
' "$ts" "$agent_id" "$agent_type")
        fi
        ;;
    *) exit 0 ;;
esac

[ -n "${row:-}" ] && append_row "$log" "$row"
exit 0
