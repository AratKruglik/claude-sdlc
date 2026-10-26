#!/usr/bin/env bash
# Read-only stack-profile detector. Emits a single JSON object on stdout.
#
# Mirrors pipeline-orchestrator/references/fallback-steps.md Step 0b (profile matching) and 0b-aspects
# (per-aspect winner resolution) exactly — this script does not introduce new selection
# semantics, it precomputes the same deterministic algorithm so the orchestrator (and the
# SessionStart hook) don't have to spend LLM tool calls Glob-ing and Read-ing every installed
# plugin's stack.md.
#
# Contract: never exits non-zero on a project or plugin set it cannot parse. A malformed
# stack.md is skipped with a note in `parse_errors`, not a crash — this script's output is a
# cache; a cache miss (or a script that produced nothing usable) must degrade to the
# orchestrator's own full scan, never to a pipeline abort. Requires jq; without it the
# script prints a minimal JSON object with `error` set and still exits 0.
#
# Usage:
#   detect-stack.sh [--repo <path>] [--plugins-root <path>] [--write-cache] [--cache-dir <path>]
#                   [--shape-only]
#
#   --repo          Project directory to evaluate detect rules against. Default ".".
#   --plugins-root  Root to search (recursively) for stack.md files. Default
#                   ~/.claude/plugins/cache — the real installed-plugin location.
#   --write-cache   Also write the result to the session stack-cache file
#                   ({cache-dir}/{sha1(realpath(repo))[:16]}.json) after printing it.
#   --cache-dir     Override the cache directory. Default ${CLAUDE_PLUGIN_DATA}/stack-cache when
#                   Claude Code provides the plugin data dir, else ~/.claude/.sdlc-stack-cache.
#   --shape-only    Print only {"project_shape": …} — the read-only project-shape probe
#                   (package manager, test/lint/format/typecheck commands, test framework,
#                   runner prefix, CI, monorepo), skipping the stack.md scan entirely.
#
# `project_shape` is also part of the full output. It answers the questions every phase
# agent used to re-derive per pass (which runner, which test command, which framework)
# from the files on disk only — nothing is executed and nothing is fetched.
set -uo pipefail

CANONICAL_ASPECTS='["backend","frontend","database","infra","testing","messaging"]'

repo="."
plugins_root="${HOME}/.claude/plugins/cache"
write_cache=false
shape_only=false
cache_dir="${CLAUDE_PLUGIN_DATA:+${CLAUDE_PLUGIN_DATA}/stack-cache}"
[ -n "$cache_dir" ] || cache_dir="${HOME}/.claude/.sdlc-stack-cache"

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)         repo="${2:-.}"; shift 2 ;;
        --plugins-root) plugins_root="${2:-}"; shift 2 ;;
        --write-cache)  write_cache=true; shift ;;
        --cache-dir)    cache_dir="${2:-}"; shift 2 ;;
        --shape-only)   shape_only=true; shift ;;
        *)              shift ;;
    esac
done

repo_abs=$(cd "$repo" 2>/dev/null && pwd -P) || repo_abs="$repo"
detected_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

if ! command -v jq >/dev/null 2>&1; then
    printf '{"schema_version":1,"detected_at":"%s","repo":"%s","error":"jq required","primary_profile":null,"active_profiles":{},"aspect_ties":{},"matched_profiles":[],"parse_errors":[]}\n' \
        "$detected_at" "$repo_abs"
    exit 0
fi


# ── project shape ─────────────────────────────────────────────────────────────
# Everything below reads files only. Commands are strings for the agents to run, never
# run here. A null means "could not tell from disk", not "the project has none".

has_file() { [ -f "${repo}/$1" ]; }
json_has_key() {
    # $1 = json file (relative), $2 = jq path expression
    [ -f "${repo}/$1" ] && jq -e "$2" "${repo}/$1" >/dev/null 2>&1
}
json_str_at() {
    [ -f "${repo}/$1" ] && jq -r "$2 // empty" "${repo}/$1" 2>/dev/null
}
glob_exists() {
    # $1 = glob relative to repo root (single level)
    local m
    for m in "${repo}"/$1; do [ -e "$m" ] && return 0; done
    return 1
}

