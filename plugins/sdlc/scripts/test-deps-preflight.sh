#!/usr/bin/env bash
# Fixture-based test harness for deps-preflight.sh.
#
# Each case builds a throwaway plugins root (fake runtime-dependencies.json files and
# skills/ trees) under a temp dir. Nothing touches ~/.claude or the real plugin cache —
# every case passes --plugins-root and --cache-dir explicitly.
#
# Run: bash plugins/sdlc/scripts/test-deps-preflight.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREFLIGHT="${SCRIPT_DIR}/deps-preflight.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-deps-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

pass_count=0
fail_count=0

assert_field() {
    local case_name="$1" filter="$2" expected="$3" json="$4" actual
    actual=$(printf '%s' "$json" | jq -r "$filter" 2>/dev/null)
    if [ "$actual" = "$expected" ]; then
        pass_count=$((pass_count + 1)); printf 'PASS  %-64s %s = %s\n' "$case_name" "$filter" "$actual"
    else
        fail_count=$((fail_count + 1)); printf 'FAIL  %-64s %s: expected %q, got %q\n' "$case_name" "$filter" "$expected" "$actual"
    fi
}

declare_deps() {
    # $1 = plugins root, $2 = marketplace/plugin/version path, $3 = dependencies JSON array
    mkdir -p "$1/$2"
    printf '{"dependencies": %s}\n' "$3" > "$1/$2/runtime-dependencies.json"
}

echo "=== deps-preflight.sh ==="
echo

ROOT="$TMP_ROOT/cache"
declare_deps "$ROOT" "mk/sdlc/2.0.0" '[{"name":"superpowers","version":">=1.0.0","policy":"warn","skills_used":["using-superpowers","verification-before-completion"],"install_command":["/plugin install superpowers@superpowers"],"fallback_note":"degrades"}]'
declare_deps "$ROOT" "mk/vue-plugin/2.0.0" '[{"name":"superpowers","policy":"block","skills_used":["using-superpowers"]},{"name":"frontend-design","policy":"warn","skills_used":["frontend-design"]}]'
mkdir -p "$ROOT/sp-market/superpowers/1.2.0/skills/using-superpowers" "$ROOT/sp-market/superpowers/1.2.0/skills/verification-before-completion"
touch "$ROOT/sp-market/superpowers/1.2.0/skills/using-superpowers/SKILL.md" "$ROOT/sp-market/superpowers/1.2.0/skills/verification-before-completion/SKILL.md"

out=$(bash "$PREFLIGHT" --plugins-root "$ROOT")
assert_field "merged: superpowers available"         '.results.superpowers' "available" "$out"
assert_field "merged: strictest policy wins"          '.dependencies[] | select(.name == "superpowers") | .policy' "block" "$out"
assert_field "merged: skills unioned"                 '[.dependencies[] | select(.name == "superpowers") | .skills_used // empty] | length' "0" "$out"
assert_field "merged: frontend-design missing"        '.results["frontend-design"]' "missing" "$out"
assert_field "merged: missing skill listed"           '.dependencies[] | select(.name == "frontend-design") | .missing_skills | join(",")' "frontend-design" "$out"
assert_field "merged: all_satisfied false"            '.all_satisfied' "false" "$out"
assert_field "merged: install_command carried"        '.dependencies[] | select(.name == "superpowers") | .install_command[0]' "/plugin install superpowers@superpowers" "$out"
assert_field "merged: security-guidance absent"       '.security_guidance_available' "false" "$out"

mkdir -p "$ROOT/official/security-guidance/1.0.0/.claude-plugin"
printf '{"name":"security-guidance"}\n' > "$ROOT/official/security-guidance/1.0.0/.claude-plugin/plugin.json"
mkdir -p "$ROOT/official/frontend-design/1.0.0/skills/frontend-design"
touch "$ROOT/official/frontend-design/1.0.0/skills/frontend-design/SKILL.md"
out=$(bash "$PREFLIGHT" --plugins-root "$ROOT" --write-cache --cache-dir "$TMP_ROOT/cachedir")
assert_field "satisfied: all_satisfied true"          '.all_satisfied' "true" "$out"
assert_field "satisfied: security-guidance detected"  '.security_guidance_available' "true" "$out"
assert_field "satisfied: cache written"               '.all_satisfied' "true" "$(cat "$TMP_ROOT/cachedir/deps-preflight.json")"

DEV="$TMP_ROOT/dev"
mkdir -p "$DEV/plugins/sdlc" "$DEV/plugins/acme/skills/house-style"
printf '{"dependencies":[{"name":"acme","policy":"graceful-degrade","skills_used":["house-style"]}]}\n' > "$DEV/plugins/sdlc/runtime-dependencies.json"
touch "$DEV/plugins/acme/skills/house-style/SKILL.md"
out=$(bash "$PREFLIGHT" --plugins-root "$TMP_ROOT/empty" --dev-root "$DEV")
assert_field "dev-root: declaration scanned"          '.results.acme' "available" "$out"
assert_field "dev-root: policy kept"                  '.dependencies[0].policy' "graceful-degrade" "$out"

mkdir -p "$ROOT/mk/broken/1.0.0"
printf 'not json' > "$ROOT/mk/broken/1.0.0/runtime-dependencies.json"
out=$(bash "$PREFLIGHT" --plugins-root "$ROOT")
assert_field "malformed file: reported, not fatal"    '.parse_errors | length' "1" "$out"
assert_field "malformed file: others still evaluated" '.results.superpowers' "available" "$out"

out=$(bash "$PREFLIGHT" --plugins-root "$TMP_ROOT/does-not-exist")
assert_field "empty root: no dependencies"            '.dependencies | length' "0" "$out"
assert_field "empty root: all_satisfied vacuous"      '.all_satisfied' "true" "$out"

echo
printf '%d passed, %d failed\n' "$pass_count" "$fail_count"
[ "$fail_count" -eq 0 ]
