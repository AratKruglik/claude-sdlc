#!/usr/bin/env bash
# Fixture-based test harness for detect-git-flow.sh.
#
# Each case builds a throwaway git repository under a temp root and asserts on the
# detector's JSON output. Nothing touches the real repo, the network, or ~/.claude —
# --allow-network is never passed, so no case can reach out to a remote.
#
# Run: bash plugins/sdlc/scripts/test-detect-git-flow.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="${SCRIPT_DIR}/detect-git-flow.sh"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-gitflow-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

pass_count=0
fail_count=0

# $1 = case name, $2 = jq filter, $3 = expected value, $4 = actual JSON
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

# Builds a repo with one commit on $2 (default branch), then creates every branch in $3..
# Branches are created with `git branch` off the initial commit — no checkout churn.
fresh_repo() {
    local name="$1" default_branch="$2"; shift 2
    local dir="$TMP_ROOT/$name"
    mkdir -p "$dir"
    git -C "$dir" init --quiet --initial-branch="$default_branch" 2>/dev/null \
        || { git -C "$dir" init --quiet; git -C "$dir" checkout -q -b "$default_branch" 2>/dev/null; }
    git -C "$dir" config user.email "test@example.com"
    git -C "$dir" config user.name "Test"
    git -C "$dir" config commit.gpgsign false
    printf 'seed\n' > "$dir/README.md"
    git -C "$dir" add README.md
    git -C "$dir" commit --quiet -m "seed"
    for branch in "$@"; do
        git -C "$dir" branch "$branch" >/dev/null 2>&1
    done
    printf '%s' "$dir"
}

run_detect() {
    bash "$DETECT" --repo "$1" 2>/dev/null
}

echo "=== detect-git-flow.sh ==="
echo

# ── Case 1: classic git-flow — develop + prefixed branches ──
REPO=$(fresh_repo "gitflow" main develop feature/checkout hotfix/npe release/1.2.0 feature/cart)
OUT=$(run_detect "$REPO")
assert_valid_json "case1 git-flow" "$OUT"
assert_field "case1 model" '.model' "git-flow" "$OUT"
assert_field "case1 develop branch" '.develop_branch' "develop" "$OUT"
assert_field "case1 default branch" '.default_branch' "main" "$OUT"
assert_field "case1 release branch listed" '.release_branches[0]' "release/1.2.0" "$OUT"
assert_field "case1 feature prefix counted" '.prefix_histogram.feature' "2" "$OUT"

# ── Case 2: git flow init'ed, but develop not created yet → config-only signal ──
REPO=$(fresh_repo "gitflow-config" main)
git -C "$REPO" config gitflow.branch.master main
git -C "$REPO" config gitflow.branch.develop develop
OUT=$(run_detect "$REPO")
assert_valid_json "case2 gitflow config only" "$OUT"
assert_field "case2 model" '.model' "git-flow" "$OUT"
assert_field "case2 no develop branch yet" '.develop_branch' "null" "$OUT"
assert_field "case2 confidence is medium" '.confidence' "medium" "$OUT"
assert_field "case2 config keys counted" '.gitflow_config_keys' "2" "$OUT"

# ── Case 3: github-flow with prefixes + a typo singleton that must NOT be learned ──
REPO=$(fresh_repo "githubflow" main feature/a feature/b fix/c fix/d feaature/typo docs/e)
OUT=$(run_detect "$REPO")
assert_valid_json "case3 github-flow" "$OUT"
assert_field "case3 model" '.model' "github-flow" "$OUT"
assert_field "case3 prefix style" '.prefix_style' "conventional" "$OUT"
assert_field "case3 feature counted" '.prefix_histogram.feature' "2" "$OUT"
assert_field "case3 typo singleton discarded" '.prefix_histogram.feaature' "null" "$OUT"
assert_field "case3 docs singleton discarded" '.prefix_histogram.docs' "null" "$OUT"
assert_field "case3 separator" '.naming.separator' "/" "$OUT"
# Named observed_* deliberately: it is the longest existing name, never a length cap.
# GIT-FLOW.md Step E caps at 60 (or explicit config) — deriving a limit from this would
# truncate every future branch in a repo whose longest name happens to be short.
assert_field "case3 observed length is reported" '.naming.observed_max_length' "13" "$OUT"  # feaature/typo
assert_field "case3 no max_length field to misread" '.naming.max_length' "null" "$OUT"

# ── Case 4: trunk-ish — unprefixed branch names, no convention to learn ──
REPO=$(fresh_repo "trunkish" main add-healthz-endpoint tidy-logging)
OUT=$(run_detect "$REPO")
assert_valid_json "case4 trunk-ish" "$OUT"
assert_field "case4 model" '.model' "github-flow" "$OUT"
assert_field "case4 no prefix convention" '.prefix_style' "none" "$OUT"
assert_field "case4 histogram empty" '.prefix_histogram | length' "0" "$OUT"

