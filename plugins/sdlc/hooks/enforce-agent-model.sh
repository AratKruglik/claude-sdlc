#!/usr/bin/env bash
# PreToolUse hook: enforce declared model on every Agent() dispatch.
#
# Claude Code sends a JSON payload on stdin:
#   { "tool_name": "Agent",
#     "tool_input": { "subagent_type": "...", "model": "...", ... } }
#
# Requires jq (preferred) or python3 for JSON parsing.
# Fails open (allow) if neither is available.
set -uo pipefail

# Tier → Agent tool model alias.
# The Agent tool's `model` parameter accepts ONLY short aliases, never full model IDs —
# a full ID fails schema validation and the dispatch retries without any model override,
# silently inheriting the (expensive) session model. Agent *frontmatter* is more permissive
# (full IDs and `inherit` are legal there); this allowlist deliberately is not.
#
# NOTE: this hook cannot make enforcement absolute. Claude Code resolves a subagent's model
# in the order per-invocation parameter -> frontmatter -> CLAUDE_CODE_SUBAGENT_MODEL ->
# session model. This hook writes the parameter, so that variable alone never overrides it.
# CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 (Claude Code v2.1.257+) does: it makes Claude Code
# ignore the parameter and the frontmatter alike. `/sdlc:doctor` reports when it is set.
tier_to_model() {
    case "$1" in
        opus|sonnet|haiku|fable) echo "$1" ;;
        *)                       echo "" ;;
    esac
}

allow() {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}\n'
}

# $1 = message. agent_name is caller-supplied (subagent_type), so it may legally
# contain characters that break naive JSON string interpolation — build the JSON
# with jq when available, and quote-escape by hand only in the no-jq fallback.
allow_warn() {
    local msg="$1"
    if command -v jq >/dev/null 2>&1; then
        jq -n --arg msg "$msg" \
            '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"},"systemMessage":$msg}'
    else
        local escaped
        escaped=$(printf '%s' "$msg" | sed 's/\\/\\\\/g; s/"/\\"/g')
        printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"},"systemMessage":"%s"}\n' "$escaped"
    fi
}

# $1 = permissionDecisionReason (shown to Claude only), $2 = systemMessage (shown to the user).
# A deny with only the reason is invisible to the operator — the orchestrator would
# silently re-dispatch and nobody would learn the local roster is shadowing.
deny_with_notice() {
    local reason="$1"
    local msg="$2"
    if command -v jq >/dev/null 2>&1; then
        jq -n --arg reason "$reason" --arg msg "$msg" \
            '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":$reason},"systemMessage":$msg}'
    elif command -v python3 >/dev/null 2>&1; then
        python3 -c "
import json, sys
reason, msg = sys.argv[1], sys.argv[2]
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PreToolUse',
        'permissionDecision': 'deny',
        'permissionDecisionReason': reason,
    },
    'systemMessage': msg,
}))
" "$reason" "$msg"
    else
        # Neither jq nor python3 — fail open rather than emit malformed JSON.
        allow
    fi
}

payload=$(cat)

# ── detect JSON tool ────────────────────────────────────────────────────────
if command -v jq >/dev/null 2>&1; then
    tool_name=$(printf '%s' "$payload" | jq -r '.tool_name // empty')
    agent_name=$(printf '%s' "$payload" | jq -r '.tool_input.subagent_type // empty')
    requested_model=$(printf '%s' "$payload" | jq -r '.tool_input.model // empty')
    description=$(printf '%s' "$payload" | jq -r '.tool_input.description // empty')