shape_package_manager() {
    if has_file pnpm-lock.yaml; then echo pnpm
    elif has_file yarn.lock; then echo yarn
    elif has_file bun.lockb || has_file bun.lock; then echo bun
    elif has_file package-lock.json || has_file package.json; then echo npm
    elif has_file composer.json; then echo composer
    elif has_file uv.lock; then echo uv
    elif has_file poetry.lock || json_toml_has poetry; then echo poetry
    elif has_file Pipfile; then echo pipenv
    elif has_file pyproject.toml || has_file requirements.txt || has_file setup.py; then echo pip
    elif has_file pom.xml; then echo maven
    elif has_file build.gradle || has_file build.gradle.kts; then echo gradle
    elif glob_exists '*.sln' || glob_exists '*.csproj'; then echo dotnet
    fi
}

json_toml_has() { has_file pyproject.toml && grep -Eq "^\[tool\.$1" "${repo}/pyproject.toml" 2>/dev/null; }
toml_dep() { has_file pyproject.toml && grep -Eiq "[\"']?$1[\"'>=<~ ]" "${repo}/pyproject.toml" 2>/dev/null; }

shape_runner_prefix() {
    local f svc
    for f in docker-compose.yml docker-compose.yaml compose.yml compose.yaml; do
        has_file "$f" || continue
        for svc in app php web api backend; do
            if grep -Eq "^  ${svc}:[[:space:]]*$" "${repo}/$f" 2>/dev/null; then
                echo "docker compose exec -T ${svc}"; return 0
            fi
        done
    done
    echo ""
}

# $1 = package manager → how to invoke a package.json script
js_run() {
    case "$1" in
        pnpm) echo "pnpm run $2" ;;
        yarn) echo "yarn $2" ;;
        bun)  echo "bun run $2" ;;
        *)    echo "npm run $2" ;;
    esac
}

# $1 = script name → the pnpm/yarn/npm invocation when package.json declares it
js_script() {
    local pm="$1" name="$2"
    json_has_key package.json ".scripts[\"$name\"]" && js_run "$pm" "$name"
}

js_dev_dep() { json_has_key package.json ".devDependencies[\"$1\"] // .dependencies[\"$1\"]"; }
php_dev_dep() { json_has_key composer.json ".[\"require-dev\"][\"$1\"] // .require[\"$1\"]"; }

shape_test_framework() {
    local pm="$1"
    case "$pm" in
        npm|pnpm|yarn|bun)
            if js_dev_dep vitest || glob_exists 'vitest.config.*'; then echo vitest
            elif js_dev_dep jest || glob_exists 'jest.config.*' || json_has_key package.json '.jest'; then echo jest
            elif js_dev_dep mocha; then echo mocha
            fi ;;
        composer)
            if php_dev_dep pestphp/pest; then echo pest
            elif php_dev_dep phpunit/phpunit || has_file phpunit.xml || has_file phpunit.xml.dist; then echo phpunit
            fi ;;
        pip|poetry|uv|pipenv)
            if has_file pytest.ini || json_toml_has pytest || toml_dep pytest || grep -qs pytest "${repo}/requirements-dev.txt" "${repo}/requirements.txt" 2>/dev/null; then echo pytest
            elif glob_exists 'manage.py'; then echo unittest
            fi ;;
        maven|gradle) echo junit ;;
        dotnet)
            if grep -rqs --include='*.csproj' 'xunit' "${repo}" 2>/dev/null; then echo xunit
            elif grep -rqs --include='*.csproj' 'NUnit' "${repo}" 2>/dev/null; then echo nunit
            elif grep -rqs --include='*.csproj' 'MSTest' "${repo}" 2>/dev/null; then echo mstest
            fi ;;
    esac
}

