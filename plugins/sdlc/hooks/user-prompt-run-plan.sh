#!/usr/bin/env bash
# UserPromptSubmit hook: precompute the /sdlc:start run plan and hand it to the orchestrator.
#
# When the submitted prompt is `/sdlc:start …`, runs scripts/run-plan.sh with the command's
# arguments and injects its JSON as additionalContext, so pipeline-orchestrator Steps 0a–1c
# and the Step 2 slug are read from one block instead of being re-derived with Glob/Read/Bash
# on the session model. The orchestrator still owns every decision that needs the user (the
# branch gate, the approval gate) and every mutation.
#
# Contract:
#   - Prints NOTHING for any other prompt. This hook fires on every prompt in every session
#     on the machine; output here is context the model pays for, so it is emitted only when
#     the plan will actually be consumed.
#   - Fails open silently: no jq, script missing, planner error → exit 0 with no output, and
#     the orchestrator falls back to its inline algorithm.
#   - Never blocks the prompt. The JSON carries `halts[]` for the orchestrator to act on.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLANNER="${HOOK_DIR}/../scripts/run-plan.sh"
MARKER="=== SDLC RUN PLAN (precomputed by hooks/user-prompt-run-plan.sh) ==="
END_MARKER="=== END RUN PLAN ==="
CONTEXT_CAP="${SDLC_RUN_PLAN_CONTEXT_CAP:-9500}"

command -v jq >/dev/null 2>&1 || exit 0
[ -f "$PLANNER" ] || exit 0

payload=$(cat 2>/dev/null) || exit 0
[ -n "$payload" ] || exit 0

prompt=$(jq -r '.prompt // empty' <<<"$payload" 2>/dev/null)
case "$prompt" in
    *[![:space:]]*) ;;
    *) exit 0 ;;
esac
trimmed=$(printf '%s' "$prompt" | sed -E 's/^[[:space:]]+//')
case "$trimmed" in
    "/sdlc:start"|"/sdlc:start "*|"/sdlc:start"$'\n'*) ;;
    *) exit 0 ;;
esac
arguments=$(printf '%s' "$trimmed" | sed -E 's#^/sdlc:start[[:space:]]*##')

cwd=$(jq -r '.cwd // empty' <<<"$payload" 2>/dev/null)
[ -n "$cwd" ] && [ -d "$cwd" ] || cwd="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -d "$cwd" ] || exit 0

args=(--repo "$cwd" --arguments "$arguments")
self_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd -P)
cwd_real=$(cd "$cwd" 2>/dev/null && pwd -P)
[ -n "$self_root" ] && [ "$self_root" = "$cwd_real" ] && [ -f "${cwd}/plugins/sdlc/scripts/run-plan.sh" ] && args+=(--dev-root "$cwd")

headless=false
case "${SDLC_NONINTERACTIVE:-}" in
    true|1) headless=true ;;
    "") case "${CLAUDE_PLUGIN_OPTION_NONINTERACTIVE:-}" in true|1) headless=true ;; esac ;;
esac
[ "$headless" = true ] && args+=(--headless)

plan=$(bash "$PLANNER" "${args[@]}" 2>/dev/null) || exit 0
[ -n "$plan" ] || exit 0
jq -e 'type == "object" and (.error // null) == null' <<<"$plan" >/dev/null 2>&1 || exit 0

# Diagnostics the orchestrator never reads (the unmatched-profile list alone is ~1.5K chars)
# are dropped: additionalContext is capped at 10,000 characters, and past the cap Claude Code
# swaps the text for a 2K preview, which silently loses the fast path.
compact=$(jq -c '
    del(.generated_at, .stack.all_profiles, .stack.matched_profiles, .stack.plugins_root,
        .stack.repo, .stack.stack_md_scanned)
    | if .git_flow.documented_convention_hits then
        .git_flow.documented_convention_hits |= map(.text |= (if length > 200 then .[0:200] + "…" else . end))
      else . end' <<<"$plan" 2>/dev/null) || exit 0

context="${MARKER}
${compact}
${END_MARKER}"
if [ "$(jq -rn --arg c "$context" '$c | length')" -gt "$CONTEXT_CAP" ]; then
    plan_file="${CLAUDE_PLUGIN_DATA:-${TMPDIR:-/tmp}}/run-plan/$(jq -r '.session_id // "session"' <<<"$payload").json"
    mkdir -p "$(dirname "$plan_file")" 2>/dev/null && printf '%s\n' "$compact" > "$plan_file" || exit 0
    context="${MARKER}
The run plan exceeds the hook context cap. Read ${plan_file} once and use its JSON as the run plan.
${END_MARKER}"
fi

jq -cn --arg c "$context" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
exit 0
