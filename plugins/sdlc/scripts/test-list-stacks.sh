#!/usr/bin/env bash
# Tests for list-stacks.sh: the rendered table, the active marker, the tie warning, the
# vanilla-only message and --json pass-through. Uses this repository's plugins as the
# plugins root plus fabricated roots for the edge cases.
#
# Run: bash plugins/sdlc/scripts/test-list-stacks.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="${SCRIPT_DIR}/list-stacks.sh"
REAL_PLUGINS_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-list-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

pass_count=0
fail_count=0

assert_contains() {
    local case_name="$1" needle="$2" haystack="$3"
    case "$haystack" in
        *"$needle"*) pass_count=$((pass_count + 1)); printf 'PASS  %-64s contains %q\n' "$case_name" "$needle" ;;
        *) fail_count=$((fail_count + 1)); printf 'FAIL  %-64s missing %q\n' "$case_name" "$needle" ;;
    esac
}
assert_not_contains() {
    local case_name="$1" needle="$2" haystack="$3"
    case "$haystack" in
        *"$needle"*) fail_count=$((fail_count + 1)); printf 'FAIL  %-64s unexpectedly contains %q\n' "$case_name" "$needle" ;;
        *) pass_count=$((pass_count + 1)); printf 'PASS  %-64s free of %q\n' "$case_name" "$needle" ;;
    esac
}
assert_eq() {
    local case_name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        pass_count=$((pass_count + 1)); printf 'PASS  %-64s = %s\n' "$case_name" "$actual"
    else
        fail_count=$((fail_count + 1)); printf 'FAIL  %-64s expected %q, got %q\n' "$case_name" "$expected" "$actual"
    fi
}

# ── Case 1: Laravel project against the real plugin set ──
REPO="$TMP_ROOT/laravel"; mkdir -p "$REPO"
printf '{"require":{"laravel/framework":"^11"}}\n' > "$REPO/composer.json"
OUT=$(bash "$LIST" --repo "$REPO" --plugins-root "$REAL_PLUGINS_ROOT")
assert_contains "case1 header" "Stack profiles found:" "$OUT"
assert_contains "case1 laravel row matches" "matches: composer.json + laravel/framework" "$OUT"
assert_contains "case1 laravel is active" "← active" "$OUT"
assert_contains "case1 active line names source" "Active profile for this project: laravel (from laravel-plugin/stack.md)" "$OUT"
assert_contains "case1 override hint" 'Override with: /sdlc:start --stack=NAME "<feature>"' "$OUT"
assert_contains "case1 unmatched row explains why" "no match: composer.json lacks symfony/framework-bundle" "$OUT"
assert_contains "case1 vanilla row" "(always matches)" "$OUT"
assert_not_contains "case1 no vanilla-only message" "Only the vanilla profile is registered" "$OUT"

# ── Case 2: empty project → vanilla fallback marked ──
REPO="$TMP_ROOT/empty"; mkdir -p "$REPO"
OUT=$(bash "$LIST" --repo "$REPO" --plugins-root "$REAL_PLUGINS_ROOT")
assert_contains "case2 vanilla active fallback" "← active fallback" "$OUT"
assert_contains "case2 nextjs unmatched" "no match: package.json not present" "$OUT"

# ── Case 3: only vanilla installed → install hint ──
ONLY_ROOT="$TMP_ROOT/only-vanilla"; mkdir -p "$ONLY_ROOT/sdlc"
cp "${SCRIPT_DIR}/../stack.md" "$ONLY_ROOT/sdlc/stack.md"
OUT=$(bash "$LIST" --repo "$REPO" --plugins-root "$ONLY_ROOT")
assert_contains "case3 vanilla-only message" "Only the vanilla profile is registered" "$OUT"

# ── Case 4: tie → ambiguity warning ──
TIE_ROOT="$TMP_ROOT/tie"; mkdir -p "$TIE_ROOT/a" "$TIE_ROOT/b"
for n in a b; do
    printf -- '---\nstack: fake%s\naspects: [backend]\npriority: 100\ndetect:\n  any: ["*"]\n---\nFake\n' "$n" > "$TIE_ROOT/$n/stack.md"
done
OUT=$(bash "$LIST" --repo "$REPO" --plugins-root "$TIE_ROOT")
assert_contains "case4 aspect tie warning" "aspect backend: tie between fakea, fakeb" "$OUT"
assert_contains "case4 ambiguity warning" "ambiguous: fakea, fakeb all match at the same priority" "$OUT"

# ── Case 5: --json passes the detector output through ──
OUT=$(bash "$LIST" --repo "$TMP_ROOT/laravel" --plugins-root "$REAL_PLUGINS_ROOT" --json)
assert_eq "case5 json primary" "laravel" "$(jq -r '.primary_profile.stack' <<<"$OUT")"
assert_eq "case5 json has all_profiles" "true" "$(jq -r '.all_profiles | length > 5' <<<"$OUT")"

# ── Case 6: --dev-root used when the plugins root is empty ──
EMPTY_ROOT="$TMP_ROOT/no-plugins"; mkdir -p "$EMPTY_ROOT"
OUT=$(bash "$LIST" --repo "$TMP_ROOT/laravel" --plugins-root "$EMPTY_ROOT" --dev-root "$REAL_PLUGINS_ROOT")
assert_contains "case6 dev-root fallback finds laravel" "Active profile for this project: laravel" "$OUT"
OUT=$(bash "$LIST" --repo "$TMP_ROOT/laravel" --plugins-root "$EMPTY_ROOT")
assert_contains "case6 no plugins anywhere" "No stack profiles found" "$OUT"

# ── Case 7: usage error exits 2 ──
bash "$LIST" --bogus >/dev/null 2>&1; assert_eq "case7 usage error exit code" "2" "$?"

echo
echo "=== ${pass_count} passed, ${fail_count} failed ==="
[ "$fail_count" -eq 0 ]
