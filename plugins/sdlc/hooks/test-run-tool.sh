#!/usr/bin/env bash
# Test harness for run-tool.sh / _runner-lib.sh: applicability, local-vs-docker resolution,
# sdlc.local.yaml overrides, the docker probe cache and the --probe output.
#
# Docker is never required: a fake `docker` shim on PATH records every invocation to a log
# and answers `compose ps` / `compose exec` the way a running stack would.
#
# Run: bash plugins/sdlc/hooks/test-run-tool.sh
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN_TOOL="${HOOK_DIR}/run-tool.sh"

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-run-tool.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

export CLAUDE_PLUGIN_DATA="${TMP_ROOT}/plugin-data"
unset CLAUDE_PROJECT_DIR
unset SDLC_RUNNER_NO_CACHE

pass_count=0
fail_count=0

assert_eq() {
    local case_name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        pass_count=$((pass_count + 1)); printf 'PASS  %-70s = %s\n' "$case_name" "$actual"
    else
        fail_count=$((fail_count + 1)); printf 'FAIL  %-70s expected %q, got %q\n' "$case_name" "$expected" "$actual"
    fi
}

assert_contains() {
    local case_name="$1" needle="$2" haystack="$3"
    case "$haystack" in
        *"$needle"*) pass_count=$((pass_count + 1)); printf 'PASS  %-70s contains %q\n' "$case_name" "$needle" ;;
        *) fail_count=$((fail_count + 1)); printf 'FAIL  %-70s missing %q in %q\n' "$case_name" "$needle" "$haystack" ;;
    esac
}

# Sets PROJ. Called bare so the global reaches the caller.
fresh_project() {
    PROJ="${TMP_ROOT}/$1"
    rm -rf "$PROJ"
    mkdir -p "$PROJ/.claude"
}

# $1 = project, $2 = relative path. Creates an executable that appends its argv to a log.
fake_tool() {
    local path="$1/$2"
    mkdir -p "$(dirname "$path")"
    printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "%s/tool-calls.log"\necho "ran $(basename "$0")"\nexit ${FAKE_TOOL_EXIT:-0}\n' "$1" > "$path"
    chmod +x "$path"
}

# A PATH that contains only this directory of shims, plus the system basics bash needs.
# $1 = shim dir. Prints the PATH value.
shim_path() {
    printf '%s:/usr/bin:/bin' "$1"
}

# $1 = shim dir, $2 = running services (newline-separated). docker compose ps lists them;
# docker compose exec succeeds for any of them and logs every call.
fake_docker() {
    local dir="$1"
    mkdir -p "$dir"
    cat > "$dir/docker" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$dir/docker-calls.log"
case "\$*" in
    "compose ps --services --status running") printf '%s\n' "$2"; exit 0 ;;
    "compose exec -T "*) exit 0 ;;
    *) exit 1 ;;
esac
EOF
    chmod +x "$dir/docker"
}

run() { (cd "$PROJ" && bash "$RUN_TOOL" "$@" 2>&1); }

# ── applicability ──────────────────────────────────────────────────────────────

fresh_project no-php
fake_tool "$PROJ" vendor/bin/pint
out=$(run --lang php -- ./vendor/bin/pint x.php)
assert_eq "php without composer.json -> not applicable, nothing runs" "" "$out"
assert_eq "no tool-calls log written" "false" "$([ -f "$PROJ/tool-calls.log" ] && echo true || echo false)"
probe=$(run --lang php --probe -- ./vendor/bin/pint x.php)
assert_contains "probe reports applicable=false" '"applicable":false' "$probe"
assert_contains "probe reports mode none" '"mode":"none"' "$probe"

# ── local resolution ───────────────────────────────────────────────────────────

fresh_project php-local
: > "$PROJ/composer.json"
fake_tool "$PROJ" vendor/bin/pint
out=$(run --lang php -- ./vendor/bin/pint app/Foo.php)
assert_eq "php project with vendor/bin/pint -> runs locally" "ran pint" "$out"
assert_eq "pint received its arguments" "app/Foo.php" "$(cat "$PROJ/tool-calls.log")"
out=$(run --lang php --quiet -- ./vendor/bin/pint app/Foo.php)
assert_eq "--quiet silences the tool" "" "$out"
rc=$(run --lang php --quiet -- ./vendor/bin/pint x.php >/dev/null; echo $?)
assert_eq "--quiet exits 0" "0" "$rc"
rc=$(FAKE_TOOL_EXIT=3 run --lang php -- ./vendor/bin/pint x.php >/dev/null; echo $?)
assert_eq "without --quiet the tool's exit code propagates" "3" "$rc"
probe=$(run --lang php --probe -- ./vendor/bin/pint x.php)
assert_contains "probe: local mode" '"mode":"local"' "$probe"
assert_contains "probe: service null" '"service":null' "$probe"
assert_contains "probe: lang echoed" '"lang":"php"' "$probe"

