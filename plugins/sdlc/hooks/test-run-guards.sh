#!/usr/bin/env bash
# Test harness for the three run-scoped guard hooks: config-protection.sh,
# pre-commit-guard.sh and post-implement-check.sh.
#
# Every case builds a throwaway project under a temp root. Nothing touches the real repo,
# and no case runs git against anything but its own fixture.
#
# Run: bash plugins/sdlc/hooks/test-run-guards.sh
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_GUARD="${HOOK_DIR}/config-protection.sh"
COMMIT_GUARD="${HOOK_DIR}/pre-commit-guard.sh"
POST_CHECK="${HOOK_DIR}/post-implement-check.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not available"; exit 0; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-guards.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

pass_count=0
fail_count=0

assert_eq() {
    local case_name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        pass_count=$((pass_count + 1)); printf 'PASS  %-68s = %s\n' "$case_name" "$actual"
    else
        fail_count=$((fail_count + 1)); printf 'FAIL  %-68s expected %q, got %q\n' "$case_name" "$expected" "$actual"
    fi
}

assert_contains() {
    local case_name="$1" needle="$2" haystack="$3"
    case "$haystack" in
        *"$needle"*) pass_count=$((pass_count + 1)); printf 'PASS  %-68s contains %q\n' "$case_name" "$needle" ;;
        *) fail_count=$((fail_count + 1)); printf 'FAIL  %-68s missing %q in %q\n' "$case_name" "$needle" "$haystack" ;;
    esac
}

decision() {
    # An empty hook response is how PreToolUse says "allow".
    [ -n "$1" ] || { echo allow; return; }
    printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null || echo allow
}
reason()   { printf '%s' "$1" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null; }

# Portable across BSD and GNU date. The BSD -v form is tried second because GNU date
# accepts -v as an unknown option rather than failing loudly.
iso_offset() {
    local off="$1" gnu_expr=""
    case "$off" in
        -*M) gnu_expr="${off#-}"; gnu_expr="${gnu_expr%M} minutes ago" ;;
        -*H) gnu_expr="${off#-}"; gnu_expr="${gnu_expr%H} hours ago" ;;
    esac
    if [ -n "$gnu_expr" ] && date -u -d "$gnu_expr" +"%Y-%m-%dT%H:%M:%S+00:00" 2>/dev/null; then
        return 0
    fi
    date -u -v"$off" +"%Y-%m-%dT%H:%M:%S+00:00"
}

# Sets the global PROJ. Called bare, not in $(...): the global must reach the caller.
fresh_project() {
    PROJ="${TMP_ROOT}/$1"
    rm -rf "$PROJ"
    mkdir -p "$PROJ/.claude"
    git -C "$PROJ" init -q 2>/dev/null
    # Pin the initial branch: `git init` defaults to master on the CI runner and main
    # locally, and the fixtures state base_branch explicitly.
    git -C "$PROJ" symbolic-ref HEAD refs/heads/main 2>/dev/null
    git -C "$PROJ" config user.email t@example.com
    git -C "$PROJ" config user.name Test
}

write_state() {
    # $1 = project, $2 = updated_at, $3 = task_type, $4 = base_branch
    printf '{"schema_version":2,"task_slug":"demo","started_at":"%s","updated_at":"%s","git_flow":{"task_type":"%s","base_branch":"%s"}}\n' \
        "$2" "$2" "${3:-feature}" "${4:-main}" > "$1/.claude/.sdlc-run-active.json"
}

run_config() {
    # $1 = project, $2 = file_path, $3.. = globs
    local proj="$1" file="$2"; shift 2
    bash "$CONFIG_GUARD" "$@" <<EOF
{"hook_event_name":"PreToolUse","tool_name":"Edit","cwd":"$proj","tool_input":{"file_path":"$file"}}
EOF
}

run_commit() {
    # $1 = project, $2 = command
    bash "$COMMIT_GUARD" <<EOF
{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"$1","tool_input":{"command":$(printf '%s' "$2" | jq -Rs .)}}
EOF
}

run_post() {
    # $1 = project, $2.. = check command
    local proj="$1"; shift
    bash "$POST_CHECK" "$@" <<EOF
{"hook_event_name":"SubagentStop","cwd":"$proj","session_id":"s1","agent_id":"a1","agent_type":"laravel-plugin:laravel-architect"}
EOF
}

echo "=== run-scoped guard hooks ==="
echo