shape_test_command() {
    local pm="$1" fw="$2" cmd
    case "$pm" in
        npm|pnpm|yarn|bun)
            cmd=$(js_script "$pm" test) && { echo "$cmd"; return; }
            case "$fw" in vitest) echo "npx vitest run" ;; jest) echo "npx jest" ;; esac ;;
        composer)
            if has_file artisan; then echo "php artisan test"
            elif cmd=$(json_str_at composer.json '.scripts.test | if type=="array" then .[0] else . end') && [ -n "$cmd" ]; then echo "composer test"
            elif [ "$fw" = pest ]; then echo "./vendor/bin/pest"
            elif [ "$fw" = phpunit ]; then echo "./vendor/bin/phpunit"
            fi ;;
        pip|poetry|uv|pipenv)
            case "$fw" in
                pytest) case "$pm" in poetry) echo "poetry run pytest" ;; uv) echo "uv run pytest" ;; pipenv) echo "pipenv run pytest" ;; *) echo "pytest" ;; esac ;;
                unittest) echo "python manage.py test" ;;
            esac ;;
        maven)  if has_file mvnw; then echo "./mvnw test"; else echo "mvn test"; fi ;;
        gradle) if has_file gradlew; then echo "./gradlew test"; else echo "gradle test"; fi ;;
        dotnet) echo "dotnet test" ;;
    esac
}

shape_lint_command() {
    local pm="$1" cmd
    case "$pm" in
        npm|pnpm|yarn|bun)
            cmd=$(js_script "$pm" lint) && { echo "$cmd"; return; }
            if js_dev_dep eslint || glob_exists 'eslint.config.*' || glob_exists '.eslintrc*'; then echo "npx eslint ."
            elif js_dev_dep '@biomejs/biome' || glob_exists 'biome.json*'; then echo "npx biome lint ."
            fi ;;
        composer)
            if has_file phpstan.neon || has_file phpstan.neon.dist; then echo "./vendor/bin/phpstan analyse --no-progress"
            elif php_dev_dep laravel/pint; then echo "./vendor/bin/pint --test"
            fi ;;
        pip|poetry|uv|pipenv)
            if has_file ruff.toml || has_file .ruff.toml || json_toml_has ruff; then echo "ruff check ."
            elif has_file .flake8 || has_file setup.cfg && grep -q '^\[flake8\]' "${repo}/setup.cfg" 2>/dev/null; then echo "flake8"
            fi ;;
        maven)  grep -q spotless "${repo}/pom.xml" 2>/dev/null && { if has_file mvnw; then echo "./mvnw -q spotless:check"; else echo "mvn -q spotless:check"; fi; } ;;
        gradle) grep -qs spotless "${repo}/build.gradle" "${repo}/build.gradle.kts" 2>/dev/null && { if has_file gradlew; then echo "./gradlew spotlessCheck"; else echo "gradle spotlessCheck"; fi; } ;;
        dotnet) echo "dotnet format --verify-no-changes" ;;
    esac
}

shape_format_command() {
    local pm="$1" cmd
    case "$pm" in
        npm|pnpm|yarn|bun)
            cmd=$(js_script "$pm" format) && { echo "$cmd"; return; }
            if js_dev_dep prettier || glob_exists '.prettierrc*'; then echo "npx prettier --write ."
            elif js_dev_dep '@biomejs/biome'; then echo "npx biome format --write ."
            fi ;;
        composer)
            if php_dev_dep laravel/pint; then echo "./vendor/bin/pint"
            elif php_dev_dep friendsofphp/php-cs-fixer; then echo "./vendor/bin/php-cs-fixer fix"
            fi ;;
        pip|poetry|uv|pipenv)
            if has_file ruff.toml || has_file .ruff.toml || json_toml_has ruff; then echo "ruff format ."
            elif json_toml_has black || toml_dep black; then echo "black ."
            fi ;;
        maven)  grep -q spotless "${repo}/pom.xml" 2>/dev/null && { if has_file mvnw; then echo "./mvnw -q spotless:apply"; else echo "mvn -q spotless:apply"; fi; } ;;
        gradle) grep -qs spotless "${repo}/build.gradle" "${repo}/build.gradle.kts" 2>/dev/null && { if has_file gradlew; then echo "./gradlew spotlessApply"; else echo "gradle spotlessApply"; fi; } ;;
        dotnet) echo "dotnet format" ;;
    esac
}

shape_typecheck_command() {
    local pm="$1" cmd
    case "$pm" in
        npm|pnpm|yarn|bun)
            cmd=$(js_script "$pm" typecheck) && { echo "$cmd"; return; }
            has_file tsconfig.json && echo "npx tsc --noEmit" ;;
        composer)
            if has_file phpstan.neon || has_file phpstan.neon.dist; then echo "./vendor/bin/phpstan analyse --no-progress"
            elif has_file psalm.xml; then echo "./vendor/bin/psalm"
            fi ;;
        pip|poetry|uv|pipenv)
            if has_file mypy.ini || json_toml_has mypy; then echo "mypy ."
            elif json_toml_has pyright || has_file pyrightconfig.json; then echo "pyright"
            fi ;;
    esac
}