elif command -v python3 >/dev/null 2>&1; then
    tool_name=$(printf '%s' "$payload"      | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_name',''))")
    agent_name=$(printf '%s' "$payload"     | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('subagent_type',''))")
    requested_model=$(printf '%s' "$payload" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('model',''))")
    description=$(printf '%s' "$payload"    | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('description',''))")
else
    allow_warn "[model-enforcement] neither jq nor python3 found — model enforcement skipped"
    exit 0
fi

# ── only intercept Agent tool ───────────────────────────────────────────────
[ "$tool_name" = "Agent" ] || { allow; exit 0; }
[ -n "$agent_name" ]       || { allow; exit 0; }

# subagent_type may carry a plugin prefix ("sdlc:document-writer") — strip it,
# agent .md files are named without it. Keep the qualified form too — the roster
# comparison below needs to recognize both "sdlc:qa-engineer" and "qa-engineer".
agent_name_qualified="$agent_name"
agent_name="${agent_name##*:}"

project_root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
log_path="${project_root}/docs/plans/_model-enforcement.log"
marker_path="${project_root}/.claude/.sdlc-run-active.json"

# ── run-marker: block off-roster PROJECT-LOCAL agents during a pipeline run ─
#
# The orchestrator writes $marker_path at Step 2 (pipeline-orchestrator/SKILL.md)
# and removes it at Step 5 / on abort. It contains the resolved agent roster for
# this run, so a project that ships its own .claude/agents/{tester,reviewer,...}.md
# can no longer silently shadow the pipeline's qa-engineer/security-analyst/etc.
#
# Deliberately narrow: this only denies PROJECT- or USER-LOCAL agents (files under
# .claude/agents/), never plugin agents or built-ins (general-purpose, Explore, ...)
# — architects legitimately spawn those via superpowers:requesting-code-review and
# superpowers:subagent-driven-development, and denying them would break the
# development phase. An off-roster PLUGIN agent stays governed by prompt text only.
MARKER_MAX_AGE_SECONDS=21600  # 6h — a crashed run must not wedge every later dispatch

# Freshness keys on `updated_at` — refreshed by the orchestrator at every phase boundary
# (state file v2) so a resumed or long run stays enforced — and falls back to `started_at`
# for v1 markers. The variable keeps its historical name; it is "the timestamp the marker
# is judged by", whichever field supplied it.
marker_active=false
roster_json="[]"
phase_agents_json="{}"

if [ -f "$marker_path" ]; then
    if command -v jq >/dev/null 2>&1; then
        started_at=$(jq -r '.updated_at // .started_at // empty' "$marker_path" 2>/dev/null)
        roster_json=$(jq -c '.roster // []' "$marker_path" 2>/dev/null || echo '[]')
        phase_agents_json=$(jq -c '.phase_agents // {}' "$marker_path" 2>/dev/null || echo '{}')
    elif command -v python3 >/dev/null 2>&1; then
        started_at=$(python3 -c "
import json
try:
    d = json.load(open('${marker_path}'))
    print(d.get('updated_at') or d.get('started_at',''))
except Exception:
    print('')
" 2>/dev/null)
        roster_json=$(python3 -c "
import json
try:
    d = json.load(open('${marker_path}'))
    print(json.dumps(d.get('roster', [])))
except Exception:
    print('[]')
" 2>/dev/null)
        phase_agents_json=$(python3 -c "
import json
try:
    d = json.load(open('${marker_path}'))
    print(json.dumps(d.get('phase_agents', {})))
except Exception:
    print('{}')
" 2>/dev/null)
    fi

    if [ -n "${started_at:-}" ]; then
        now_epoch=$(date -u +%s)
        # ISO 8601 with a colon in the tz offset ("+00:00") trips BSD date's %z —
        # normalize to "+0000" before the BSD fallback. Best-effort: an unparsable
        # timestamp fails open (marker treated as absent), consistent with the
        # rest of this hook's fail-open philosophy.
        started_at_bsd=$(printf '%s' "$started_at" | sed -E 's/([+-][0-9]{2}):([0-9]{2})$/\1\2/')
        started_epoch=$(date -u -d "$started_at" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%S%z" "$started_at_bsd" +%s 2>/dev/null || echo "")
        if [ -n "$started_epoch" ]; then
            age=$(( now_epoch - started_epoch ))
            [ "$age" -ge 0 ] && [ "$age" -lt "$MARKER_MAX_AGE_SECONDS" ] && marker_active=true
        fi
    fi
fi

# $1 = bare agent name, $2 = roster JSON array (compact) → 0 if the bare name is
# explicitly present (an agent_overrides entry).
#
# Exact match only — this is invoked ONLY for UNQUALIFIED dispatches (the caller
# skips it entirely for a "plugin:agent" subagent_type, see below), so there is no
# "plugin:agent" form of the SAME dispatch to also accept. Do not add an
# endswith(":"+bare) fallback here: a roster containing "sdlc:developer" describes
# the qualified PLUGIN agent being on the roster, not a sanctioned bare-name local
# override — matching on it would let a bare "developer" dispatch (e.g. a retry
# after a qualified-dispatch error) slide through as if it were legitimate, when it
# actually resolves to whatever project-local developer.md happens to exist.
bare_agent_overridden() {
    local bare="$1" roster="$2"
    [ -z "$roster" ] && return 1
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$roster" | jq -e --arg b "$bare" 'any(.[]; . == $b)' >/dev/null 2>&1
        return $?
    elif command -v python3 >/dev/null 2>&1; then
        printf '%s' "$roster" | python3 -c "
import json, sys
roster = json.load(sys.stdin)
b = sys.argv[1]
sys.exit(0 if any(r == b for r in roster) else 1)
" "$bare"
        return $?
    fi
    return 1
}

# $1 = bare agent name → prints the matching path and returns 0, or returns 1
find_local_agent() {
    local hit
    for d in "${project_root}/.claude/agents" "${HOME}/.claude/agents"; do
        [ -d "$d" ] || continue
        hit=$(find "$d" -name "${1}.md" 2>/dev/null | head -1)
        if [ -n "$hit" ]; then
            printf '%s' "$hit"
            return 0
        fi
    done
    return 1
}

if [ "$marker_active" = true ]; then
    case "$agent_name_qualified" in
        *:*)
            # Qualified dispatch ("plugin:agent") cannot resolve to a project- or
            # user-local agent — those files are never plugin-prefixed, so there is
            # nothing to police here. This matters: without this guard, a plugin
            # agent whose BARE name happens to collide with a local file (e.g. a
            # project ships .claude/agents/developer.md) would be probed against
            # that local file and denied even though the dispatch is legitimately
            # qualified as "sdlc:developer". Only unqualified dispatches are checked.
            ;;
        *)
            if local_agent_path=$(find_local_agent "$agent_name"); then
                if ! bare_agent_overridden "$agent_name" "$roster_json"; then
                    # Best-effort: name the specific roster agent for this phase if the
                    # description follows the "Phase N/M: {phase_name}..." contract;
                    # otherwise fall back to listing the whole roster.
                    phase_name=""
                    case "$description" in
                        "Phase "*": "*)
                            rest="${description#Phase*: }"
                            phase_name="${rest%% *}"
                            phase_name="${phase_name%%[—\[]*}"
                            ;;
                    esac

                    expected_agent=""
                    if [ -n "$phase_name" ]; then
                        if command -v jq >/dev/null 2>&1; then
                            expected_agent=$(printf '%s' "$phase_agents_json" | jq -r --arg p "$phase_name" '.[$p] // empty')
                        elif command -v python3 >/dev/null 2>&1; then
                            expected_agent=$(printf '%s' "$phase_agents_json" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(d.get(sys.argv[1], ''))
" "$phase_name")
                        fi
                    fi

                    if [ -n "$expected_agent" ]; then
                        suggestion="Re-dispatch this phase using '${expected_agent}' instead."
                    else
                        roster_csv=""
                        if command -v jq >/dev/null 2>&1; then
                            roster_csv=$(printf '%s' "$roster_json" | jq -r 'join(", ")')
                        elif command -v python3 >/dev/null 2>&1; then
                            roster_csv=$(printf '%s' "$roster_json" | python3 -c "import json,sys; print(', '.join(json.load(sys.stdin)))")
                        fi
                        suggestion="Re-dispatch this phase using one of the run's roster agents: ${roster_csv}."
                    fi

                    mkdir -p "$(dirname "$log_path")"
                    ts=$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")
                    printf '[%s] DENIED local agent=%s (qualified=%s) path=%s\n' \
                        "$ts" "$agent_name" "$agent_name_qualified" "$local_agent_path" >> "$log_path"

                    reason="[model-enforcement] '${agent_name}' (${local_agent_path}) is not part of this SDLC pipeline run's roster. ${suggestion} If it should be, add it under agent_overrides in .claude/sdlc.local.yaml. If no pipeline is actually running, remove the stale marker: rm ${marker_path}"
                    msg="[model-enforcement] BLOCKED project-local agent '${agent_name}' — not in the active SDLC pipeline roster. See ${log_path}."

                    deny_with_notice "$reason" "$msg"
                    exit 0
                fi
            fi
            ;;
    esac
fi

# ── find agent .md ──────────────────────────────────────────────────────────
# Search order: installed plugin root → sibling plugins (marketplace layout) → dev checkout fallback
search_roots=()
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
    search_roots+=(
        "${CLAUDE_PLUGIN_ROOT}"
        "$(dirname "${CLAUDE_PLUGIN_ROOT}")"
        "$(dirname "$(dirname "${CLAUDE_PLUGIN_ROOT}")")"
    )
fi
search_roots+=( "${project_root}/plugins" )

md_path=""
for root in "${search_roots[@]}"; do
    [ -d "$root" ] || continue
    candidates=$(find "$root" -path "*/agents/${agent_name}.md" 2>/dev/null)
    [ -z "$candidates" ] && continue
    # A root can hold multiple installed versions of the same plugin side by side
    # (e.g. .../sdlc-marketplace/sdlc/1.2.1/agents/ and .../1.3.0/agents/) — plain
    # `head -1` on an unordered `find` picks whichever the filesystem returns first,
    # which can enforce a stale tier nondeterministically. Version-sort descending
    # (the differing version segment is the only part that varies across candidates
    # for the same plugin) and take the newest.
    if printf '%s\n' "$candidates" | sort -Vr >/dev/null 2>&1; then
        md_path=$(printf '%s\n' "$candidates" | sort -Vr | head -1)
    else
        md_path=$(printf '%s\n' "$candidates" | sort -r | head -1)
    fi
    [ -n "$md_path" ] && break
done

if [ -z "$md_path" ]; then
    allow_warn "[model-enforcement] agent '${agent_name}' .md not found — skipping model check (non-SDLC agent?)"
    exit 0
fi

# ── extract model tier from frontmatter ─────────────────────────────────────
# The development phase runs two passes on different tiers: the planning pass resolves
# `model_plan:` and the implementation pass resolves `model:`. The hook only sees
# tool_input, so the orchestrator marks the pass in `description` (see SKILL.md step 3c).
# Without this branch the hook would rewrite a planning-pass dispatch back down to
# `model:` and silently undo the tier split.
field="model"
case "$description" in
    *"[pass:plan]"*) field="model_plan" ;;
esac

# awk counts --- delimiters; f==1 means inside the frontmatter block
extract_tier() {
    awk -v key="^$1:" '/^---$/{f++; next} f==1 && $0 ~ key {print $2; exit}' "$md_path"
}

tier=$(extract_tier "$field")

# model_plan is optional — fall back to model when the agent does not declare one
if [ -z "$tier" ] && [ "$field" = "model_plan" ]; then
    tier=$(extract_tier "model")
fi

if [ -z "$tier" ]; then
    allow_warn "[model-enforcement] agent '${agent_name}' has no model: in frontmatter — skipping"
    exit 0
fi

declared_model=$(tier_to_model "$tier")

if [ -z "$declared_model" ]; then
    allow_warn "[model-enforcement] unknown tier '${tier}' for agent '${agent_name}' — skipping"
    exit 0
fi

# ── already correct → passthrough ──────────────────────────────────────────
[ "$requested_model" = "$declared_model" ] && { allow; exit 0; }

# ── correction needed ───────────────────────────────────────────────────────
mkdir -p "$(dirname "$log_path")"
ts=$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")
printf '[%s] CORRECTED agent=%s field=%s requested=%s enforced=%s\n' \
    "$ts" "$agent_name" "$field" "${requested_model:-absent}" "$declared_model" >> "$log_path"

# Build corrected output — jq path preferred, python3 fallback
if command -v jq >/dev/null 2>&1; then
    updated_input=$(printf '%s' "$payload" | jq --arg m "$declared_model" '.tool_input | .model = $m')
    jq -n \
        --argjson ui "$updated_input" \
        --arg msg "[model-enforcement] CORRECTED ${agent_name}: ${requested_model:-absent} → ${declared_model}" \
        '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":$ui},"systemMessage":$msg}'
else
    updated_input=$(printf '%s' "$payload" \
        | python3 -c "
import json, sys
d = json.load(sys.stdin)
ti = d.get('tool_input', {})
ti['model'] = '${declared_model}'
print(json.dumps(ti))
")
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","updatedInput":%s},"systemMessage":"[model-enforcement] CORRECTED %s: %s → %s"}\n' \
        "$updated_input" "$agent_name" "${requested_model:-absent}" "$declared_model"
fi
