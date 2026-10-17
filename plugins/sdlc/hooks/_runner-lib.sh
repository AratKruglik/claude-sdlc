#!/usr/bin/env bash
# Shared tool runner for every stack hook: decides whether a language applies to the
# project, where its tool lives (local machine vs. a running Docker Compose service), and
# runs it the right way — or not at all. Sourced by run-tool.sh and post-implement-check.sh,
# never executed. Pure bash + awk so PostToolUse formatters work without jq.
#
# Resolution order, first hit wins (runner_resolve sets RUNNER_MODE / RUNNER_SERVICE /
# RUNNER_REASON; mode is "local", "docker" or "none"):
#   0. applicability — the language's marker file must exist in the project root, else "none".
#   1. explicit override: .claude/sdlc.local.yaml → phase_command_overrides.development.
#      {lang}_runner. A value starting with "docker compose exec" forces the Docker path with
#      that service; any other value forces local. The prefix only picks the mode — the
#      command is always passed through as written in hooks.json.
#   2. local: a project-relative command (./vendor/bin/x, node_modules/.bin/x, ./mvnw) must be
#      an executable file; a bare command must be on PATH; `npx --no-install <pkg>` counts as
#      local when node_modules/.bin/<pkg> exists.
#   3. docker: `docker` on PATH, a compose file in the root, a service that is running and
#      has the command inside. Probing Docker costs ~1s, so this answer is cached for ten
#      minutes under ${CLAUDE_PLUGIN_DATA}/runner-cache/ (fallback $TMPDIR), invalidated when
#      the compose file or sdlc.local.yaml changes. SDLC_RUNNER_NO_CACHE=1 bypasses the cache.
#   4. none — the caller skips silently. A missing tool is a project that does not use it.
#
# Docker probes are wrapped in `timeout 5` when timeout/gtimeout exists so a wedged daemon
# can never outlive the hook's own timeout.

RUNNER_CACHE_TTL_SECONDS=600
RUNNER_SERVICE_CANDIDATES="app php web api backend node frontend python worker"

RUNNER_MODE="none"
RUNNER_SERVICE=""
RUNNER_REASON=""

runner_project_root() {
    if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
        printf '%s' "$CLAUDE_PROJECT_DIR"
    else
        pwd
    fi
}

# $1 = lang, $2 = root
runner_applicable() {
    local lang="$1" root="$2"
    case "$lang" in
        any)    return 0 ;;
        php)    [ -f "$root/composer.json" ] ;;
        node)   [ -f "$root/package.json" ] ;;
        python)
            [ -f "$root/pyproject.toml" ] || [ -f "$root/setup.py" ] || [ -f "$root/setup.cfg" ] \
                || [ -f "$root/Pipfile" ] || ls "$root"/requirements*.txt >/dev/null 2>&1
            ;;
        java)   [ -f "$root/pom.xml" ] || [ -f "$root/build.gradle" ] || [ -f "$root/build.gradle.kts" ] ;;
        dotnet)
            find "$root" -maxdepth 2 \( -name '*.sln' -o -name '*.csproj' \) -print -quit 2>/dev/null | grep -q .
            ;;
        *)      return 1 ;;
    esac
}

# $1 = lang, $2 = root. Prints the configured runner prefix, or nothing.
runner_override() {
    local yaml="$2/.claude/sdlc.local.yaml"
    [ -f "$yaml" ] || return 0
    awk -v key="${1}_runner" '
        function indent(s) { match(s, /^[ \t]*/); return RLENGTH }
        /^[ \t]*#/ || /^[ \t]*$/ { next }
        {
            ind = indent($0)
            line = $0; sub(/^[ \t]+/, "", line)
            if (ind == 0) { top = line; dev = 0; next }
            if (top != "phase_command_overrides:") next
            if (!dev) { if (line ~ /^development:/) { dev = 1; dev_ind = ind }; next }
            if (ind <= dev_ind) { dev = 0; next }
            if (index(line, key ":") == 1) {
                val = substr(line, length(key) + 2)
                sub(/^[ \t]+/, "", val); sub(/[ \t]+#.*$/, "", val); sub(/[ \t]+$/, "", val)
                gsub(/^["'"'"']|["'"'"']$/, "", val)
                print val; exit
            }
        }' "$yaml" 2>/dev/null
}

# $1 = root, $2.. = command. True when the command can run on this machine.
runner_local_available() {
    local root="$1" tok="$2" pkg
    case "$tok" in
        npx)
            if [ "${3:-}" = "--no-install" ] && [ -n "${4:-}" ]; then
                pkg="${4##*/}"
                [ -x "$root/node_modules/.bin/$pkg" ]
            else
                command -v npx >/dev/null 2>&1
            fi
            ;;
        */*)
            [ -x "$root/${tok#./}" ] || { [ "${tok#/}" != "$tok" ] && [ -x "$tok" ]; }
            ;;
        *)
            command -v "$tok" >/dev/null 2>&1
            ;;
    esac
}

# $1 = root. Prints the compose file path, or nothing.
runner_compose_file() {
    local root="$1" f
    for f in compose.yaml compose.yml docker-compose.yaml docker-compose.yml docker-compose.override.yml; do
        [ -f "$root/$f" ] && { printf '%s' "$root/$f"; return 0; }
    done
    return 1
}

# $1 = compose file. Prints the top-level service names, one per line.
runner_compose_services() {
    awk '
        function indent(s) { match(s, /^[ \t]*/); return RLENGTH }
        /^[ \t]*#/ || /^[ \t]*$/ { next }
        indent($0) == 0 { inside = ($0 ~ /^services:[ \t]*$/); child = 0; next }
        inside {
            ind = indent($0)
            if (!child) child = ind
            if (ind == child && $0 ~ /^[ \t]+[A-Za-z0-9_.-]+:[ \t]*$/) {
                name = $0; sub(/^[ \t]+/, "", name); sub(/:.*$/, "", name); print name
            }
        }' "$1" 2>/dev/null
}

