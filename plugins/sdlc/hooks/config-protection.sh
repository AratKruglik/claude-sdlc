#!/usr/bin/env bash
# PreToolUse(Edit|Write) hook: protect a stack's tooling config during a pipeline run.
#
# Invoked with the protected globs as arguments — each stack plugin passes its own list from
# its hooks.json, so this script holds the policy and the stacks hold the file names:
#
#   bash config-protection.sh 'pint.json' 'phpstan.neon*' '.editorconfig'
#
# Contract:
#   - Active ONLY while a fresh .claude/.sdlc-run-active.json exists AND the run's
#     git_flow.task_type is not `chore`. A chore run is how a maintainer deliberately changes
#     tooling config, so the guard must not stand in its way; outside a run it never fires at
#     all, and a human editing pint.json by hand is never blocked.
#   - Denies with a reason that says what to do instead. Fails open on every error.
#
# Why deny rather than warn: an agent that loosens a linter rule to make its own diff pass has
# silently widened the project's standards to fit one feature. That is not visible in the diff
# review unless someone notices the config file among the source changes.
set -uo pipefail

# shellcheck source=_telemetry-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_telemetry-lib.sh"

allow() { exit 0; }

[ "$#" -gt 0 ] || allow

payload=$(cat 2>/dev/null) || allow
[ -n "$payload" ] || allow
json_tool >/dev/null || allow

[ "$(json_get "$payload" "hook_event_name")" = "PreToolUse" ] || allow
case "$(json_get "$payload" "tool_name")" in
    Edit|Write) ;;
    *) allow ;;
esac

target=$(json_get "$payload" "tool_input.file_path")
[ -n "$target" ] || allow

root=$(resolve_project_root "$payload")
state=$(fresh_state_json "$root") || allow
[ "$(json_get "$state" "git_flow.task_type")" != "chore" ] || allow

# Match on the path relative to the project root, and on the bare basename, so that a glob
# like `pint.json` protects the file wherever the tool call spells the path from.
rel="${target#"$root"/}"
base="${target##*/}"

for glob in "$@"; do
    # shellcheck disable=SC2254  # $glob is a pattern on purpose
    case "$rel" in $glob) ;; *) case "$base" in $glob) ;; *) continue ;; esac ;; esac

    reason="\`${base}\` is this stack's tooling configuration, and this is an SDLC pipeline run (task_type=$(json_get "$state" "git_flow.task_type")). Editing it here would change the standard the whole project is measured against in order to make one feature's diff pass, which a diff review is unlikely to catch. Fix the code to satisfy the existing rules instead. If the rule itself is genuinely wrong, that is its own change: raise it with the user, or run it as a \`chore\` task where this guard stands down."
    if command -v jq >/dev/null 2>&1; then
        jq -cn --arg r "$reason" \
            '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    else
        python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":sys.argv[1]}},separators=(",",":")))' "$reason" 2>/dev/null || exit 0
    fi
    exit 0
done

allow
