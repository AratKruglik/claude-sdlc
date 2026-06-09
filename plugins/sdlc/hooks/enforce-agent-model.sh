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

# Tier → full model ID
tier_to_model() {
    case "$1" in
        opus)   echo "claude-opus-4-8" ;;
        sonnet) echo "claude-sonnet-4-6" ;;
        haiku)  echo "claude-haiku-4-5-20251001" ;;
        *)      echo "" ;;
    esac
}

allow() {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}\n'
}

allow_warn() {
    # $1 = message (must not contain double-quotes)
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"},"systemMessage":"%s"}\n' "$1"
}

payload=$(cat)

# ── detect JSON tool ────────────────────────────────────────────────────────
if command -v jq >/dev/null 2>&1; then
    tool_name=$(printf '%s' "$payload" | jq -r '.tool_name // empty')
    agent_name=$(printf '%s' "$payload" | jq -r '.tool_input.subagent_type // empty')
    requested_model=$(printf '%s' "$payload" | jq -r '.tool_input.model // empty')
elif command -v python3 >/dev/null 2>&1; then
    tool_name=$(printf '%s' "$payload"      | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_name',''))")
    agent_name=$(printf '%s' "$payload"     | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('subagent_type',''))")
    requested_model=$(printf '%s' "$payload" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('tool_input',{}).get('model',''))")
else
    allow_warn "[model-enforcement] neither jq nor python3 found — model enforcement skipped"
    exit 0
fi

# ── only intercept Agent tool ───────────────────────────────────────────────
[ "$tool_name" = "Agent" ] || { allow; exit 0; }
[ -n "$agent_name" ]       || { allow; exit 0; }

project_root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
log_path="${project_root}/docs/plans/_model-enforcement.log"

# ── find agent .md ──────────────────────────────────────────────────────────
md_path=$(find "${project_root}/plugins" -path "*/agents/${agent_name}.md" 2>/dev/null | head -1)

if [ -z "$md_path" ]; then
    allow_warn "[model-enforcement] agent '${agent_name}' .md not found — skipping model check (non-SDLC agent?)"
    exit 0
fi

# ── extract model tier from frontmatter ─────────────────────────────────────
# awk counts --- delimiters; f==1 means inside the frontmatter block
tier=$(awk '/^---$/{f++; next} f==1 && /^model:/{print $2; exit}' "$md_path")

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
printf '[%s] CORRECTED agent=%s requested=%s enforced=%s\n' \
    "$ts" "$agent_name" "${requested_model:-absent}" "$declared_model" >> "$log_path"

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
