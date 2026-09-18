#!/usr/bin/env bash
# Keeps README.md's "model+effort table for all agents" in sync with the agent
# frontmatter it documents.
#
# Bidirectional: every table row must match the agent file's model/model_plan/
# effort, and every agents/*.md on disk must have a row. An em dash in a cell
# means "key absent from frontmatter".
#
# Run: bash scripts/ci/check-readme-drift.sh
set -uo pipefail

# shellcheck source=scripts/ci/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

README="$REPO_ROOT/README.md"
TABLE_HEADER='| Agent | Plugin | model | model_plan | effort | Rationale |'

WORK=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-readme-drift.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

awk -v header="$TABLE_HEADER" '
    index($0, header) == 1 { inside = 1; next }
    inside && /^\|[[:space:]]*-/ { next }
    inside && /^\|/ { print; next }
    inside { exit }
' "$README" > "$WORK/rows.txt"

if [ ! -s "$WORK/rows.txt" ]; then
    report fail "README.md: agent table not found (expected header: $TABLE_HEADER)"
    summary "check-readme-drift"
    exit $?
fi

# Reads one frontmatter scalar; prints an em dash when the key is absent.
fm_value() {
    local file="$1" key="$2" value
    value=$(frontmatter "$file" | awk -v k="^${key}:" '$0 ~ k { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }')
    value=$(printf '%s' "$value" | tr -d '"'"'"' ' | tr -d '\r')
    [ -n "$value" ] && printf '%s' "$value" || printf '—'
}

# The Plugin column holds the bare stack name; directories append -plugin,
# except for the core `sdlc` plugin and the *-foundation plugins.
plugin_dir() {
    local col="$1"
    for candidate in "$col" "$col-plugin" "$col-foundation"; do
        [ -d "$REPO_ROOT/plugins/$candidate" ] && { printf '%s' "$candidate"; return; }
    done
    printf '%s' "$col"
}

: > "$WORK/documented.txt"

while IFS='|' read -r _ agent_cell plugin_cell model_cell plan_cell effort_cell _; do
    agent=$(printf '%s' "$agent_cell" | tr -d '` ')
    plugin=$(printf '%s' "$plugin_cell" | tr -d ' ')
    [ -n "$agent" ] || continue

    dir=$(plugin_dir "$plugin")
    file="$REPO_ROOT/plugins/$dir/agents/$agent.md"
    printf '%s\n' "$agent" >> "$WORK/documented.txt"

    if [ ! -f "$file" ]; then
        report fail "README row \`$agent\` ($plugin): no such agent at plugins/$dir/agents/$agent.md"
        continue
    fi

    drift=""
    for pair in "model:$model_cell" "model_plan:$plan_cell" "effort:$effort_cell"; do
        key="${pair%%:*}"
        documented=$(printf '%s' "${pair#*:}" | tr -d '` ')
        actual=$(fm_value "$file" "$key")
        [ "$documented" = "$actual" ] || drift="$drift $key(README=$documented, frontmatter=$actual)"
    done

    if [ -n "$drift" ]; then
        report fail "README row \`$agent\` drifted from frontmatter:$drift"
    else
        report ok "\`$agent\` ($plugin): model/model_plan/effort match frontmatter"
    fi
done < "$WORK/rows.txt"

sort -u "$WORK/documented.txt" -o "$WORK/documented.txt"
find "$REPO_ROOT/plugins" -path '*/agents/*.md' -exec basename {} .md \; | sort -u > "$WORK/on-disk.txt"

undocumented=$(comm -13 "$WORK/documented.txt" "$WORK/on-disk.txt")
if [ -n "$undocumented" ]; then
    report fail "agents missing from the README table: $(printf '%s' "$undocumented" | tr '\n' ' ')"
else
    report ok "every agents/*.md on disk has a README row"
fi

summary "check-readme-drift"