# ── config-protection ──
fresh_project "cfg-norun"
printf '{}\n' > "$PROJ/pint.json"
OUT=$(run_config "$PROJ" "$PROJ/pint.json" 'pint.json')
assert_eq "config: no run state -> allow (a human editing config is never blocked)" "allow" "$(decision "$OUT")"

fresh_project "cfg-stale"
printf '{}\n' > "$PROJ/pint.json"
write_state "$PROJ" "$(iso_offset -8H)" feature main
OUT=$(run_config "$PROJ" "$PROJ/pint.json" 'pint.json')
assert_eq "config: stale run state -> allow" "allow" "$(decision "$OUT")"

fresh_project "cfg-deny"
printf '{}\n' > "$PROJ/pint.json"
write_state "$PROJ" "$(iso_offset -10M)" feature main
OUT=$(run_config "$PROJ" "$PROJ/pint.json" 'pint.json' 'phpstan.neon*')
assert_eq "config: fresh run + protected file -> deny" "deny" "$(decision "$OUT")"
assert_contains "config: reason names the file" "pint.json" "$(reason "$OUT")"
assert_contains "config: reason offers the chore escape hatch" "chore" "$(reason "$OUT")"

fresh_project "cfg-chore"
printf '{}\n' > "$PROJ/pint.json"
write_state "$PROJ" "$(iso_offset -10M)" chore main
OUT=$(run_config "$PROJ" "$PROJ/pint.json" 'pint.json')
assert_eq "config: chore run -> allow (this is how config is deliberately changed)" "allow" "$(decision "$OUT")"

fresh_project "cfg-glob"
mkdir -p "$PROJ/sub"
printf '{}\n' > "$PROJ/sub/phpstan.neon.dist"
write_state "$PROJ" "$(iso_offset -10M)" feature main
OUT=$(run_config "$PROJ" "$PROJ/sub/phpstan.neon.dist" 'phpstan.neon*')
assert_eq "config: glob matches basename in a subdirectory" "deny" "$(decision "$OUT")"

fresh_project "cfg-other"
printf 'x\n' > "$PROJ/src.php"
write_state "$PROJ" "$(iso_offset -10M)" feature main
OUT=$(run_config "$PROJ" "$PROJ/src.php" 'pint.json')
assert_eq "config: unprotected file -> allow" "allow" "$(decision "$OUT")"

# ── pre-commit-guard ──
fresh_project "commit-norun"
OUT=$(run_commit "$PROJ" "git commit --no-verify -m wip")
assert_eq "commit: no run state -> allow even with --no-verify" "allow" "$(decision "$OUT")"

fresh_project "commit-noverify"
write_state "$PROJ" "$(iso_offset -10M)" feature main
OUT=$(run_commit "$PROJ" "git commit --no-verify -m wip")
assert_eq "commit: --no-verify during a run -> deny" "deny" "$(decision "$OUT")"
assert_contains "commit: reason explains the alternative" "fix or disable the hook" "$(reason "$OUT")"

fresh_project "commit-notgit"
write_state "$PROJ" "$(iso_offset -10M)" feature main
OUT=$(run_commit "$PROJ" "npm test")
assert_eq "commit: unrelated Bash command -> allow" "allow" "$(decision "$OUT")"

fresh_project "commit-aws"
write_state "$PROJ" "$(iso_offset -10M)" feature main
printf 'const key = "AKIAIOSFODNN7EXAMPLE";\n' > "$PROJ/config.js"
git -C "$PROJ" add config.js
OUT=$(run_commit "$PROJ" "git commit -m 'add config'")
assert_eq "commit: staged AWS key -> deny" "deny" "$(decision "$OUT")"
assert_contains "commit: reason names file:line" "config.js:1" "$(reason "$OUT")"
assert_contains "commit: reason says rotate" "rotate" "$(reason "$OUT")"

fresh_project "commit-privkey"
write_state "$PROJ" "$(iso_offset -10M)" feature main
printf 'x\n-----BEGIN RSA PRIVATE KEY-----\n' > "$PROJ/id.pem"
git -C "$PROJ" add id.pem
OUT=$(run_commit "$PROJ" "git commit -m keys")
assert_eq "commit: staged private key block -> deny" "deny" "$(decision "$OUT")"

fresh_project "commit-clean"
write_state "$PROJ" "$(iso_offset -10M)" feature main
printf 'export const add = (a, b) => a + b;\n' > "$PROJ/util.js"
git -C "$PROJ" add util.js
OUT=$(run_commit "$PROJ" "git commit -m 'add util'")
assert_eq "commit: clean staged diff -> allow" "allow" "$(decision "$OUT")"

