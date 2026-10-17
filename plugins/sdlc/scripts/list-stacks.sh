#!/usr/bin/env bash
# Renders /sdlc:list-stacks from detect-stack.sh output. Read-only.
#
# The command used to Glob and Read every installed stack.md through the model; this script
# is the same scan, printed in the exact plain-text format commands/list-stacks.md specifies,
# so the model only relays it. --json passes the detector's object through unchanged.
#
# Usage: list-stacks.sh [--repo DIR] [--plugins-root DIR] [--dev-root DIR] [--json]
#
#   --plugins-root  Where installed plugins live. Default ~/.claude/plugins/cache.
#   --dev-root      A development checkout of the marketplace, searched when the plugins root
#                   holds no stack.md at all (so the command works from this repo itself).
#
# Exit codes: 0 always for a renderable result; 2 usage error; 3 jq missing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

repo="."
plugins_root="${HOME}/.claude/plugins/cache"
dev_root=""
json_out=false

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)         repo="${2:-.}"; shift 2 ;;
        --plugins-root) plugins_root="${2:-}"; shift 2 ;;
        --dev-root)     dev_root="${2:-}"; shift 2 ;;
        --json)         json_out=true; shift ;;
        -h|--help)      sed -n '2,15p' "$0"; exit 0 ;;
        *)              echo "usage: list-stacks.sh [--repo DIR] [--plugins-root DIR] [--dev-root DIR] [--json]" >&2; exit 2 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo '{"error":"jq is required"}'; exit 3; }

if [ -z "$(find "$plugins_root" -name stack.md -type f 2>/dev/null | head -1)" ] && [ -n "$dev_root" ]; then
    plugins_root="$dev_root"
fi

result=$(bash "${SCRIPT_DIR}/detect-stack.sh" --repo "$repo" --plugins-root "$plugins_root")

if [ "$json_out" = true ]; then
    printf '%s\n' "$result"
    exit 0
fi

count=$(jq -r '.all_profiles | length' <<<"$result")
if [ "$count" = "0" ]; then
    echo "No stack profiles found under ${plugins_root}."
    echo "Install a framework plugin (e.g. /plugin install laravel-plugin@sdlc-marketplace) to add stack-specific agents."
    exit 0
fi

echo "Stack profiles found:"
echo
jq -r '
    (.primary_profile.stack // "") as $primary
    | (.matched_profiles | map(.priority) | max // 0) as $top
    | .all_profiles
    | sort_by(-.priority, .stack)[]
    | (if .matched then
         (if .detect_summary == "always matches" then "(always matches)" else "matches: " + .detect_summary end)
       else "no match: " + (.unmatched_reason // "detect rules not satisfied") end) as $detail
    | (if .stack == $primary then "  ← active" + (if .priority == 0 then " fallback" else "" end)
       elif .matched and .priority == $top then "  ← active (tie)"
       else "" end) as $mark
    | "  🎯 " + (.stack | . + (" " * (14 - length | if . < 1 then 1 else . end))) + "priority=" + (.priority | tostring | . + (" " * (6 - length | if . < 1 then 1 else . end))) + $detail + $mark
' <<<"$result"
echo

primary=$(jq -r '.primary_profile.stack // empty' <<<"$result")
source=$(jq -r '.primary_profile.source // empty' <<<"$result")
if [ -n "$primary" ]; then
    echo "Active profile for this project: ${primary} (from ${source})"
else
    echo "Active profile for this project: none matched"
fi
echo 'Override with: /sdlc:start --stack=NAME "<feature>"'

ties=$(jq -r '.aspect_ties | to_entries[] | "  ⚠️  aspect \(.key): tie between \(.value | join(", ")) — use --stack=NAME to disambiguate"' <<<"$result")
[ -n "$ties" ] && { echo; printf '%s\n' "$ties"; }

shared_top=$(jq -r '
    (.matched_profiles | map(.priority) | max // 0) as $top
    | [.matched_profiles[] | select(.priority == $top) | .stack] | if length > 1 then join(", ") else empty end' <<<"$result")
[ -n "$shared_top" ] && echo "  ⚠️  ambiguous: ${shared_top} all match at the same priority — pass --stack=NAME to choose"

non_vanilla=$(jq -r '[.all_profiles[] | select(.stack != "vanilla")] | length' <<<"$result")
if [ "$non_vanilla" = "0" ]; then
    echo
    echo "Only the vanilla profile is registered. Install a framework plugin"
    echo "(e.g. /plugin install laravel-plugin@sdlc-marketplace) to add stack-specific agents."
fi

errors=$(jq -r '.parse_errors[] | "  ⚠️  \(.source): \(.reason)"' <<<"$result")
[ -n "$errors" ] && { echo; echo "Skipped (parse errors):"; printf '%s\n' "$errors"; }

exit 0