fresh_project node-local
: > "$PROJ/package.json"
fake_tool "$PROJ" node_modules/.bin/prettier
mkdir -p "$TMP_ROOT/npx-shim"
printf '#!/bin/sh\necho "npx $*"\n' > "$TMP_ROOT/npx-shim/npx"; chmod +x "$TMP_ROOT/npx-shim/npx"
out=$(PATH="$(shim_path "$TMP_ROOT/npx-shim")" run --lang node -- npx --no-install prettier --write src/a.ts)
assert_eq "npx --no-install with node_modules/.bin present -> local" "npx --no-install prettier --write src/a.ts" "$out"
rm -f "$PROJ/node_modules/.bin/prettier"
out=$(PATH="$(shim_path "$TMP_ROOT/npx-shim")" run --lang node -- npx --no-install prettier --write src/a.ts)
assert_eq "npx --no-install without the package -> not local, no docker -> skipped" "" "$out"

fresh_project bare-missing
: > "$PROJ/pyproject.toml"
mkdir -p "$TMP_ROOT/empty-shims"
probe=$(PATH="$(shim_path "$TMP_ROOT/empty-shims")" run --lang python --probe -- ruff format a.py)
assert_contains "bare command absent, no docker -> mode none" '"mode":"none"' "$probe"
assert_contains "reason explains docker is missing" 'docker is not installed' "$probe"
assert_contains "applicable stays true" '"applicable":true' "$probe"

# ── sdlc.local.yaml override ───────────────────────────────────────────────────

fresh_project override-local
: > "$PROJ/composer.json"
printf 'phase_command_overrides:\n  development:\n    php_runner: php\n    artisan_runner: php artisan\n' > "$PROJ/.claude/sdlc.local.yaml"
probe=$(run --lang php --probe -- ./vendor/bin/pint x.php)
assert_contains "php_runner: php forces local even when the tool is absent" '"mode":"local"' "$probe"
assert_contains "reason names the override" 'override: php_runner' "$probe"

fresh_project override-docker
: > "$PROJ/composer.json"
printf 'phase_command_overrides:\n  development:\n    php_runner: "docker compose exec -T workspace php"\n' > "$PROJ/.claude/sdlc.local.yaml"
fake_tool "$PROJ" vendor/bin/pint
probe=$(run --lang php --probe -- ./vendor/bin/pint x.php)
assert_contains "docker compose exec override forces docker mode" '"mode":"docker"' "$probe"
assert_contains "service taken from the override" '"service":"workspace"' "$probe"

fresh_project override-other-lang
: > "$PROJ/composer.json"
printf 'phase_command_overrides:\n  development:\n    node_runner: node\n' > "$PROJ/.claude/sdlc.local.yaml"
probe=$(PATH="$(shim_path "$TMP_ROOT/empty-shims")" run --lang php --probe -- ./vendor/bin/pint x.php)
assert_contains "an override for another language is ignored" '"mode":"none"' "$probe"

# ── docker fallback ────────────────────────────────────────────────────────────

fresh_project docker-app
: > "$PROJ/composer.json"
printf 'services:\n  db:\n    image: postgres\n  app:\n    build: .\nvolumes:\n  data: {}\n' > "$PROJ/docker-compose.yml"
fake_docker "$TMP_ROOT/docker-shim" "app"
DPATH="$(shim_path "$TMP_ROOT/docker-shim")"
out=$(PATH="$DPATH" run --lang php -- ./vendor/bin/pint app/Foo.php)
assert_eq "no local pint, running app service -> runs via docker" "" "$out"
assert_contains "docker compose exec was invoked with the command" "compose exec -T app ./vendor/bin/pint app/Foo.php" "$(cat "$TMP_ROOT/docker-shim/docker-calls.log")"
assert_contains "service running check used one ps call" "compose ps --services --status running" "$(cat "$TMP_ROOT/docker-shim/docker-calls.log")"
probe=$(PATH="$DPATH" run --lang php --probe -- ./vendor/bin/pint x.php)
assert_contains "probe: docker mode" '"mode":"docker"' "$probe"
assert_contains "probe: service app" '"service":"app"' "$probe"

