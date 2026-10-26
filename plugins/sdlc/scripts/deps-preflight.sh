#!/usr/bin/env bash
# Read-only external-dependency preflight. Emits a single JSON object on stdout.
#
# Mirrors pipeline-orchestrator/references/fallback-steps.md Step 0a-2 / 0a-3 (filesystem fallback path):
# every installed plugin's runtime-dependencies.json is merged by dependency name
# (strictest policy wins: block > warn > graceful-degrade) and each declared skill is
# looked up as {plugins-root}/**/{dependency}/**/skills/{skill}/SKILL.md. Policy is NOT
# enforced here — Step 0a-4 decides what a missing dependency means for the run.
#
# Contract: never exits non-zero. A malformed declaration file is skipped with a note in
# `parse_errors`; without jq the script prints a minimal JSON object with `error` set.
#
# Usage:
#   deps-preflight.sh [--plugins-root <path>] [--dev-root <path>] [--write-cache] [--cache-dir <path>]
#
#   --plugins-root  Root searched recursively for runtime-dependencies.json and skills.
#                   Default ~/.claude/plugins/cache.
#   --dev-root      A marketplace checkout: <dev-root>/plugins/*/runtime-dependencies.json
#                   is scanned too (and <dev-root>/plugins/*/skills for skill lookup).
#   --write-cache   Also write the result to {cache-dir}/deps-preflight.json after printing it.
#   --cache-dir     Override the cache directory. Default ${CLAUDE_PLUGIN_DATA} when Claude
#                   Code provides the plugin data dir, else ~/.claude (file name becomes
#                   .sdlc-deps-preflight.json there, matching Step 0a's fallback path).
set -uo pipefail

plugins_root="${HOME}/.claude/plugins/cache"
dev_root=""
write_cache=false
cache_dir=""

while [ $# -gt 0 ]; do
    case "$1" in
        --plugins-root) plugins_root="${2:-}"; shift 2 ;;
        --dev-root)     dev_root="${2:-}"; shift 2 ;;
        --write-cache)  write_cache=true; shift ;;
        --cache-dir)    cache_dir="${2:-}"; shift 2 ;;
        *)              shift ;;
    esac
done

checked_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if ! command -v jq >/dev/null 2>&1; then
    printf '{"schema_version":1,"checked_at":"%s","error":"jq required","results":{},"all_satisfied":false,"dependencies":[],"security_guidance_available":false,"parse_errors":[]}\n' "$checked_at"
    exit 0
fi

declarations='[]'
parse_errors='[]'

add_declaration_file() {
    local file="$1" parsed
    [ -f "$file" ] || return 0
    if ! parsed=$(jq -c '.dependencies // [] | map(select(type == "object" and (.name | type) == "string"))' "$file" 2>/dev/null); then
        parse_errors=$(jq -c --arg s "$file" '. + [{source: $s, reason: "invalid JSON"}]' <<<"$parse_errors")
        return 0
    fi
    declarations=$(jq -c --argjson d "$parsed" --arg s "$file" '. + ($d | map(. + {_source: $s}))' <<<"$declarations")
}

while IFS= read -r file; do
    [ -n "$file" ] && add_declaration_file "$file"
done < <({ [ -d "$plugins_root" ] && find "$plugins_root" -name runtime-dependencies.json -type f 2>/dev/null; \
           [ -n "$dev_root" ] && [ -d "$dev_root/plugins" ] && find "$dev_root/plugins" -maxdepth 2 -name runtime-dependencies.json -type f 2>/dev/null; } | sort)

skill_available() {
    local dep="$1" skill="$2"
    if [ -d "$plugins_root" ] && [ -n "$(find "$plugins_root" -path "*/${dep}/*skills/${skill}/SKILL.md" -type f -print -quit 2>/dev/null)" ]; then
        return 0
    fi
    if [ -n "$dev_root" ] && [ -f "$dev_root/plugins/${dep}/skills/${skill}/SKILL.md" ]; then
        return 0
    fi
    return 1
}

merged=$(jq -c '
    def rank: {"block": 3, "warn": 2, "graceful-degrade": 1}[.] // 0;
    group_by(.name)
    | map(
        (map(.policy // "graceful-degrade") | max_by(rank)) as $policy
        | {
            name: .[0].name,
            version: (map(.version // empty) | first // null),
            policy: $policy,
            skills_used: (map(.skills_used // []) | add | unique),
            install_command: (map(.install_command // []) | add | unique),
            fallback_note: (map(.fallback_note // empty) | first // null),
            sources: map(._source)
          })
    | sort_by(.name)' <<<"$declarations")

dependencies='[]'
while IFS= read -r entry; do
    [ -n "$entry" ] || continue
    name=$(jq -r '.name' <<<"$entry")
    missing='[]'
    while IFS= read -r skill; do
        [ -n "$skill" ] || continue
        skill_available "$name" "$skill" || missing=$(jq -c --arg s "$skill" '. + [$s]' <<<"$missing")
    done < <(jq -r '.skills_used[]?' <<<"$entry")
    dependencies=$(jq -c --argjson e "$entry" --argjson m "$missing" \
        '. + [$e + {missing_skills: $m, status: (if ($m | length) == 0 then "available" else "missing" end)}]' <<<"$dependencies")
done < <(jq -c '.[]' <<<"$merged")

security_guidance=false
if [ -d "$plugins_root" ] && [ -n "$(find "$plugins_root" -path "*/security-guidance/*.claude-plugin/plugin.json" -type f -print -quit 2>/dev/null)" ]; then
    security_guidance=true
fi

result=$(jq -cn --arg checked_at "$checked_at" --argjson deps "$dependencies" \
    --argjson errors "$parse_errors" --argjson sg "$security_guidance" '
    {
      schema_version: 1,
      checked_at: $checked_at,
      results: ($deps | map({key: .name, value: .status}) | from_entries),
      all_satisfied: ($deps | all(.status == "available")),
      dependencies: ($deps | map({name, version, policy, status, missing_skills, install_command, fallback_note})),
      security_guidance_available: $sg,
      parse_errors: $errors
    }')

printf '%s\n' "$result"

if [ "$write_cache" = true ]; then
    if [ -n "$cache_dir" ]; then
        target="${cache_dir}/deps-preflight.json"
    elif [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
        target="${CLAUDE_PLUGIN_DATA}/deps-preflight.json"
    else
        target="${HOME}/.claude/.sdlc-deps-preflight.json"
    fi
    mkdir -p "$(dirname "$target")" 2>/dev/null && printf '%s\n' "$result" > "$target" 2>/dev/null
fi
exit 0
