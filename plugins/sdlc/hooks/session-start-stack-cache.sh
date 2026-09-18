#!/usr/bin/env bash
# SessionStart hook: precompute the stack-profile detection (pipeline-orchestrator
# Step 0b / 0b-aspects) once per session, for free, so /sdlc:start and /sdlc:doctor
# don't have to spend LLM tool calls Glob-ing and Read-ing every installed
# plugin's stack.md.
#
# Contract: purely additive side effect, never surfaced to the model.
#   - Prints NOTHING to stdout. This hook fires on every Claude Code session on
#     the machine, including ones that never touch this plugin — any stdout
#     here becomes context injected into ALL of them, which is a token cost
#     paid unconditionally to save tokens conditionally. Silence is the point.
#   - Never blocks session start (SessionStart hooks can't anyway) and never
#     writes a non-zero exit code for anything short of a scripting bug.
#   - Fails open silently: no jq, no detect-stack.sh found, malformed
#     plugin set, unwritable cache dir → do nothing. A missing cache is a
#     supported state (the orchestrator's Step 0b falls back to a full scan).
#
# Claude Code sends a JSON payload on stdin:
#   { "session_id": "...", "cwd": "...", "hook_event_name": "SessionStart",
#     "source": "startup" | "resume" | "clear" | "compact" | "fork", ... }
set -uo pipefail

payload=$(cat 2>/dev/null) || exit 0

if command -v jq >/dev/null 2>&1; then
    source=$(printf '%s' "$payload" | jq -r '.source // empty' 2>/dev/null)
    cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty' 2>/dev/null)
else
    exit 0
fi

# `compact` and `fork` don't change the project on disk — re-detecting there
# just burns CPU for a cache that would come out identical. `startup`,
# `resume`, and `clear` are the sources where the repo state is worth
# re-checking (a resumed session may be days old; the repo may have changed).
case "$source" in
    startup|resume|clear) ;;
    *) exit 0 ;;
esac

[ -n "$cwd" ] && [ -d "$cwd" ] || exit 0

command -v jq >/dev/null 2>&1 || exit 0

# Resolve detect-stack.sh the same way the PreToolUse hook resolves its own
# script: plugin root env var first, then the installed cache copy, then the
# dev-checkout layout (this repo, when testing the plugin from source).
DETECT=""
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && [ -f "${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh" ]; then
    DETECT="${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.sh"
else
    f=$(ls -d "${HOME}/.claude/plugins/cache"/*/sdlc/*/scripts/detect-stack.sh 2>/dev/null | { sort -Vr 2>/dev/null || sort -r; } | head -1)
    if [ -n "$f" ]; then
        DETECT="$f"
    elif [ -f "${PWD}/plugins/sdlc/scripts/detect-stack.sh" ]; then
        DETECT="${PWD}/plugins/sdlc/scripts/detect-stack.sh"
    fi
fi

[ -n "$DETECT" ] || exit 0

bash "$DETECT" --repo "$cwd" --write-cache >/dev/null 2>&1

exit 0
