#!/usr/bin/env bash
# Fixture-based test harness for pr-prepare.sh. Every case builds a throwaway repository with
# a local bare remote under a temp root, so pushes never leave the machine.
#
# Run: bash plugins/sdlc/scripts/test-pr-prepare.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PREPARE="${SCRIPT_DIR}/pr-prepare.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not available"; exit 0; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-pr-prepare.XXXXXX")
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

# Sets REPO: a clone of a fresh bare remote with one commit on main.
fresh_repo() {
    local name="$1" remote="$TMP_ROOT/$1.git"
    REPO="$TMP_ROOT/$name"
    git init --quiet --bare "$remote"
    git init --quiet --initial-branch=main "$REPO" 2>/dev/null \
        || { git init --quiet "$REPO"; git -C "$REPO" checkout -q -b main 2>/dev/null; }
    git -C "$REPO" config user.email "test@example.com"
    git -C "$REPO" config user.name "Test"
    git -C "$REPO" config commit.gpgsign false
    printf 'seed\n' > "$REPO/README.md"
    git -C "$REPO" add README.md
    git -C "$REPO" commit --quiet -m "seed"
    git -C "$REPO" remote add origin "$remote"
    git -C "$REPO" push --quiet -u origin main 2>/dev/null
}

# ── read-only shape on a dirty feature branch ─────────────────────────────
fresh_repo readonly
git -C "$REPO" checkout -q -b feature/add-billing
printf 'x\n' > "$REPO/billing.txt"
out=$(bash "$PREPARE" --project-root "$REPO" --pr-base main --task-type feature)
assert_field "readonly: branch"            '.current_branch' "feature/add-billing" "$out"
assert_field "readonly: upstream"          '.has_upstream' false "$out"
assert_field "readonly: dirty"             '.dirty' true "$out"
assert_field "readonly: dirty file"        '.dirty_files[0]' "billing.txt" "$out"
assert_field "readonly: commits ahead"     '.commits_ahead' 0 "$out"
assert_field "readonly: cannot create PR"  '.can_create_pr' false "$out"
assert_field "readonly: type"              '.conventional_type' feat "$out"
assert_field "readonly: base from flag"    '.pr_base_resolved_from' flag "$out"
assert_field "readonly: committed null"    '.committed_sha' null "$out"
assert_field "readonly: still dirty after" '.dirty' true "$(bash "$PREPARE" --project-root "$REPO" --pr-base main)"

# ── commit + push ──────────────────────────────────────────────────────────
out=$(bash "$PREPARE" --project-root "$REPO" --pr-base main --task-type hotfix --commit-message "fix: add billing" --push)
assert_field "commit: sha set"             '.committed_sha | length' 40 "$out"
assert_field "commit: pushed"              '.pushed' true "$out"
assert_field "commit: upstream set"        '.upstream' "origin/feature/add-billing" "$out"
assert_field "commit: ahead"               '.commits_ahead' 1 "$out"
assert_field "commit: can create PR"       '.can_create_pr' true "$out"
assert_field "commit: clean"               '.dirty' false "$out"
assert_field "commit: hotfix→fix"          '.conventional_type' fix "$out"
assert_field "commit: message verbatim"    '.' "fix: add billing" "\"$(git -C "$REPO" log -1 --format=%s)\""
assert_field "commit: remote has branch"   '.' 1 "$(git -C "$TMP_ROOT/readonly.git" branch --list feature/add-billing | grep -c .)"

# ── second run on a clean tree: nothing to commit, push already up to date ─
out=$(bash "$PREPARE" --project-root "$REPO" --pr-base main --task-type docs --commit-message "docs: noop" --push)
assert_field "noop: no new sha"            '.committed_sha' null "$out"
assert_field "noop: warning"               '.warnings | any(startswith("nothing to commit"))' true "$out"
assert_field "noop: docs type"             '.conventional_type' docs "$out"

# ── base fallback and unknown task type ───────────────────────────────────
fresh_repo fallback
git -C "$REPO" checkout -q -b chore-branch
out=$(bash "$PREPARE" --project-root "$REPO" --task-type weird)
assert_field "fallback: base"              '.pr_base' main "$out"
assert_field "fallback: source"            '.pr_base_resolved_from' default-branch "$out"
assert_field "fallback: warning"           '.warnings | any(startswith("pr_base missing"))' true "$out"
assert_field "fallback: unknown type"      '.conventional_type' feat "$out"
assert_field "fallback: unknown warning"   '.warnings | any(contains("weird"))' true "$out"

# ── unresolvable base ─────────────────────────────────────────────────────
out=$(bash "$PREPARE" --project-root "$REPO" --pr-base develop --task-type release)
assert_field "no base: ahead null"         '.commits_ahead' null "$out"
assert_field "no base: cannot create"      '.can_create_pr' false "$out"
assert_field "no base: release→chore"      '.conventional_type' chore "$out"

# ── not a repository ──────────────────────────────────────────────────────
mkdir -p "$TMP_ROOT/plain"
out=$(bash "$PREPARE" --project-root "$TMP_ROOT/plain")
assert_field "not repo: error"             '.error' "not a git repository" "$out"

# ── usage errors ──────────────────────────────────────────────────────────
bash "$PREPARE" --push >/dev/null 2>&1; assert_field "usage: push without message" '.' 2 "$?"
bash "$PREPARE" --bogus >/dev/null 2>&1; assert_field "usage: unknown flag" '.' 2 "$?"

# ── credentials in the remote URL never reach the model ──────────────────
fresh_repo redact
git -C "$REPO" remote set-url origin "https://oauth2:ghp_SECRETTOKEN123@example.com/o/r.git"
out=$(bash "$PREPARE" --project-root "$REPO" --pr-base main)
assert_field "remote_url: userinfo stripped" '.remote_url' "https://example.com/o/r.git" "$out"
case "$out" in
    *SECRETTOKEN*) fail_count=$((fail_count + 1)); printf 'FAIL  credential leaked in pr-prepare output\n' ;;
    *) pass_count=$((pass_count + 1)); printf 'PASS  no credential in pr-prepare output\n' ;;
esac

printf '\n%d passed, %d failed\n' "$pass_count" "$fail_count"
[ "$fail_count" -eq 0 ]
