#!/usr/bin/env bash
# Every `plugin:skill` a stack.md lists under "## Convention skills to apply" must resolve:
#
#   - plugin is in this marketplace → plugins/<dir>/skills/<skill>/SKILL.md exists, where <dir>
#     is the plugin whose manifest `name` is <plugin> (the namespace Claude Code qualifies with)
#   - plugin is external → some runtime-dependencies.json declares it with <skill> in skills_used
#
# A reference that resolves to neither makes the architect's Skill call fail at run time.
#
# Run: bash scripts/ci/check-skill-refs.sh
set -uo pipefail

# shellcheck source=scripts/ci/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_tool jq "Install with: brew install jq | apt-get install jq"

declare -A plugin_dir
for manifest in "$REPO_ROOT"/plugins/*/.claude-plugin/plugin.json; do
    plugin_dir[$(jq -r '.name' "$manifest")]=$(dirname "$(dirname "$manifest")")
done

external=$(jq -r '.dependencies[]? | .name as $p | .skills_used[]? | "\($p):\(.)"' \
    "$REPO_ROOT"/plugins/*/runtime-dependencies.json 2>/dev/null | sort -u)

refs=0
broken=0
for stack in "$REPO_ROOT"/plugins/*/stack.md; do
    rel=${stack#"$REPO_ROOT"/}
    while IFS= read -r ref; do
        [ -n "$ref" ] || continue
        refs=$((refs + 1))
        plugin=${ref%%:*}
        skill=${ref#*:}
        if [ -n "${plugin_dir[$plugin]:-}" ]; then
            [ -f "${plugin_dir[$plugin]}/skills/$skill/SKILL.md" ] && continue
            report fail "$rel → $ref (plugin '$plugin' has no skill '$skill')"
        elif grep -qxF "$ref" <<<"$external"; then
            continue
        else
            report fail "$rel → $ref (no plugin named '$plugin' here, and no runtime-dependencies.json declares it)"
        fi
        broken=$((broken + 1))
    done < <(awk '/^## Convention skills to apply/ { f = 1; next } /^## / { f = 0 } f' "$stack" \
        | sed -nE 's/^- ([A-Za-z0-9_-]+:[A-Za-z0-9_-]+).*/\1/p')
done

if [ "$broken" -eq 0 ]; then
    report ok "all $refs convention skill reference(s) resolve"
fi

summary "check-skill-refs"