fresh_project docker-hint
: > "$PROJ/composer.json"
printf 'services:\n  app:\n    image: x\n  php:\n    image: y\n' > "$PROJ/compose.yaml"
rm -f "$TMP_ROOT/docker-shim/docker-calls.log"
fake_docker "$TMP_ROOT/docker-shim" "app
php"
probe=$(PATH="$DPATH" run --lang php --service-hint php --probe -- vendor/bin/php-cs-fixer fix x.php)
assert_contains "--service-hint wins when the service exists" '"service":"php"' "$probe"
probe=$(SDLC_RUNNER_NO_CACHE=1 PATH="$DPATH" run --lang php --service-hint nope --probe -- vendor/bin/php-cs-fixer fix x.php)
assert_contains "unknown hint falls back to the candidate order (app)" '"service":"app"' "$probe"

fresh_project docker-stopped
: > "$PROJ/composer.json"
printf 'services:\n  app:\n    image: x\n' > "$PROJ/compose.yaml"
fake_docker "$TMP_ROOT/docker-stopped-shim" ""
probe=$(PATH="$(shim_path "$TMP_ROOT/docker-stopped-shim")" run --lang php --probe -- ./vendor/bin/pint x.php)
assert_contains "service not running -> mode none" '"mode":"none"' "$probe"
assert_contains "reason mentions the compose service" 'running compose service' "$probe"

fresh_project no-compose
: > "$PROJ/composer.json"
probe=$(PATH="$DPATH" run --lang php --probe -- ./vendor/bin/pint x.php)
assert_contains "docker present but no compose file -> none" 'no compose file' "$probe"

# ── cache ──────────────────────────────────────────────────────────────────────

fresh_project cache
: > "$PROJ/composer.json"
printf 'services:\n  app:\n    image: x\n' > "$PROJ/compose.yaml"
rm -f "$TMP_ROOT/docker-shim/docker-calls.log"
fake_docker "$TMP_ROOT/docker-shim" "app"
PATH="$DPATH" run --lang php --probe -- ./vendor/bin/pint x.php >/dev/null
first=$(grep -c "compose ps" "$TMP_ROOT/docker-shim/docker-calls.log")
PATH="$DPATH" run --lang php --probe -- ./vendor/bin/pint x.php >/dev/null
second=$(grep -c "compose ps" "$TMP_ROOT/docker-shim/docker-calls.log")
assert_eq "first resolution probes docker once" "1" "$first"
assert_eq "second resolution is served from cache (no new ps call)" "1" "$second"
probe=$(PATH="$DPATH" run --lang php --probe -- ./vendor/bin/pint x.php)
assert_contains "cached answer is marked" '(cached)' "$probe"
assert_eq "cache lives under CLAUDE_PLUGIN_DATA/runner-cache" "true" "$(ls "$CLAUDE_PLUGIN_DATA/runner-cache"/*.txt >/dev/null 2>&1 && echo true || echo false)"
SDLC_RUNNER_NO_CACHE=1 PATH="$DPATH" run --lang php --probe -- ./vendor/bin/pint x.php >/dev/null
third=$(grep -c "compose ps" "$TMP_ROOT/docker-shim/docker-calls.log")
assert_eq "SDLC_RUNNER_NO_CACHE=1 re-probes" "2" "$third"
sleep 1
touch "$PROJ/compose.yaml"
PATH="$DPATH" run --lang php --probe -- ./vendor/bin/pint x.php >/dev/null
fourth=$(grep -c "compose ps" "$TMP_ROOT/docker-shim/docker-calls.log")
assert_eq "a changed compose file invalidates the cache" "3" "$fourth"
PATH="$DPATH" run --lang php --probe -- ./vendor/bin/phpstan analyse >/dev/null
fifth=$(grep -c "compose ps" "$TMP_ROOT/docker-shim/docker-calls.log")
assert_eq "a different command gets its own cache entry" "4" "$fifth"

# ── CLAUDE_PROJECT_DIR and argument handling ───────────────────────────────────

fresh_project env-root
: > "$PROJ/composer.json"
fake_tool "$PROJ" vendor/bin/pint
out=$(cd "$TMP_ROOT" && CLAUDE_PROJECT_DIR="$PROJ" bash "$RUN_TOOL" --lang php -- ./vendor/bin/pint y.php 2>&1)
assert_eq "CLAUDE_PROJECT_DIR is the project root when set" "ran pint" "$out"
out=$(run --lang php 2>&1; echo "rc=$?")
assert_eq "no command -> exit 0 silently" "rc=0" "$out"
out=$(run -- ./vendor/bin/pint 2>&1; echo "rc=$?")
assert_eq "no --lang -> exit 0 silently" "rc=0" "$out"
probe=$(run --lang any --probe -- ./vendor/bin/pint x.php)
assert_contains "--lang any always applies" '"applicable":true' "$probe"

printf '\n=== %d passed, %d failed ===\n' "$pass_count" "$fail_count"
[ "$fail_count" -eq 0 ]