shape_coverage_available() {
    local pm="$1" fw="$2"
    case "$fw" in
        vitest) js_dev_dep '@vitest/coverage-v8' || js_dev_dep '@vitest/coverage-istanbul' ;;
        jest) return 0 ;;
        pest|phpunit) return 0 ;;
        pytest) toml_dep pytest-cov || grep -qs pytest-cov "${repo}/requirements-dev.txt" "${repo}/requirements.txt" 2>/dev/null ;;
        junit) grep -qs jacoco "${repo}/pom.xml" "${repo}/build.gradle" "${repo}/build.gradle.kts" 2>/dev/null ;;
        xunit|nunit|mstest) grep -rqs --include='*.csproj' coverlet "${repo}" 2>/dev/null ;;
        *) return 1 ;;
    esac
}

shape_ci() {
    if [ -d "${repo}/.github/workflows" ] && glob_exists '.github/workflows/*.y*ml'; then echo github-actions
    elif has_file .gitlab-ci.yml; then echo gitlab-ci
    else echo none
    fi
}

shape_monorepo() {
    json_has_key package.json '.workspaces' || has_file pnpm-workspace.yaml || has_file nx.json || has_file turbo.json
}

project_shape() {
    local pm fw test lint fmt tc cov ci mono
    pm=$(shape_package_manager)
    fw=$(shape_test_framework "$pm")
    test=$(shape_test_command "$pm" "$fw")
    lint=$(shape_lint_command "$pm")
    fmt=$(shape_format_command "$pm")
    tc=$(shape_typecheck_command "$pm")
    cov=false; shape_coverage_available "$pm" "$fw" && cov=true
    ci=$(shape_ci)
    mono=false; shape_monorepo && mono=true
    jq -cn --arg pm "$pm" --arg rp "$(shape_runner_prefix)" --arg fw "$fw" --arg test "$test" \
        --arg lint "$lint" --arg fmt "$fmt" --arg tc "$tc" --argjson cov "$cov" --arg ci "$ci" --argjson mono "$mono" '
        def nz: if . == "" then null else . end;
        {package_manager: ($pm | nz), runner_prefix: $rp, test_command: ($test | nz),
         lint_command: ($lint | nz), format_command: ($fmt | nz), typecheck_command: ($tc | nz),
         test_framework: ($fw | nz), coverage_available: $cov, ci: $ci, monorepo: $mono}'
}

shape_json=$(project_shape)

if [ "$shape_only" = true ]; then
    jq -cn --argjson s "$shape_json" '{project_shape: $s}'
    exit 0
fi

profiles='[]'
parse_errors='[]'
scanned=0

add_error() {
    parse_errors=$(jq -c --arg s "$1" --arg r "$2" '. + [{source: $s, reason: $r}]' <<<"$parse_errors")
}

# Python's `re` shorthand classes are not POSIX ERE; translate the ones stack.md patterns use.
ere_pattern() {
    printf '%s' "$1" | sed -e 's/\\s/[[:space:]]/g' -e 's/\\d/[0-9]/g' -e 's/\\w/[[:alnum:]_]/g'
}

trim() {
    local v="$1"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    printf '%s' "$v"
}

strip_quotes() {
    local v
    v=$(trim "$1")
    v="${v#\"}"; v="${v%\"}"; v="${v#\'}"; v="${v%\'}"
    printf '%s' "$v"
}

# $1 = comma-separated list body → JSON array of trimmed, unquoted, non-empty strings
csv_to_json() {
    local out='[]' item
    IFS=',' read -r -a parts <<<"$1"
    for item in "${parts[@]:-}"; do
        item=$(strip_quotes "$item")
        [ -n "$item" ] || continue
        out=$(jq -c --arg i "$item" '. + [$i]' <<<"$out")
    done
    printf '%s' "$out"
}

