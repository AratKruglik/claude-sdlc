#!/usr/bin/env bash
# Tests for security-init.sh: fresh materialization, idempotent re-run, managed-block
# replacement that preserves user content, skip-with-warning on a file without markers,
# and --dry-run writing nothing. Uses this repository's plugins as the plugins root.
#
# Run: bash plugins/sdlc/scripts/test-security-init.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INIT="${SCRIPT_DIR}/security-init.sh"
REAL_PLUGINS_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)/plugins"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-secinit-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

pass_count=0
fail_count=0

assert_eq() {
    local case_name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        pass_count=$((pass_count + 1)); printf 'PASS  %-64s = %s\n' "$case_name" "$actual"
    else
        fail_count=$((fail_count + 1)); printf 'FAIL  %-64s expected %q, got %q\n' "$case_name" "$expected" "$actual"
    fi
}
assert_contains() {
    local case_name="$1" needle="$2" haystack="$3"
    case "$haystack" in
        *"$needle"*) pass_count=$((pass_count + 1)); printf 'PASS  %-64s contains %q\n' "$case_name" "$needle" ;;
        *) fail_count=$((fail_count + 1)); printf 'FAIL  %-64s missing %q\n' "$case_name" "$needle" ;;
    esac
}

run_init() { bash "$INIT" --repo "$1" --plugins-root "$REAL_PLUGINS_ROOT" "${@:2}"; }

YAML=".claude/security-patterns.yaml"
MD=".claude/claude-security-guidance.md"

# ── Case 1: fresh Laravel + Inertia/Vue project ──
REPO="$TMP_ROOT/fresh"; mkdir -p "$REPO"
printf '{"require":{"laravel/framework":"^11"}}\n' > "$REPO/composer.json"
printf '{"dependencies":{"@inertiajs/vue3":"^1","vue":"^3"}}\n' > "$REPO/package.json"
OUT=$(run_init "$REPO")
assert_eq "case1 exit 0" "0" "$?"
assert_contains "case1 summary header" "✅ /sdlc:security-init complete" "$OUT"
assert_contains "case1 sources merged in order" "sources: sdlc, js-foundation, vue-plugin, laravel-plugin" "$OUT"
assert_eq "case1 yaml created" "yes" "$([ -f "$REPO/$YAML" ] && echo yes || echo no)"
assert_eq "case1 md created" "yes" "$([ -f "$REPO/$MD" ] && echo yes || echo no)"
assert_contains "case1 yaml begin marker" "# >>> sdlc-marketplace managed (do not edit inside this block) >>>" "$(cat "$REPO/$YAML")"
assert_contains "case1 yaml end marker" "# <<< sdlc-marketplace managed <<<" "$(cat "$REPO/$YAML")"
assert_contains "case1 core section" "# --- sdlc (core) ---" "$(cat "$REPO/$YAML")"
assert_contains "case1 core rule carried verbatim" "rule_name: core_private_key_block" "$(cat "$REPO/$YAML")"
assert_contains "case1 laravel rule present" "# --- laravel-plugin ---" "$(cat "$REPO/$YAML")"
expected_rules=$(for p in sdlc js-foundation vue-plugin laravel-plugin; do grep -c 'rule_name:' "$REAL_PLUGINS_ROOT/$p/security-patterns.yaml"; done | awk '{s+=$1} END{print s}')
assert_eq "case1 every rule from every active source" "$expected_rules" "$(grep -c 'rule_name:' "$REPO/$YAML")"
assert_eq "case1 no duplicate rule names" "$(grep 'rule_name:' "$REPO/$YAML" | wc -l | tr -d ' ')" "$(grep 'rule_name:' "$REPO/$YAML" | sort -u | wc -l | tr -d ' ')"
assert_contains "case1 guidance heading" "## Stack-specific security guidance" "$(cat "$REPO/$MD")"
assert_contains "case1 guidance laravel section" "### Laravel" "$(cat "$REPO/$MD")"
assert_contains "case1 guidance laravel content unquoted" "**Mass assignment:**" "$(cat "$REPO/$MD")"
assert_contains "case1 guidance inertia section" "### Inertia + Vue" "$(cat "$REPO/$MD")"
assert_contains "case1 guidance plugin reminder" "security-guidance plugin not detected" "$OUT"

