#!/usr/bin/env bash
# Fixture-based test harness for detect-stack.py.
#
# Each case builds a throwaway "plugins root" (a directory of fake stack.md
# files) and/or a throwaway project directory, then asserts on the
# detector's JSON output. Nothing touches the real ~/.claude/plugins/cache
# or ~/.claude/.sdlc-stack-cache — every case passes --plugins-root and, for
# cache-writing cases, --cache-dir explicitly.
#
# Run: bash plugins/sdlc/scripts/test-detect-stack.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="${SCRIPT_DIR}/detect-stack.py"
REAL_PLUGINS_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

command -v python3 >/dev/null 2>&1 || { echo "SKIP: python3 not available"; exit 0; }
command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-stack-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

pass_count=0
fail_count=0

assert_field() {
    local case_name="$1" filter="$2" expected="$3" json="$4"
    local actual
    actual=$(printf '%s' "$json" | jq -r "$filter" 2>/dev/null)
    if [ "$actual" = "$expected" ]; then
        pass_count=$((pass_count + 1))
        printf 'PASS  %-64s %s = %s\n' "$case_name" "$filter" "$actual"
    else
        fail_count=$((fail_count + 1))
        printf 'FAIL  %-64s %s: expected %q, got %q\n' "$case_name" "$filter" "$expected" "$actual"
    fi
}

assert_valid_json() {
    local case_name="$1" json="$2"
    if printf '%s' "$json" | jq . >/dev/null 2>&1; then
        pass_count=$((pass_count + 1))
        printf 'PASS  %-64s valid JSON\n' "$case_name"
    else
        fail_count=$((fail_count + 1))
        printf 'FAIL  %-64s invalid JSON: %s\n' "$case_name" "$json"
    fi
}

run_detect() {
    python3 "$DETECT" --repo "$1" --plugins-root "${2:-$REAL_PLUGINS_ROOT}"
}

# ── Case 1: real plugin set, vanilla project (this repo itself) ──
OUT=$(run_detect "$REAL_PLUGINS_ROOT")
assert_valid_json "case1 vanilla project" "$OUT"
assert_field "case1 primary is vanilla" '.primary_profile.stack' "vanilla" "$OUT"
assert_field "case1 no parse errors against real stack.md files" '.parse_errors | length' "0" "$OUT"
assert_field "case1 no aspect ties" '.aspect_ties | length' "0" "$OUT"

# ── Case 2: real plugin set, fake Laravel project → backend+database win ──
REPO="$TMP_ROOT/laravel-repo"
mkdir -p "$REPO"
printf '{"require": {"laravel/framework": "^10.0"}}\n' > "$REPO/composer.json"
OUT=$(run_detect "$REPO")
assert_field "case2 primary is laravel" '.primary_profile.stack' "laravel" "$OUT"
assert_field "case2 backend aspect is laravel" '.active_profiles.backend.stack' "laravel" "$OUT"
assert_field "case2 database aspect is laravel" '.active_profiles.database.stack' "laravel" "$OUT"
assert_field "case2 frontend aspect is empty" '.active_profiles.frontend' "null" "$OUT"

# ── Case 3: Laravel + Inertia/Vue → full-stack fan-out ──
REPO="$TMP_ROOT/laravel-inertia-vue-repo"
mkdir -p "$REPO"
printf '{"require": {"laravel/framework": "^10.0"}}\n' > "$REPO/composer.json"
printf '{"dependencies": {"@inertiajs/vue3": "^1.0.0"}}\n' > "$REPO/package.json"
OUT=$(run_detect "$REPO")
assert_field "case3 backend is laravel" '.active_profiles.backend.stack' "laravel" "$OUT"
assert_field "case3 frontend is inertia-vue" '.active_profiles.frontend.stack' "inertia-vue" "$OUT"

