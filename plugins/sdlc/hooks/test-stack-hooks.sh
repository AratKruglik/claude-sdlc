#!/usr/bin/env bash
# Test harness for the hook commands every stack plugin registers in its hooks/hooks.json:
#
#   - the PreToolUse / SubagentStop entries that locate sdlc's config-protection.sh and
#     post-implement-check.sh — in the installed cache (cache/<marketplace>/<plugin>/<version>/)
#     and in a dev checkout (plugins/<plugin>/);
#   - the PostToolUse formatter entry, which must take the edited path from the hook payload.
#
# Each command is read verbatim from hooks.json and run the way Claude Code runs a shell-form
# hook: `sh -c "<command>"`, payload on stdin, CLAUDE_PLUGIN_ROOT in the environment. sdlc's
# scripts and the formatters are stubs that report how they were called, so these cases cover
# resolution and argument passing only; test-run-guards.sh covers the guards' own logic.
#
# Run: bash plugins/sdlc/hooks/test-stack-hooks.sh
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGINS_DIR="$(cd "${HOOK_DIR}/../.." && pwd)"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-stack-hooks.XXXXXX")
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

# $1 = directory to fill with stand-ins for sdlc's guard scripts. Each prints its own path,
# which is how a case tells which copy the command resolved.
stub_guards() {
    mkdir -p "$1"
    for n in config-protection.sh post-implement-check.sh; do
        printf '#!/usr/bin/env bash\necho "%s"\n' "$1/$n" > "$1/$n"
    done
}

# $1 = CLAUDE_PLUGIN_ROOT, $2 = working directory, $3 = command. Payload on stdin.
run_hook() { (cd "$2" && CLAUDE_PLUGIN_ROOT="$1" sh -c "$3" 2>/dev/null); }

# Installed cache: sdlc at the stack plugin's own version.
SAME="${TMP_ROOT}/same/cache/mkt"
stub_guards "${SAME}/sdlc/2.0.0/hooks"
# Installed cache: sdlc at another version, next to an orphaned one awaiting cleanup.
DIVERGED="${TMP_ROOT}/diverged/cache/mkt"
stub_guards "${DIVERGED}/sdlc/1.9.0/hooks"
touch "${DIVERGED}/sdlc/1.9.0/.orphaned_at"
stub_guards "${DIVERGED}/sdlc/2.0.1/hooks"
# Dev checkout: plugins side by side.
DEV="${TMP_ROOT}/dev/plugins"
stub_guards "${DEV}/sdlc/hooks"

# Formatter stand-ins: each logs its name and arguments. docker fails, as it does on a machine
# without the compose service, so every command reaches its local fallback.
STUBS="${TMP_ROOT}/bin"
LOG="${TMP_ROOT}/formatter.log"
mkdir -p "$STUBS"
for tool in ruff npx dotnet; do
    printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$tool" "$LOG" > "${STUBS}/${tool}"