# ── Case 5: ticket ids in the description slot ──
REPO=$(fresh_repo "tickets" main feature/PROJ-12-add-cart fix/PROJ-13-null-guard feature/PROJ-19-coupons)
OUT=$(run_detect "$REPO")
assert_valid_json "case5 ticket convention" "$OUT"
assert_field "case5 ticket pattern learned" '.naming.ticket_pattern' '^[A-Z][A-Z0-9]{1,9}-[0-9]+$' "$OUT"
assert_field "case5 ticket position" '.naming.ticket_position' "after-prefix" "$OUT"

# ── Case 6: a single ticket branch is not a convention ──
REPO=$(fresh_repo "one-ticket" main feature/PROJ-12-add-cart feature/plain-slug fix/another-slug)
OUT=$(run_detect "$REPO")
assert_field "case6 single ticket not learned" '.naming.ticket_pattern' "null" "$OUT"

# ── Case 7: underscore word separator ──
REPO=$(fresh_repo "underscores" main feature/add_cart feature/fix_totals fix/null_guard)
OUT=$(run_detect "$REPO")
assert_field "case7 word separator" '.naming.word_separator' "_" "$OUT"

# ── Case 8: dash-separated prefixes (no slashes anywhere) ──
REPO=$(fresh_repo "dashes" main feature-add-cart fix-null-guard fix-totals)
OUT=$(run_detect "$REPO")
assert_valid_json "case8 dash separator" "$OUT"
assert_field "case8 separator learned as dash" '.naming.separator' "-" "$OUT"
assert_field "case8 fix prefix counted" '.prefix_histogram.fix' "2" "$OUT"

# ── Case 9: non-conventional vocabulary is reported, not discarded ──
REPO=$(fresh_repo "custom-vocab" main ticket/aaa ticket/bbb spike/ccc spike/ddd)
OUT=$(run_detect "$REPO")
assert_field "case9 custom vocabulary flagged" '.prefix_style' "custom" "$OUT"
assert_field "case9 observed prefix kept" '.prefix_histogram.ticket' "2" "$OUT"

# ── Case 10: base-branch awareness for the branch gate ──
REPO=$(fresh_repo "on-base" main develop feature/x)
OUT=$(run_detect "$REPO")
assert_field "case10 current branch" '.current_branch' "main" "$OUT"
assert_field "case10 current is a base branch" '.current_branch_is_base' "true" "$OUT"
git -C "$REPO" checkout -q feature/x
OUT=$(run_detect "$REPO")
assert_field "case10 task branch is not base" '.current_branch_is_base' "false" "$OUT"

# ── Case 11: dirty worktree count ──
REPO=$(fresh_repo "dirty" main feature/x)
printf 'change\n' >> "$REPO/README.md"
printf 'new\n' > "$REPO/untracked.txt"
OUT=$(run_detect "$REPO")
assert_field "case11 dirty files counted" '.dirty_file_count' "2" "$OUT"

# ── Case 12: repository with no commits at all → unknown, never a hard failure ──
EMPTY="$TMP_ROOT/empty"
mkdir -p "$EMPTY"
git -C "$EMPTY" init --quiet 2>/dev/null
OUT=$(run_detect "$EMPTY")
rc=$?
assert_valid_json "case12 empty repo" "$OUT"
assert_field "case12 model unknown" '.model' "unknown" "$OUT"
if [ "$rc" -eq 0 ]; then
    pass_count=$((pass_count + 1)); printf 'PASS  %-64s exit code 0\n' "case12 empty repo"
else
    fail_count=$((fail_count + 1)); printf 'FAIL  %-64s exit code %d\n' "case12 empty repo" "$rc"
fi

# ── Case 13: not a git repository → unknown, exit 0 ──
NOTGIT="$TMP_ROOT/notgit"
mkdir -p "$NOTGIT"
OUT=$(run_detect "$NOTGIT")
rc=$?
assert_valid_json "case13 non-git dir" "$OUT"
assert_field "case13 model unknown" '.model' "unknown" "$OUT"
if [ "$rc" -eq 0 ]; then
    pass_count=$((pass_count + 1)); printf 'PASS  %-64s exit code 0\n' "case13 non-git dir"
else
    fail_count=$((fail_count + 1)); printf 'FAIL  %-64s exit code %d\n' "case13 non-git dir" "$rc"
fi

# ── Case 14: master as the default branch ──
REPO=$(fresh_repo "master-default" master feature/a feature/b)
OUT=$(run_detect "$REPO")
assert_field "case14 default branch" '.default_branch' "master" "$OUT"
assert_field "case14 master is a base branch" '.current_branch_is_base' "true" "$OUT"

# ── Case 15: dev (not develop) still means git-flow ──
REPO=$(fresh_repo "dev-alias" main dev feature/a)
OUT=$(run_detect "$REPO")
assert_field "case15 dev alias detected" '.develop_branch' "dev" "$OUT"
assert_field "case15 model" '.model' "git-flow" "$OUT"

echo
echo "=== ${pass_count} passed, ${fail_count} failed ==="
[ "$fail_count" -eq 0 ]