# ── Case 4: fabricated aspect tie → must be recorded, not silently resolved ──
FAKE_ROOT="$TMP_ROOT/fake-plugins"
mkdir -p "$FAKE_ROOT/fakea" "$FAKE_ROOT/fakeb"
cat > "$FAKE_ROOT/fakea/stack.md" <<'EOF'
---
stack: fakea
aspects: [backend]
priority: 100
detect:
  any: ["*"]
---
Fake A
EOF
cat > "$FAKE_ROOT/fakeb/stack.md" <<'EOF'
---
stack: fakeb
aspects: [backend]
priority: 100
detect:
  any: ["*"]
---
Fake B
EOF
REPO="$TMP_ROOT/tie-repo"
mkdir -p "$REPO"
OUT=$(run_detect "$REPO" "$FAKE_ROOT")
assert_field "case4 backend aspect left unresolved" '.active_profiles.backend' "null" "$OUT"
assert_field "case4 tie recorded (2 names)" '.aspect_ties.backend | length' "2" "$OUT"
assert_field "case4 tie contains fakea" '.aspect_ties.backend | index("fakea") != null' "true" "$OUT"
assert_field "case4 tie contains fakeb" '.aspect_ties.backend | index("fakeb") != null' "true" "$OUT"
assert_field "case4 primary still resolvable (alphabetical tiebreak)" '.primary_profile.stack' "fakea" "$OUT"

# ── Case 5: malformed stack.md → skipped with a parse_errors entry, not a crash ──
BAD_ROOT="$TMP_ROOT/bad-plugins"
mkdir -p "$BAD_ROOT/broken"
cat > "$BAD_ROOT/broken/stack.md" <<'EOF'
---
stack: broken
priority: not-a-number
detect:
  nonsense
---
Broken profile with no usable detect block.
EOF
REPO="$TMP_ROOT/bad-repo"
mkdir -p "$REPO"
OUT=$(run_detect "$REPO" "$BAD_ROOT")
assert_valid_json "case5 malformed stack.md still produces valid JSON" "$OUT"
assert_field "case5 no match crash — primary is null" '.primary_profile' "null" "$OUT"
assert_field "case5 parse_errors recorded" '.parse_errors | length' "1" "$OUT"

# ── Case 6: no plugins root at all → empty scan, no crash ──
EMPTY_ROOT="$TMP_ROOT/empty-plugins"
mkdir -p "$EMPTY_ROOT"
REPO="$TMP_ROOT/empty-repo"
mkdir -p "$REPO"
OUT=$(run_detect "$REPO" "$EMPTY_ROOT")
assert_valid_json "case6 empty plugins root" "$OUT"
assert_field "case6 stack_md_scanned is 0" '.stack_md_scanned' "0" "$OUT"
assert_field "case6 primary is null" '.primary_profile' "null" "$OUT"

# ── Case 7: --write-cache writes a JSON file under --cache-dir, keyed by repo hash ──
CACHE_DIR="$TMP_ROOT/cache-dir"
REPO="$TMP_ROOT/cache-write-repo"
mkdir -p "$REPO"
python3 "$DETECT" --repo "$REPO" --plugins-root "$REAL_PLUGINS_ROOT" --cache-dir "$CACHE_DIR" --write-cache >/dev/null
CACHE_FILE_COUNT=$(find "$CACHE_DIR" -name '*.json' | wc -l | tr -d ' ')
if [ "$CACHE_FILE_COUNT" = "1" ]; then
    pass_count=$((pass_count + 1)); printf 'PASS  %-64s exactly one cache file written\n' "case7 write-cache"
else
    fail_count=$((fail_count + 1)); printf 'FAIL  %-64s expected 1 cache file, found %s\n' "case7 write-cache" "$CACHE_FILE_COUNT"
fi
CACHE_FILE=$(find "$CACHE_DIR" -name '*.json' | head -1)
if [ -n "$CACHE_FILE" ]; then
    assert_field "case7 cache file has schema_version" '.schema_version' "1" "$(cat "$CACHE_FILE")"
fi

echo
echo "=== ${pass_count} passed, ${fail_count} failed ==="
[ "$fail_count" -eq 0 ]