fresh_project "commit-removal"
write_state "$PROJ" "$(iso_offset -10M)" feature main
printf 'const key = "AKIAIOSFODNN7EXAMPLE";\n' > "$PROJ/config.js"
git -C "$PROJ" add config.js && git -C "$PROJ" commit -qm seed
printf 'const key = process.env.AWS_KEY;\n' > "$PROJ/config.js"
git -C "$PROJ" add config.js
OUT=$(run_commit "$PROJ" "git commit -m 'move key to env'")
assert_eq "commit: REMOVING a secret is the fix, not the defect -> allow" "allow" "$(decision "$OUT")"

fresh_project "commit-debug"
write_state "$PROJ" "$(iso_offset -10M)" feature main
printf 'console.log("here");\n' > "$PROJ/app.js"
git -C "$PROJ" add app.js
OUT=$(run_commit "$PROJ" "git commit -m wip")
assert_eq "commit: debug statement warns, never denies" "allow" "$(decision "$OUT")"
assert_contains "commit: warning is a systemMessage" "debug statement" "$(printf '%s' "$OUT" | jq -r '.systemMessage // ""')"

fresh_project "commit-debug-test"
write_state "$PROJ" "$(iso_offset -10M)" feature main
mkdir -p "$PROJ/tests"
printf 'console.log("here");\n' > "$PROJ/tests/app.test.js"
git -C "$PROJ" add tests/app.test.js
OUT=$(run_commit "$PROJ" "git commit -m tests")
assert_eq "commit: debug statement in a test path is not flagged" "" "$(printf '%s' "$OUT" | jq -r '.systemMessage // ""')"

# ── post-implement-check ──
fresh_project "post-norun"
OUT=$(run_post "$PROJ" false)
assert_eq "post: no run state -> silent" "" "$OUT"

fresh_project "post-notool"
write_state "$PROJ" "$(iso_offset -10M)" feature main
OUT=$(run_post "$PROJ" definitely-not-a-real-binary-xyz)
assert_eq "post: absent tool -> silent (not a finding)" "" "$OUT"

fresh_project "post-pass"
write_state "$PROJ" "$(iso_offset -10M)" feature main
printf 'a\n' > "$PROJ/f.txt"
git -C "$PROJ" add f.txt && git -C "$PROJ" commit -qm seed
printf 'b\n' > "$PROJ/f.txt"
git -C "$PROJ" add f.txt && git -C "$PROJ" commit -qm change
OUT=$(run_post "$PROJ" true)
assert_eq "post: passing check -> silent" "" "$OUT"

fresh_project "post-fail"
write_state "$PROJ" "$(iso_offset -10M)" feature main
printf 'a\n' > "$PROJ/f.txt"
git -C "$PROJ" add f.txt && git -C "$PROJ" commit -qm seed
git -C "$PROJ" checkout -qb work
printf 'b\n' > "$PROJ/f.txt"
git -C "$PROJ" add f.txt && git -C "$PROJ" commit -qm change
OUT=$(run_post "$PROJ" sh -c 'echo "type error on line 3"; exit 1')
MSG=$(printf '%s' "$OUT" | jq -r '.systemMessage // ""')
assert_contains "post: failing check surfaces as systemMessage" "type error on line 3" "$MSG"
assert_contains "post: message names the agent" "laravel-architect" "$MSG"
assert_contains "post: message frames output as a retry hint" "retry hint" "$MSG"
assert_eq "post: never denies (SubagentStop cannot)" "allow" "$(decision "$OUT")"

fresh_project "post-cap"
write_state "$PROJ" "$(iso_offset -10M)" feature main
printf 'a\n' > "$PROJ/f.txt"
git -C "$PROJ" add f.txt && git -C "$PROJ" commit -qm seed
git -C "$PROJ" checkout -qb work
printf 'b\n' > "$PROJ/f.txt"
git -C "$PROJ" add f.txt && git -C "$PROJ" commit -qm change
OUT=$(run_post "$PROJ" sh -c 'for i in $(seq 1 100); do echo "error $i"; done; exit 1')
MSG=$(printf '%s' "$OUT" | jq -r '.systemMessage // ""')
assert_contains "post: output is capped" "100 lines total" "$MSG"
BODY_LINES=$(printf '%s\n' "$MSG" | grep -c '^error ')
assert_eq "post: at most 40 error lines relayed" "40" "$BODY_LINES"

echo
echo "=== ${pass_count} passed, ${fail_count} failed ==="
[ "$fail_count" -eq 0 ]
