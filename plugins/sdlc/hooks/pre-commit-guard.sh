#!/usr/bin/env bash
# PreToolUse(Bash) hook: guard `git commit` during an SDLC pipeline run.
#
# Contract:
#   - Active ONLY while a fresh .claude/.sdlc-run-active.json exists under the payload cwd
#     (then CLAUDE_PROJECT_DIR). Outside a run it allows everything, silently. This hook fires
#     in every Claude Code session on the machine; a guard that second-guessed a human's own
#     commits would be a bug, not a feature.
#   - Denies `--no-verify` and staged secrets. Warns on debug leftovers without denying.
#   - Fails open: no jq and no python3, unreadable state, git unavailable → allow.
#
# Deny output is the PreToolUse permissionDecision JSON; `permissionDecisionReason` is what the
# model sees, so it names the file and line rather than just the rule.
set -uo pipefail

# shellcheck source=_telemetry-lib.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_telemetry-lib.sh"

allow() { exit 0; }

deny() {
    local reason="$1"
    if command -v jq >/dev/null 2>&1; then
        jq -cn --arg r "$reason" \
            '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
    else
        python3 -c 'import json,sys; print(json.dumps({"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":sys.argv[1]}},separators=(",",":")))' "$reason" 2>/dev/null || exit 0
    fi
    exit 0
}

warn() {
    local msg="$1"
    if command -v jq >/dev/null 2>&1; then
        jq -cn --arg m "$msg" '{systemMessage:$m}'
    fi
    exit 0
}

payload=$(cat 2>/dev/null) || allow
[ -n "$payload" ] || allow
json_tool >/dev/null || allow

[ "$(json_get "$payload" "hook_event_name")" = "PreToolUse" ] || allow
[ "$(json_get "$payload" "tool_name")" = "Bash" ] || allow

command=$(json_get "$payload" "tool_input.command")
case "$command" in
    *"git commit"*) ;;
    *) allow ;;
esac

root=$(resolve_project_root "$payload")
fresh_state_json "$root" >/dev/null || allow

case "$command" in
    *--no-verify*|*" -n "*)
        deny "This run is an SDLC pipeline run, and \`git commit --no-verify\` skips the project's own pre-commit hooks — the checks a reviewer will assume ran. Commit without it. If a hook is genuinely wrong, fix or disable the hook in the project config so the change is visible in the diff, rather than bypassing it invisibly for one commit."
        ;;
esac

command -v git >/dev/null 2>&1 || allow
staged=$(cd "$root" 2>/dev/null && git diff --cached -U0 2>/dev/null) || allow
[ -n "$staged" ] || allow

# Only added lines can introduce a secret; a removed one is the fix, not the defect.
added=$(printf '%s\n' "$staged" | grep -E '^(\+\+\+ |\+)' || true)
[ -n "$added" ] || allow

# Walks the added lines carrying the current +++ path, so a hit can be reported as file:line
# rather than as a naked pattern name. Line numbers come from the @@ hunk headers.
locate() {
    local pattern="$1"
    printf '%s\n' "$staged" | awk -v pat="$pattern" '
        /^\+\+\+ / { file = substr($0, 7); next }
        /^@@ / { split($3, a, ","); line = a[1] + 0; if (line < 0) line = -line; next }
        /^\+/ {
            body = substr($0, 2)
            if (body ~ pat) { print file ":" line; found = 1; exit }
            line++
            next
        }
        END { if (!found) exit 1 }
    ' 2>/dev/null
}

for rule in \
    'sk-[A-Za-z0-9_-]{20,}|an OpenAI/Anthropic-style API key' \
    'AKIA[0-9A-Z]{16}|an AWS access key id' \
    '-----BEGIN [A-Z ]*PRIVATE KEY|a private key block' \
    '(password|secret|token|api_?key)[[:space:]]*[:=][[:space:]]*.[^"'"'"']{8,}|a hardcoded credential literal'
do
    pattern="${rule%%|*}"
    label="${rule#*|}"
    if hit=$(locate "$pattern"); then
        deny "Staged change at ${hit} looks like ${label}. Commit blocked: a secret in a commit stays in the history even after a later removal, so the fix is to unstage it now, move the value to an environment variable or secret store, and rotate it if it was ever real. If this is a test fixture or a documented example, make that unmistakable in the value itself (for example \`sk-EXAMPLE-not-a-real-key\`) and stage it again."
    fi
done

if debug_hit=$(printf '%s\n' "$staged" | awk '
    /^\+\+\+ / { file = substr($0, 7); next }
    /^\+/ {
        if (file ~ /(test|spec|__tests__|fixtures)/) next
        body = substr($0, 2)
        if (body ~ /console\.log\(|dd\(|var_dump\(|debugger[[:space:]]*;?$|binding\.pry/) { print file; found = 1; exit }
    }
    END { if (!found) exit 1 }
' 2>/dev/null); then
    warn "Heads up: ${debug_hit} stages a debug statement (console.log / dd( / var_dump( / debugger). Not blocking — it may be deliberate — but it is rarely what you want in a reviewed commit."
fi

allow
