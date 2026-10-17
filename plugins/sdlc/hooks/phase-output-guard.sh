#!/usr/bin/env bash
# SubagentStop hook: hold a pipeline phase agent until its handoff contract is satisfied.
#
# The orchestrator's 3d/3e validation used to re-dispatch an agent that forgot its
# deliverable file or a required summary line — a full new agent with a cold cache. This hook
# checks the contract while the agent is still alive and, on a violation, returns
# `{"decision":"block","reason":…}`. On SubagentStop that does NOT deny anything: it keeps the
# subagent running and delivers `reason` as its next instruction (hooks reference, "Stop
# decision control"), so the agent finishes its own work in-place.
#
# Contract:
#   - Active ONLY while a fresh .claude/.sdlc-run-active.json exists. Outside a run, silent.
#   - Only pipeline phase dispatches are checked. The dispatch is found the same way
#     usage-report.sh pairs rows: this agent_id's `start` row, matched FIFO to the earliest
#     unmatched `pending` row of the same bare agent_type. A pending with phase null is a
#     nested dispatch (a skill, Explore) and is left alone.
#   - `stop_hook_active == true` means this hook already blocked once for this agent. It never
#     blocks twice: a second miss is the orchestrator's call, not an infinite loop.
#   - Prints nothing when the contract holds. Fails open on every error.
set -uo pipefail

COMPACT_BUDGET_TOKENS=3000

# shellcheck source=_telemetry-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_telemetry-lib.sh"

quiet() { exit 0; }

payload=$(cat 2>/dev/null) || quiet
[ -n "$payload" ] || quiet
command -v jq >/dev/null 2>&1 || quiet
[ "$(json_get "$payload" "hook_event_name")" = "SubagentStop" ] || quiet
[ "$(json_get "$payload" "stop_hook_active")" != "true" ] || quiet

agent_id=$(json_get "$payload" "agent_id")
[ -n "$agent_id" ] || quiet
agent_type=$(bare_agent "$(json_get "$payload" "agent_type")")
[ -n "$agent_type" ] || quiet

root=$(resolve_project_root "$payload")
state=$(fresh_state_json "$root") || quiet
slug=$(json_get "$state" "task_slug")
[ -n "$slug" ] || quiet

log="${root}/docs/plans/${slug}/_usage.jsonl"
[ -f "$log" ] || quiet

# FIFO pairing identical to usage-report.sh: each start consumes the earliest pending of its
# agent_type; the pending paired with THIS agent_id is the dispatch under review.
dispatch=$(jq -c -R 'fromjson? // empty' "$log" 2>/dev/null \
    | jq -sc --arg id "$agent_id" --arg at "$agent_type" '
        reduce .[] as $r ({p: {}, hit: null};
          if $r.event == "pending" then .p[$r.agent_type // ""] += [$r]
          elif $r.event == "start" then
            ($r.agent_type // "") as $t
            | ((.p[$t] // [])[0] // null) as $pend
            | .p[$t] = ((.p[$t] // [])[1:])
            | if $r.agent_id == $id and .hit == null then .hit = ($pend // {}) else . end
          else . end)
        | .hit // empty' 2>/dev/null)
[ -n "$dispatch" ] || quiet

phase=$(json_get "$dispatch" "phase")
[ -n "$phase" ] || quiet
aspect=$(json_get "$dispatch" "aspect")
pass=$(json_get "$dispatch" "pass")

suffix=""
[ -n "$aspect" ] && suffix="-${aspect}"

expected_file=""
required=""
case "$pass" in
    fix)    required="FIXES_APPLIED:" ;;
    verify) ;;
    plan)   expected_file="02-development-plan${suffix}.md" ;;
    implement)
        expected_file="02-development${suffix}.md"
        required="FILES CREATED:|FILES MODIFIED:"
        ;;
    *)
        case "$phase" in
            business_analysis) expected_file="01-business-analysis.md"; required="SCOPE:|COMPLEXITY:" ;;
            development)       expected_file="02-development${suffix}.md"; required="FILES CREATED:|FILES MODIFIED:" ;;
            database)          expected_file="02-development-database.md"; required="FILES CREATED:|FILES MODIFIED:" ;;
            qa)                expected_file="03-qa${suffix}.md"; required="TESTS:|ITERATIONS_USED:|STATUS:" ;;
            security)          expected_file="04-security.md"; required="ISSUES_FOUND:|STATUS:|ENTRY_POINTS_CHECKED:|CALLERS_TRACED:" ;;
            documentation)     expected_file="05-pr.md"; required="PR_URL:" ;;
            post_checks)       ;;
            *)                 quiet ;;
        esac
        ;;
esac

message=$(json_get "$payload" "last_assistant_message")

has_line() {
    printf '%s\n' "$message" | grep -q "^${1}" 2>/dev/null
}

line_value() {
    printf '%s\n' "$message" | awk -v k="^${1}" '$0 ~ k { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }' | tr -d '[]' | tr -d ' '
}

problems=""
add_problem() { problems="${problems}
- $1"; }

if [ -n "$expected_file" ] && [ ! -s "${root}/docs/plans/${slug}/${expected_file}" ]; then
    add_problem "The full deliverable is missing: write it to docs/plans/${slug}/${expected_file} now, then return the compact summary again."
fi

missing=""
IFS="|"
for label in $required; do
    [ -n "$label" ] || continue
    has_line "$label" || missing="${missing} \`${label}\`"
done
unset IFS
[ -z "$missing" ] || add_problem "The compact summary must start these lines at column 0:${missing}. Add them (a value of \"none\" or \"[]\" is fine when there is nothing to report)."

if [ "$phase" = security ] && [ -z "$pass" ] && has_line "STATUS:"; then
    status=$(line_value "STATUS:")
    entries=$(line_value "ENTRY_POINTS_CHECKED:" | tr '[:upper:]' '[:lower:]')
    callers=$(line_value "CALLERS_TRACED:" | tr '[:upper:]' '[:lower:]')
    if [ "$status" = clean ]; then
        case "${entries:-none}|${callers:-none}" in
            none\|none|"|"|none\||\|none)
                add_problem "STATUS: clean is a conclusion, and ENTRY_POINTS_CHECKED / CALLERS_TRACED are both empty — that is an absence of analysis. Read the changed files' entry points (routes, handlers, CLI commands), follow the call sites of the changed symbols, then list what you actually read and traced in those two lines."
                ;;
        esac
    fi
fi

chars=${#message}
tokens=$(( chars / 4 ))
if [ "$tokens" -gt "$COMPACT_BUDGET_TOKENS" ]; then
    add_problem "The compact summary is ~${tokens} tokens; the handoff budget is ${COMPACT_BUDGET_TOKENS}. Detail belongs in the deliverable file, not the return value — return only the labelled summary lines."
fi

[ -n "$problems" ] || quiet

reason="Phase handoff contract not yet satisfied for ${phase}${aspect:+ — $aspect}${pass:+ [pass:$pass]} (the orchestrator validates exactly this and would otherwise re-dispatch you from scratch):${problems}"

jq -cn --arg r "$reason" '{decision:"block", reason:$r}'
exit 0