# $1 = frontmatter text → prints the indented body of the `detect:` block, returns 1 if absent
detect_block() {
    printf '%s\n' "$1" | awk '
        /^detect:[[:space:]]*$/ { inb = 1; found = 1; next }
        inb && /^[[:space:]]/  { print; next }
        inb                    { exit }
        END                    { if (!found) exit 1 }'
}

# Parses one detect block into a JSON object {any|all: [rules]} on stdout, or prints a
# reason on stderr and returns 1.
parse_detect() {
    local block="$1" kind="" inline="" rules='[]' line item in_item=""
    inline=$(printf '%s\n' "$block" | sed -nE 's/^[[:space:]]*(any|all):[[:space:]]*\[(.*)\][[:space:]]*$/\1|\2/p' | head -1)
    if [ -n "$inline" ]; then
        kind="${inline%%|*}"
        local items_json
        items_json=$(csv_to_json "${inline#*|}")
        jq -cn --arg k "$kind" --argjson items "$items_json" '{($k): ($items | map({literal: .}))}'
        return 0
    fi
    kind=$(printf '%s\n' "$block" | sed -nE 's/^[[:space:]]*(any|all):[[:space:]]*$/\1/p' | head -1)
    if [ -z "$kind" ]; then
        echo "detect block has neither inline nor list form" >&2
        return 1
    fi
    local items=()
    while IFS= read -r line; do
        [ -n "$(trim "$line")" ] || continue
        case "$line" in
            *"${kind}:"*) [ -z "$in_item" ] && continue ;;
        esac
        if printf '%s' "$line" | grep -Eq '^[[:space:]]*-[[:space:]]'; then
            [ -n "$in_item" ] && items+=("$in_item")
            in_item=$(printf '%s' "$line" | sed -E 's/^[[:space:]]*-[[:space:]]*//')
        elif [ -n "$in_item" ]; then
            in_item="${in_item}"$'\n'"${line}"
        fi
    done <<<"$block"
    [ -n "$in_item" ] && items+=("$in_item")
    if [ ${#items[@]} -eq 0 ]; then
        echo "detect block has neither inline nor list form" >&2
        return 1
    fi
    for item in "${items[@]}"; do
        local first path pattern rule
        first=$(printf '%s\n' "$item" | head -1)
        if printf '%s' "$first" | grep -Eq '^file_exists:[[:space:]]*[^[:space:]]+[[:space:]]*$'; then
            path=$(trim "${first#file_exists:}")
            rule=$(jq -cn --arg p "$path" '{file_exists: $p}')
        else
            path=$(printf '%s\n' "$item" | sed -nE 's/^[[:space:]]*path:[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p' | head -1)
            pattern=$(printf '%s\n' "$item" | sed -nE "s/^[[:space:]]*pattern:[[:space:]]*'(.*)'[[:space:]]*\$/\1/p" | head -1)
            [ -n "$pattern" ] || pattern=$(printf '%s\n' "$item" | sed -nE 's/^[[:space:]]*pattern:[[:space:]]*"(.*)"[[:space:]]*$/\1/p' | head -1)
            if [ -z "$path" ] || [ -z "$pattern" ]; then
                local inline_fc
                inline_fc=$(printf '%s' "$first" | sed -nE "s/^file_contains:[[:space:]]*\{[[:space:]]*path:[[:space:]]*([^,[:space:]]+)[[:space:]]*,[[:space:]]*pattern:[[:space:]]*['\"](.*)['\"][[:space:]]*\}[[:space:]]*\$/\1|\2/p")
                if [ -n "$inline_fc" ]; then
                    path="${inline_fc%%|*}"; pattern="${inline_fc#*|}"
                fi
            fi
            if [ -z "$path" ] || [ -z "$pattern" ]; then
                echo "unrecognized detect rule: $(trim "$item" | tr '\n' ' ' | cut -c1-60)" >&2
                return 1
            fi
            rule=$(jq -cn --arg p "$path" --arg re "$pattern" '{file_contains: {path: $p, pattern: $re}}')
        fi
        rules=$(jq -c --argjson r "$rule" '. + [$r]' <<<"$rules")
    done
    jq -cn --arg k "$kind" --argjson rules "$rules" '{($k): $rules}'
}

# Human-readable gist of a detect regex for list-stacks: drops escapes, character classes,
# anchors, quantifiers and quotes, leaving the literal the rule looks for.
pattern_gist() {
    printf '%s' "$1" | sed -E 's/\([^)]*\)\?//g; s/\[(.)[^]]*\]/\1/g' | awk '{
        gsub(/\\[a-zA-Z][*+?]?/, "")
        gsub(/[\\()^$|?+*"\047]/, ""); gsub(/^[ :]+|[ :]+$/, "")
        print
    }'
}

# $1 = rule JSON → returns 0 when the rule matches the repo. Also sets RULE_DESC (what the
# rule looks for) and RULE_FAIL (why it did not match, empty on success) for list-stacks.
evaluate_rule() {
    local rule="$1" kind
    kind=$(jq -r 'keys[0]' <<<"$rule")
    RULE_DESC=""; RULE_FAIL=""
    case "$kind" in
        literal)
            if [ "$(jq -r '.literal' <<<"$rule")" = "*" ]; then RULE_DESC="always matches"; return 0; fi
            RULE_DESC="literal $(jq -r '.literal' <<<"$rule")"; RULE_FAIL="unsupported literal rule"; return 1 ;;
        file_exists)
            local path
            path=$(jq -r '.file_exists' <<<"$rule")
            RULE_DESC="$path"
            [ -f "${repo}/${path}" ] && return 0
            RULE_FAIL="${path} not present"; return 1 ;;
        file_contains)
            local path pattern raw
            path=$(jq -r '.file_contains.path' <<<"$rule")
            raw=$(jq -r '.file_contains.pattern' <<<"$rule")
            pattern=$(ere_pattern "$raw")
            RULE_DESC=$(pattern_gist "$raw")
            [ -f "${repo}/${path}" ] || { RULE_FAIL="${path} not present"; return 1; }
            grep -Eq -- "$pattern" "${repo}/${path}" 2>/dev/null && return 0
            RULE_FAIL="${path} lacks ${RULE_DESC}"; return 1 ;;
        *) RULE_FAIL="unknown rule $kind"; return 1 ;;
    esac
}

