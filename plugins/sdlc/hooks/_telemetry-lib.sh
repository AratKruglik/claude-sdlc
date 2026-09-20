#!/usr/bin/env bash
# Shared helpers for the dispatch-telemetry hooks (dispatch-log.sh, subagent-usage.sh).
# Sourced, never executed. Every function is fail-open: on any doubt it returns
# non-zero or an empty string and the caller exits 0 silently.
#
# JSON tool selection: jq when present, python3 otherwise. SDLC_HOOK_JSON_TOOL=python3
# forces the fallback path (used by the test suite to cover it on machines that have jq).

MARKER_MAX_AGE_SECONDS=21600

json_tool() {
    case "${SDLC_HOOK_JSON_TOOL:-}" in
        python3) command -v python3 >/dev/null 2>&1 && { echo python3; return 0; } ;;
        jq)      command -v jq >/dev/null 2>&1 && { echo jq; return 0; } ;;
    esac
    if command -v jq >/dev/null 2>&1; then echo jq; return 0; fi
    if command -v python3 >/dev/null 2>&1; then echo python3; return 0; fi
    return 1
}

# $1 = JSON text, $2 = dotted top-level-or-nested key path (a.b.c). Prints "" when absent.
json_get() {
    local json="$1" path="$2"
    case "$(json_tool)" in
        jq)
            printf '%s' "$json" | jq -r --arg p "$path" '
                getpath($p | split(".")) // empty
                | if type == "string" then . else tojson end' 2>/dev/null
            ;;
        python3)
            printf '%s' "$json" | python3 -c '
import json, sys
path = sys.argv[1].split(".")
try:
    d = json.load(sys.stdin)
    for k in path:
        d = d[k]
    print(d if isinstance(d, str) else json.dumps(d))
except Exception:
    pass
' "$path" 2>/dev/null
            ;;
    esac
}

now_iso() {
    if command -v python3 >/dev/null 2>&1; then
        python3 -c 'from datetime import datetime, timezone; print(datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z")' 2>/dev/null && return 0
    fi
    date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# $1 = ISO 8601 timestamp → epoch seconds, "" when unparsable.
iso_to_epoch() {
    local ts="$1" bsd
    bsd=$(printf '%s' "$ts" | sed -E 's/\.[0-9]+//; s/Z$/+0000/; s/([+-][0-9]{2}):([0-9]{2})$/\1\2/')
    date -u -d "$ts" +%s 2>/dev/null \
        || date -u -j -f "%Y-%m-%dT%H:%M:%S%z" "$bsd" +%s 2>/dev/null \
        || echo ""
}

# $1 = payload JSON. Prints the project root the run marker should live under.
resolve_project_root() {
    local payload="$1" cwd
    cwd=$(json_get "$payload" "cwd")
    if [ -n "$cwd" ] && [ -d "$cwd" ]; then printf '%s' "$cwd"; return 0; fi
    if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then printf '%s' "$CLAUDE_PROJECT_DIR"; return 0; fi
    pwd
}

# $1 = project root. Prints the task_slug when a FRESH run marker exists, else returns 1.
# Freshness keys on updated_at (refreshed by the orchestrator at every phase boundary)
# and falls back to started_at for v1 markers.
active_task_slug() {
    local root="$1" marker json ts epoch now age slug
    marker="${root}/.claude/.sdlc-run-active.json"
    [ -f "$marker" ] || return 1
    json=$(cat "$marker" 2>/dev/null) || return 1
    ts=$(json_get "$json" "updated_at")
    [ -n "$ts" ] || ts=$(json_get "$json" "started_at")
    [ -n "$ts" ] || return 1
    epoch=$(iso_to_epoch "$ts")
    [ -n "$epoch" ] || return 1
    now=$(date -u +%s)
    age=$(( now - epoch ))
    { [ "$age" -ge 0 ] && [ "$age" -lt "$MARKER_MAX_AGE_SECONDS" ]; } || return 1
    slug=$(json_get "$json" "task_slug")
    [ -n "$slug" ] || return 1
    printf '%s' "$slug"
}

# $1 = project root, $2 = task_slug. Prints the usage log path, creating its directory.
usage_log_path() {
    local dir="$1/docs/plans/$2"
    mkdir -p "$dir" 2>/dev/null || return 1
    printf '%s/_usage.jsonl' "$dir"
}

# $1 = path, $2 = one compact JSON row. Single write() so concurrent hooks never interleave.
append_row() {
    printf '%s\n' "$2" >> "$1" 2>/dev/null
}

# Strip a "plugin:" prefix: "sdlc:qa-engineer" → "qa-engineer".
bare_agent() {
    printf '%s' "${1##*:}"
}

# Parse the orchestrator's description contract
#   Phase {N}/{M}: {phase}[ — {aspect}][ [pass:{pass}]]
# into three globals: PARSED_PHASE, PARSED_ASPECT, PARSED_PASS (empty when absent).
# A description that does not follow the contract leaves PARSED_PHASE empty — that is
# how nested, non-pipeline dispatches are recognised downstream.
# shellcheck disable=SC2034  # the three globals are consumed by the sourcing script
parse_description() {
    local description="$1" rest
    PARSED_PHASE=""; PARSED_ASPECT=""; PARSED_PASS=""
    case "$description" in
        "Phase "*": "*) ;;
        *) return 0 ;;
    esac
    rest="${description#Phase*: }"
    case "$rest" in
        *"[pass:"*"]"*)
            PARSED_PASS="${rest##*\[pass:}"
            PARSED_PASS="${PARSED_PASS%%\]*}"
            rest="${rest%% \[pass:*}"
            ;;
    esac
    case "$rest" in
        *" — "*)
            PARSED_ASPECT="${rest#* — }"
            rest="${rest%% — *}"
            ;;
    esac
    PARSED_PHASE="${rest%% *}"
}