done
printf '#!/bin/sh\nexit 1\n' > "${STUBS}/docker"
# A jq that is "not installed", to force the python3 branch of the payload read.
NOJQ="${TMP_ROOT}/nojq"
mkdir -p "$NOJQ"
printf '#!/bin/sh\nexit 127\n' > "${NOJQ}/jq"
chmod +x "$STUBS"/* "$NOJQ"/jq

PROJ="${TMP_ROOT}/project"
mkdir -p "${PROJ}/vendor/bin" "${PROJ}/src"
printf '{"devDependencies": {"prettier": "3", "eslint": "9"}}\n' > "${PROJ}/package.json"
for f in pom.xml build.gradle.kts build.gradle; do echo spotless > "${PROJ}/${f}"; done
for tool in mvnw gradlew vendor/bin/pint vendor/bin/php-cs-fixer; do
    printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$tool" "$LOG" > "${PROJ}/${tool}"
    chmod +x "${PROJ}/${tool}"
done
# Language markers run-tool.sh uses to decide a stack applies to the project at all, and the
# local npm binaries it requires before it treats `npx --no-install <pkg>` as installed.
: > "${PROJ}/composer.json"; : > "${PROJ}/pyproject.toml"; : > "${PROJ}/App.csproj"
mkdir -p "${PROJ}/node_modules/.bin"
for tool in prettier eslint; do
    printf '#!/bin/sh\necho "%s $*" >> "%s"\n' "$tool" "$LOG" > "${PROJ}/node_modules/.bin/${tool}"
    chmod +x "${PROJ}/node_modules/.bin/${tool}"
done
# A project of a language none of the stacks cover: the same stubs are on PATH, but nothing in
# the project says a formatter applies, so nothing may run.
BARE="${TMP_ROOT}/bare"
mkdir -p "${BARE}/src"

# The formatter entries call the real run-tool.sh through the same lookup as the guards.
for root in "$SAME" "$DEV/.."; do
    dest="${root}/sdlc/2.0.0/hooks"
    [ "$root" = "$DEV/.." ] && dest="${DEV}/sdlc/hooks"
    mkdir -p "$dest"
    cp "${HOOK_DIR}/run-tool.sh" "${HOOK_DIR}/_runner-lib.sh" "$dest/"
done

echo "=== stack plugin hook commands ==="

for hooks in "$PLUGINS_DIR"/*/hooks/hooks.json; do
    plugin=$(basename "$(dirname "$(dirname "$hooks")")")
    [ "$plugin" = "sdlc" ] && continue

    for n in config-protection.sh post-implement-check.sh; do
        cmd=$(jq -r --arg n "$n" '.hooks[][].hooks[] | select(.command | contains($n)) | .command' "$hooks")
        [ -n "$cmd" ] || continue
        mkdir -p "${SAME}/${plugin}/2.0.0" "${DIVERGED}/${plugin}/2.0.0" "${DEV}/${plugin}"

        out=$(run_hook "${SAME}/${plugin}/2.0.0" "$PROJ" "$cmd" </dev/null)
        assert_eq "${plugin}: ${n} in cache, same version" "${SAME}/sdlc/2.0.0/hooks/${n}" "$out"
        out=$(run_hook "${DIVERGED}/${plugin}/2.0.0" "$PROJ" "$cmd" </dev/null)
        assert_eq "${plugin}: ${n} in cache, other version, orphan skipped" "${DIVERGED}/sdlc/2.0.1/hooks/${n}" "$out"
        out=$(run_hook "${DEV}/${plugin}" "$PROJ" "$cmd" </dev/null)
        assert_eq "${plugin}: ${n} in dev checkout" "${DEV}/sdlc/hooks/${n}" "$out"
    done

    cmd=$(jq -r '.hooks.PostToolUse[]?.hooks[] | select(.command | contains("tool_input.file_path")) | .command' "$hooks")
    if [ -z "$cmd" ]; then
        assert_eq "${plugin}: formatter reads the payload" "present" "missing"
        continue
    fi
    # The first pattern of `case "$f" in *.ext|...)` names a file the command formats.
    body=${cmd#*'case "$f" in '}
    pattern=${body%%)*}; pattern=${pattern%%|*}
    payload=$(jq -cn --arg f "${PROJ}/src/example${pattern#\*}" \
        '{hook_event_name: "PostToolUse", tool_name: "Edit", tool_input: {file_path: $f}}')
    # Read back rather than reuse: on Windows, MSYS rewrites /tmp paths passed to a native jq.
    file=$(printf '%s' "$payload" | jq -j '.tool_input.file_path')

    for reader in jq python3; do
        if [ "$reader" = python3 ]; then
            command -v python3 >/dev/null 2>&1 || continue
            path="${NOJQ}:${STUBS}:${PATH}"
        else
            path="${STUBS}:${PATH}"
        fi
        rm -f "$LOG"
        printf '%s' "$payload" | PATH="$path" run_hook "${SAME}/${plugin}/2.0.0" "$PROJ" "$cmd"
        ran=$( [ -s "$LOG" ] && echo yes || echo no )
        assert_eq "${plugin}: formatter runs on ${file##*/} (${reader})" "yes" "$ran"
        # Commands that hand "$f" to the formatter must hand it the payload's path.
        case "${body#*)}" in
            *'"$f"'*) assert_eq "${plugin}: formatter got the edited path (${reader})" "yes" \
                          "$(grep -qF "$file" "$LOG" 2>/dev/null && echo yes || echo no)" ;;
        esac
    done

    rm -f "$LOG"
    printf '' | PATH="${STUBS}:${PATH}" run_hook "${SAME}/${plugin}/2.0.0" "$PROJ" "$cmd"
    assert_eq "${plugin}: formatter is silent without a payload" "no" "$( [ -s "$LOG" ] && echo yes || echo no )"

    rm -f "$LOG"
    barefile="${BARE}/src/example${pattern#\*}"
    jq -cn --arg f "$barefile" '{hook_event_name: "PostToolUse", tool_name: "Edit", tool_input: {file_path: $f}}' \
        | PATH="${STUBS}:${PATH}" run_hook "${SAME}/${plugin}/2.0.0" "$BARE" "$cmd"
    assert_eq "${plugin}: formatter is silent when the stack does not apply" "no" "$( [ -s "$LOG" ] && echo yes || echo no )"

    rm -f "$LOG"
    printf '%s' "$payload" | PATH="${STUBS}:${PATH}" run_hook "${DEV}/${plugin}" "$PROJ" "$cmd"
    assert_eq "${plugin}: formatter runs from a dev checkout" "yes" "$( [ -s "$LOG" ] && echo yes || echo no )"
done

echo
echo "=== ${pass_count} passed, ${fail_count} failed ==="
[ "$fail_count" -eq 0 ]