# $1 = detect JSON {any|all: [rules]} → returns 0 when the profile matches. Sets
# DETECT_SUMMARY (rule descriptions joined by " + " / " | ") and UNMATCHED_REASON (first
# failing rule for `all`, "none of: …" for `any`; empty when matched).
evaluate_detect() {
    local detect="$1" kind rule joiner
    kind=$(jq -r 'keys[0]' <<<"$detect")
    local any_hit=false all_hit=true descs="" first_fail=""
    joiner=" + "; [ "$kind" = "any" ] && joiner=" | "
    while IFS= read -r rule; do
        [ -n "$rule" ] || continue
        if evaluate_rule "$rule"; then any_hit=true; else all_hit=false; [ -n "$first_fail" ] || first_fail="$RULE_FAIL"; fi
        descs="${descs:+${descs}${joiner}}${RULE_DESC}"
    done < <(jq -c ".${kind}[]" <<<"$detect")
    DETECT_SUMMARY="$descs"; UNMATCHED_REASON=""
    if [ "$kind" = "any" ]; then
        [ "$any_hit" = true ] && return 0
        UNMATCHED_REASON="none of: ${descs}"; return 1
    fi
    [ "$all_hit" = true ] && return 0
    UNMATCHED_REASON="$first_fail"; return 1
}

seen_signatures=""

