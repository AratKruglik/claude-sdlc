#!/usr/bin/env bash
# PostToolUse(Agent) hook: hand the orchestrator its per-dispatch telemetry record and the
# running cost total as context, so Step 3d-1 / 3d-3 need no usage-report.sh call and no
# JSON reading on the session model.
#
# Contract:
#   - Active ONLY while a fresh .claude/.sdlc-run-active.json exists, and only for dispatches
#     whose description follows the `Phase N/M: …` contract. Nested dispatches and non-pipeline
#     Agent calls get nothing.
#   - Reads docs/plans/{slug}/_usage.jsonl through scripts/usage-report.sh (read-only) and
#     picks the record for THIS dispatch: same bare agent_type, same phase/aspect/pass, latest
#     started_at.
#   - Emits hookSpecificOutput.additionalContext, at most a dozen lines plus the latest
#     `post_check` findings post-implement-check.sh logged for this agent_id. When the state file
#     carries a numeric max_total_cost_usd and the measured phase total exceeds it, the 💸 block
#     the orchestrator must print verbatim (SKILL.md 3d-3) is included — the decision
#     (continue / stop) stays with the orchestrator and the user.
#   - Fails open on every error; never writes.
set -uo pipefail

COMPACT_BUDGET_TOKENS=3000

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_telemetry-lib.sh
. "${HOOK_DIR}/_telemetry-lib.sh"
REPORT="${HOOK_DIR}/../scripts/usage-report.sh"

quiet() { exit 0; }

payload=$(cat 2>/dev/null) || quiet
[ -n "$payload" ] || quiet
command -v jq >/dev/null 2>&1 || quiet
[ -f "$REPORT" ] || quiet
[ "$(json_get "$payload" "hook_event_name")" = "PostToolUse" ] || quiet
[ "$(json_get "$payload" "tool_name")" = "Agent" ] || quiet

description=$(json_get "$payload" "tool_input.description")
parse_description "$description"
[ -n "$PARSED_PHASE" ] || quiet
agent_type=$(bare_agent "$(json_get "$payload" "tool_input.subagent_type")")
[ -n "$agent_type" ] || quiet

root=$(resolve_project_root "$payload")
state=$(fresh_state_json "$root") || quiet
slug=$(json_get "$state" "task_slug")
[ -n "$slug" ] || quiet

report=$(bash "$REPORT" "$slug" --project-root "$root" 2>/dev/null) || quiet
[ -n "$report" ] || quiet

text=$(printf '%s' "$report" | jq -r \
    --arg at "$agent_type" --arg ph "$PARSED_PHASE" --arg as "$PARSED_ASPECT" --arg pa "$PARSED_PASS" \
    --arg desc "$description" --argjson state "$state" --argjson budget "$COMPACT_BUDGET_TOKENS" '
    def nz: if . == null then "—" else tostring end;
    def money: if . == null then "—" else "$" + (tostring) end;
    ([ .dispatches[]
       | select((.nested | not) and .agent_type == $at and .phase == $ph
                and ((.aspect // "") == $as) and ((.pass // "") == $pa)) ]
     | sort_by(.started_at // "") | last) as $r
    | if $r == null then empty else
      ("SDLC telemetry for \($desc): usage_source=\($r.status | if . == "completed" then "measured" else . end) model_id=\($r.model | nz) input=\($r.input_tokens | nz) (cache_read=\($r.cache_read_input_tokens | nz), cache_creation=\($r.cache_creation_input_tokens | nz)) output=\($r.output_tokens | nz) turns=\($r.turns | nz) cost_usd=\($r.cost_usd | nz) pricing_note=\($r.pricing_note | nz)"),
      ("Running total: phases=\(.total_cost_usd | money) nested=\(.nested_cost_usd | money) (measured rows only)"),
      (if (($r.last_message_chars // 0) / 4 | floor) > $budget
       then "compact_handoff_violation: true (~\(($r.last_message_chars / 4) | floor) tokens > \($budget))" else empty end),
      (($state.max_total_cost_usd) as $cap
       | if ($cap | type) == "number" and .total_cost_usd > $cap then
           ([ $state.resolved_phases[]?[]? ]
            | map(select(. as $p
                         | [ ($state.phase_status // {}) | to_entries[]
                             | select((.key | split("/")[0]) == $p)
                             | select(.value | IN("completed","skipped","skipped-cost-cap") | not) ]
                         | length > 0))
            | join(", ")) as $remaining
           | "💸 Cost cap exceeded for workflow '\''\($state.active_workflow // "default")'\''\n   Cap: $\($cap)   Spent so far: $\(.total_cost_usd) (through phase \($ph))\n   Remaining phases: \(if $remaining == "" then "none" else $remaining end)\nAsk the user: continue / stop here (SKILL.md 3d-3)."
         else empty end)
    end' 2>/dev/null)
[ -n "$text" ] || quiet

# Typecheck / lint findings a stack's post-implement-check.sh logged for this agent.
agent_id=$(printf '%s' "$report" | jq -r --arg at "$agent_type" --arg ph "$PARSED_PHASE" --arg as "$PARSED_ASPECT" --arg pa "$PARSED_PASS" '
    [ .dispatches[] | select((.nested | not) and .agent_type == $at and .phase == $ph
                             and ((.aspect // "") == $as) and ((.pass // "") == $pa)) ]
    | sort_by(.started_at // "") | last | .agent_id // empty' 2>/dev/null)
if [ -n "$agent_id" ]; then
    check=$(jq -R 'fromjson? // empty' "${root}/docs/plans/${slug}/_usage.jsonl" 2>/dev/null \
        | jq -rs --arg id "$agent_id" '[.[] | select(.event == "post_check" and .agent_id == $id) | .message] | last // empty' 2>/dev/null)
    [ -z "$check" ] || text="${text}
${check}"
fi

jq -cn --arg t "$text" '{hookSpecificOutput:{hookEventName:"PostToolUse", additionalContext:$t}}'
exit 0
