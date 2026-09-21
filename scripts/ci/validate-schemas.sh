#!/usr/bin/env bash
# Validates every declarative artefact in the marketplace against schemas/:
#
#   plugins/*/stack.md frontmatter            → schemas/stack.schema.json
#   plugins/*/.claude-plugin/plugin.json      → schemas/plugin.schema.json
#   plugins/sdlc/workflows/*.yaml             → schemas/workflow.schema.json
#
# workflows/test-fixtures/ is excluded on purpose: cyclic.yaml is schema-valid
# and only violates the RESOLVER's acyclic rule, so validating it here would
# assert nothing.
#
# Run: bash scripts/ci/validate-schemas.sh
set -uo pipefail

# shellcheck source=scripts/ci/lib.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib.sh"

require_tool jq "Install with: brew install jq | apt-get install jq"
require_tool yq "Install the mikefarah yq v4 binary: brew install yq | https://github.com/mikefarah/yq/releases"
require_tool node "Install Node.js 20+ — ajv-cli runs on it."

if command -v ajv >/dev/null 2>&1; then
    AJV=(ajv)
else
    AJV=(npx --yes -p ajv-cli@5 -p ajv-formats@3 ajv)
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-schema-check.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

indent() { sed 's|^|      |'; }

# Validates a whole group of converted documents in a single ajv call, so that
# a per-file loop can never swallow a non-zero exit.
validate_group() {
    local label="$1" schema="$2" dir="$3" output count
    if ! compgen -G "$dir/*.json" >/dev/null; then
        report fail "$label: no documents found to validate"
        return
    fi
    count=$(find "$dir" -name '*.json' | wc -l | tr -d ' ')
    if output=$("${AJV[@]}" validate --spec=draft2020 -c ajv-formats \
        -s "$REPO_ROOT/schemas/$schema" -d "$dir/*.json" --all-errors 2>&1); then
        report ok "$label: $count document(s) valid against $schema"
    else
        report fail "$label: invalid against $schema"
        printf '%s\n' "$output" | grep -v ' valid$' | indent
    fi
}

STACK_DIR="$WORK/stack"
mkdir -p "$STACK_DIR"
for f in "$REPO_ROOT"/plugins/*/stack.md; do
    [ -e "$f" ] || continue
    plugin=$(basename "$(dirname "$f")")
    if ! frontmatter "$f" | yq -o=json '.' > "$STACK_DIR/$plugin.json" 2>"$WORK/yq.err"; then
        report fail "stack.md ($plugin): frontmatter is not parseable YAML"
        indent < "$WORK/yq.err"
        rm -f "$STACK_DIR/$plugin.json"
        continue
    fi
    if [ ! -s "$STACK_DIR/$plugin.json" ] || [ "$(jq -r 'type' "$STACK_DIR/$plugin.json")" != "object" ]; then
        report fail "stack.md ($plugin): frontmatter block missing or not a mapping"
        rm -f "$STACK_DIR/$plugin.json"
    fi
done
validate_group "stack profiles" stack.schema.json "$STACK_DIR"

PLUGIN_DIR="$WORK/plugin"
mkdir -p "$PLUGIN_DIR"
for f in "$REPO_ROOT"/plugins/*/.claude-plugin/plugin.json; do
    [ -e "$f" ] || continue
    plugin=$(basename "$(dirname "$(dirname "$f")")")
    if jq -e . "$f" >/dev/null 2>&1; then
        cp "$f" "$PLUGIN_DIR/$plugin.json"
    else
        report fail "plugin.json ($plugin): not valid JSON"
    fi
done
validate_group "plugin manifests" plugin.schema.json "$PLUGIN_DIR"

WORKFLOW_DIR="$WORK/workflow"
mkdir -p "$WORKFLOW_DIR"
for f in "$REPO_ROOT"/plugins/sdlc/workflows/*.yaml; do
    [ -e "$f" ] || continue
    recipe=$(basename "$f" .yaml)
    if ! yq -o=json '.' "$f" > "$WORKFLOW_DIR/$recipe.json" 2>"$WORK/yq.err"; then
        report fail "workflow ($recipe): not parseable YAML"
        indent < "$WORK/yq.err"
        rm -f "$WORKFLOW_DIR/$recipe.json"
    fi
done
validate_group "workflow recipes" workflow.schema.json "$WORKFLOW_DIR"

MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
if jq -e '.name and .version and (.plugins | type == "array")' "$MARKETPLACE" >/dev/null 2>&1; then
    report ok "marketplace.json: name, version and plugins[] present"
else
    report fail "marketplace.json: missing name, version or plugins[]"
fi

summary "validate-schemas"