# ── Case 2: re-run is idempotent ──
cp "$REPO/$YAML" "$TMP_ROOT/yaml.first"; cp "$REPO/$MD" "$TMP_ROOT/md.first"
run_init "$REPO" >/dev/null
assert_eq "case2 yaml unchanged on re-run" "" "$(diff "$TMP_ROOT/yaml.first" "$REPO/$YAML")"
assert_eq "case2 md unchanged on re-run" "" "$(diff "$TMP_ROOT/md.first" "$REPO/$MD")"

# ── Case 3: user content outside the markers survives a regeneration ──
{ printf '# my custom rules\npatterns_custom:\n  - rule_name: mine\n'; cat "$REPO/$YAML"; printf '# trailing note\n'; } > "$TMP_ROOT/with-user" && mv "$TMP_ROOT/with-user" "$REPO/$YAML"
run_init "$REPO" >/dev/null
assert_eq "case3 head preserved" "# my custom rules" "$(head -1 "$REPO/$YAML")"
assert_eq "case3 tail preserved" "# trailing note" "$(tail -1 "$REPO/$YAML")"
assert_eq "case3 exactly one managed block" "1" "$(grep -c '^# >>> sdlc-marketplace managed' "$REPO/$YAML")"
assert_eq "case3 managed rules intact" "$expected_rules" "$(grep -c 'rule_name: [a-z]' "$REPO/$YAML" | awk -v u=1 '{print $1 - u}')"

# ── Case 4: existing file without markers is skipped with a warning ──
REPO="$TMP_ROOT/manual"; mkdir -p "$REPO/.claude"
printf '{"require":{"laravel/framework":"^11"}}\n' > "$REPO/composer.json"
printf 'patterns:\n  - rule_name: handwritten\n' > "$REPO/$YAML"
OUT=$(run_init "$REPO")
assert_contains "case4 warning printed" "exists without sdlc-marketplace markers" "$OUT"
assert_eq "case4 manual file untouched" "patterns:
  - rule_name: handwritten" "$(cat "$REPO/$YAML")"
assert_contains "case4 yaml marked skipped in summary" "[skipped]" "$OUT"
assert_eq "case4 md still created" "yes" "$([ -f "$REPO/$MD" ] && echo yes || echo no)"

# ── Case 5: --dry-run prints and writes nothing ──
REPO="$TMP_ROOT/dry"; mkdir -p "$REPO"
printf '{"require":{"laravel/framework":"^11"}}\n' > "$REPO/composer.json"
OUT=$(run_init "$REPO" --dry-run)
assert_contains "case5 dry-run banner" "[DRY RUN] would write" "$OUT"
assert_contains "case5 dry-run shows content" "rule_name: core_private_key_block" "$OUT"
assert_contains "case5 dry-run footer" "[DRY RUN] nothing written." "$OUT"
assert_eq "case5 no .claude dir created" "no" "$([ -d "$REPO/.claude" ] && echo yes || echo no)"

# ── Case 6: vanilla project gets core rules only, no guidance stacks ──
REPO="$TMP_ROOT/vanilla"; mkdir -p "$REPO"
OUT=$(run_init "$REPO")
assert_contains "case6 core only" "sources: sdlc)" "$OUT"
assert_eq "case6 core rule count" "$(grep -c 'rule_name:' "$REAL_PLUGINS_ROOT/sdlc/security-patterns.yaml")" "$(grep -c 'rule_name:' "$REPO/$YAML")"
assert_contains "case6 zero guidance stacks" "— 0 stacks" "$OUT"

echo
echo "=== ${pass_count} passed, ${fail_count} failed ==="
[ "$fail_count" -eq 0 ]