# $1 = compose file, $2 = hint. Prints the candidate service, or nothing.
runner_pick_service() {
    local services hint="$2" c
    services=$(runner_compose_services "$1")
    [ -n "$services" ] || return 1
    if [ -n "$hint" ] && printf '%s\n' "$services" | grep -qx "$hint"; then
        printf '%s' "$hint"; return 0
    fi
    for c in $RUNNER_SERVICE_CANDIDATES; do
        printf '%s\n' "$services" | grep -qx "$c" && { printf '%s' "$c"; return 0; }
    done
    printf '%s\n' "$services" | head -n 1
}

runner_timeout_cmd() {
    if command -v timeout >/dev/null 2>&1; then printf 'timeout 5'
    elif command -v gtimeout >/dev/null 2>&1; then printf 'gtimeout 5'
    fi
}

# $1 = root, $2 = service, $3 = first command token. True when the service is running
# and the command exists inside it.
runner_docker_probe() {
    local root="$1" svc="$2" tok="$3" t running
    t=$(runner_timeout_cmd)
    # shellcheck disable=SC2086  # $t is intentionally word-split ("timeout 5" or empty)
    running=$(cd "$root" 2>/dev/null && $t docker compose ps --services --status running 2>/dev/null) || return 1
    printf '%s\n' "$running" | grep -qx "$svc" || return 1
    # shellcheck disable=SC2086
    (cd "$root" 2>/dev/null && $t docker compose exec -T "$svc" sh -c 'command -v "$1" >/dev/null 2>&1 || test -x "$1"' sh "$tok" >/dev/null 2>&1)
}

runner_mtime() {
    [ -e "$1" ] || { printf '0'; return; }
    # GNU first: on GNU stat `-f` means "filesystem status" and succeeds with unrelated output,
    # while BSD stat rejects `-c`, so this order is correct on both.
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || printf '0'
}

runner_hash() {
    if command -v shasum >/dev/null 2>&1; then printf '%s' "$1" | shasum -a 1 | cut -c1-16
    elif command -v sha1sum >/dev/null 2>&1; then printf '%s' "$1" | sha1sum | cut -c1-16
    else printf '%s' "$1" | cksum | cut -d' ' -f1
    fi
}