while IFS= read -r file; do
    [ -n "$file" ] || continue
    scanned=$((scanned + 1))
    source="$file"
    case "$file" in
        "${plugins_root}"/*) source="${file#"${plugins_root}"/}" ;;
    esac
    if ! text=$(cat "$file" 2>/dev/null); then
        add_error "$source" "read error"
        continue
    fi
    fm=$(printf '%s\n' "$text" | awk '
        NR == 1     { if ($0 != "---") { bad = 1; exit } next }
        /^---$/     { found = 1; exit }
                    { print }
        END         { if (bad || !found) exit 1 }') || { add_error "$source" "no frontmatter block"; continue; }

    stack=$(printf '%s\n' "$fm" | sed -nE 's/^stack:[[:space:]]*([^[:space:]]+)[[:space:]]*$/\1/p' | head -1)
    [ -n "$stack" ] || { add_error "$source" "missing 'stack' key"; continue; }

    priority=$(printf '%s\n' "$fm" | sed -nE 's/^priority:[[:space:]]*(-?[0-9]+)[[:space:]]*$/\1/p' | head -1)
    [ -n "$priority" ] || priority=0

    aspects_body=$(printf '%s\n' "$fm" | sed -nE 's/^aspects:[[:space:]]*\[(.*)\][[:space:]]*$/\1/p' | head -1)
    aspects=$(csv_to_json "$aspects_body")

    block=$(detect_block "$fm") || { add_error "$source" "missing 'detect' block"; continue; }
    if ! detect=$(parse_detect "$block" 2>/tmp/sdlc-detect-err.$$); then
        add_error "$source" "$(cat /tmp/sdlc-detect-err.$$ 2>/dev/null)"
        rm -f /tmp/sdlc-detect-err.$$
        continue
    fi
    rm -f /tmp/sdlc-detect-err.$$

    # De-dupe an identical profile declared twice (a dev checkout's stack.md alongside an
    # installed copy of the same plugin) rather than letting it manufacture a spurious
    # aspect tie against itself.
    signature="${stack}|${priority}|${aspects}"
    case "$seen_signatures" in
        *"<${signature}>"*) continue ;;
    esac
    seen_signatures="${seen_signatures}<${signature}>"

    matched=false
    evaluate_detect "$detect" && matched=true

    profiles=$(jq -c --arg s "$stack" --argjson p "$priority" --argjson a "$aspects" \
                  --arg src "$source" --argjson m "$matched" \
                  --arg ds "$DETECT_SUMMARY" --arg ur "$UNMATCHED_REASON" \
                  '. + [{stack: $s, priority: $p, aspects: $a, source: $src, matched: $m,
                         detect_summary: $ds, unmatched_reason: (if $ur == "" then null else $ur end)}]' <<<"$profiles")
done < <(find "$plugins_root" -name stack.md -type f 2>/dev/null | sort)

result=$(jq -cn \
    --arg detected_at "$detected_at" --arg repo "$repo_abs" --arg root "$plugins_root" \
    --argjson scanned "$scanned" --argjson profiles "$profiles" --argjson errors "$parse_errors" \
    --argjson aspects "$CANONICAL_ASPECTS" --argjson shape "$shape_json" '
    def summary: {stack, priority, source};
    ($profiles | map(select(.matched))) as $m
    | (if ($m | length) == 0 then null
       else ($m | map(.priority) | max) as $top
            | ($m | map(select(.priority == $top)) | sort_by(.stack) | .[0] | summary) end) as $primary
    | (reduce $aspects[] as $a ({active: {}, ties: {}};
        ($m | map(select(.aspects | index($a)))) as $c
        | if ($c | length) == 0 then .active[$a] = null
          else ($c | map(.priority) | max) as $top
               | ($c | map(select(.priority == $top))) as $w
               | if ($w | length) > 1
                 then .ties[$a] = ($w | map(.stack) | sort) | .active[$a] = null
                 else .active[$a] = ($w[0] | summary) end
          end)) as $r
    | {
        schema_version: 1,
        detected_at: $detected_at,
        repo: $repo,
        plugins_root: $root,
        stack_md_scanned: $scanned,
        primary_profile: $primary,
        active_profiles: $r.active,
        aspect_ties: $r.ties,
        matched_profiles: ($m | map({stack, priority, aspects, source})),
        all_profiles: ($profiles | map({stack, priority, aspects, source, matched, detect_summary, unmatched_reason})),
        project_shape: $shape,
        parse_errors: $errors
      }')

printf '%s\n' "$result"

if [ "$write_cache" = true ] && [ -n "$cache_dir" ]; then
    if command -v shasum >/dev/null 2>&1; then
        digest=$(printf '%s' "$repo_abs" | shasum -a 1 | cut -c1-16)
    elif command -v sha1sum >/dev/null 2>&1; then
        digest=$(printf '%s' "$repo_abs" | sha1sum | cut -c1-16)
    else
        digest=""
    fi
    # Cache is a pure optimization — a write failure (permissions, read-only home, disk
    # full) must never surface as an error.
    if [ -n "$digest" ]; then
        mkdir -p "$cache_dir" 2>/dev/null && printf '%s\n' "$result" > "${cache_dir}/${digest}.json" 2>/dev/null
    fi
fi
exit 0