runner_cache_dir() {
    if [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then printf '%s/runner-cache' "$CLAUDE_PLUGIN_DATA"
    else printf '%s/sdlc-runner-cache-%s' "${TMPDIR:-/tmp}" "${UID:-$(id -u)}"
    fi
}

# $1 = root, $2 = lang, $3 = first token. Prints the cache file path.
runner_cache_file() {
    local real
    real=$(cd "$1" 2>/dev/null && pwd -P) || real="$1"
    printf '%s/%s.txt' "$(runner_cache_dir)" "$(runner_hash "${real}|${2}|${3}")"
}

# $1 = cache file, $2 = compose file, $3 = yaml. Prints "mode service" on a valid hit.
runner_cache_read() {
    local f="$1" mode svc reason cm ym ts now
    [ "${SDLC_RUNNER_NO_CACHE:-0}" = "1" ] && return 1
    [ -f "$f" ] || return 1
    IFS='|' read -r mode svc reason cm ym ts < "$f" || return 1
    now=$(date +%s)
    [ -n "$ts" ] && [ $((now - ts)) -lt "$RUNNER_CACHE_TTL_SECONDS" ] || return 1
    [ "$cm" = "$(runner_mtime "$2")" ] && [ "$ym" = "$(runner_mtime "$3")" ] || return 1
    printf '%s|%s|%s' "$mode" "$svc" "$reason"
}

runner_cache_write() {
    local f="$1" dir
    [ "${SDLC_RUNNER_NO_CACHE:-0}" = "1" ] && return 0
    dir=$(dirname "$f")
    mkdir -p "$dir" 2>/dev/null || return 0
    printf '%s|%s|%s|%s|%s|%s\n' "$2" "$3" "$4" "$(runner_mtime "$5")" "$(runner_mtime "$6")" "$(date +%s)" > "$f" 2>/dev/null || true
}

# $1 = lang, $2 = root, $3 = service hint, $4.. = command.
# Sets RUNNER_MODE, RUNNER_SERVICE, RUNNER_REASON. Returns 0 unless mode is "none".
runner_resolve() {
    local lang="$1" root="$2" hint="$3"; shift 3
    local tok="${1:-}" override compose yaml cache hit svc
    RUNNER_MODE="none"; RUNNER_SERVICE=""; RUNNER_REASON=""
    [ -n "$tok" ] || { RUNNER_REASON="no command"; return 1; }

    if ! runner_applicable "$lang" "$root"; then
        RUNNER_REASON="$lang does not apply to this project"
        return 1
    fi

    yaml="$root/.claude/sdlc.local.yaml"
    compose=$(runner_compose_file "$root") || compose=""

    override=$(runner_override "$lang" "$root")
    if [ -n "$override" ]; then
        case "$override" in
            "docker compose exec"*)
                svc=$(printf '%s' "$override" | awk '{ for (i = 4; i <= NF; i++) if ($i !~ /^-/) { print $i; exit } }')
                if [ -n "$svc" ]; then
                    RUNNER_MODE="docker"; RUNNER_SERVICE="$svc"; RUNNER_REASON="override: ${lang}_runner"
                    return 0
                fi
                ;;
            *)
                RUNNER_MODE="local"; RUNNER_REASON="override: ${lang}_runner"
                return 0
                ;;
        esac
    fi

    if runner_local_available "$root" "$@"; then
        RUNNER_MODE="local"; RUNNER_REASON="found locally"
        return 0
    fi

    if ! command -v docker >/dev/null 2>&1; then
        RUNNER_REASON="$tok not found locally and docker is not installed"
        return 1
    fi
    if [ -z "$compose" ]; then
        RUNNER_REASON="$tok not found locally and no compose file in the project"
        return 1
    fi

    cache=$(runner_cache_file "$root" "$lang" "$tok")
    if hit=$(runner_cache_read "$cache" "$compose" "$yaml"); then
        RUNNER_MODE="${hit%%|*}"; hit="${hit#*|}"
        RUNNER_SERVICE="${hit%%|*}"; RUNNER_REASON="${hit#*|} (cached)"
        [ "$RUNNER_MODE" != "none" ]
        return $?
    fi

    svc=$(runner_pick_service "$compose" "$hint") || svc=""
    if [ -n "$svc" ] && runner_docker_probe "$root" "$svc" "$tok"; then
        RUNNER_MODE="docker"; RUNNER_SERVICE="$svc"; RUNNER_REASON="found in running service $svc"
    else
        RUNNER_REASON="$tok not found locally nor in a running compose service"
    fi
    runner_cache_write "$cache" "$RUNNER_MODE" "$RUNNER_SERVICE" "$RUNNER_REASON" "$compose" "$yaml"
    [ "$RUNNER_MODE" != "none" ]
}

# $1 = root, $2.. = command. Runs through the resolved mode; propagates the exit code.
# In docker mode an argument under the project root is rewritten to a root-relative path: a host
# absolute path usually does not exist inside the container, while the relative form resolves
# against the service's working directory, where the project is mounted.
runner_exec() {
    local root="$1"; shift
    local arg norm prefix args=() prefixes=()
    case "$RUNNER_MODE" in
        local)  (cd "$root" 2>/dev/null && "$@") ;;
        docker)
            prefixes=("${root//\/\///}" "$(cd "$root" 2>/dev/null && pwd -P)")
            for arg in "$@"; do
                norm="${arg//\/\///}"
                for prefix in "${prefixes[@]}"; do
                    [ -n "$prefix" ] || continue
                    case "$norm" in
                        "$prefix"/*) arg="${norm#"$prefix"/}"; break ;;
                    esac
                done
                args+=("$arg")
            done
            (cd "$root" 2>/dev/null && docker compose exec -T "$RUNNER_SERVICE" "${args[@]}") ;;
        *)      return 0 ;;
    esac
}

runner_json_str() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# $1 = lang, $2 = applicable (true|false). Prints the --probe JSON.
runner_probe_json() {
    printf '{"lang":"%s","applicable":%s,"mode":"%s","service":%s,"reason":"%s"}\n' \
        "$(runner_json_str "$1")" "$2" "$RUNNER_MODE" \
        "$([ -n "$RUNNER_SERVICE" ] && printf '"%s"' "$(runner_json_str "$RUNNER_SERVICE")" || printf 'null')" \
        "$(runner_json_str "$RUNNER_REASON")"
}
