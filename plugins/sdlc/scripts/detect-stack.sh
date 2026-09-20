#!/usr/bin/env bash
# Read-only stack-profile detector. Emits a single JSON object on stdout.
#
# Mirrors pipeline-orchestrator/SKILL.md Step 0b (profile matching) and Step 0b-aspects
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
#
#   --repo          Project directory to evaluate detect rules against. Default ".".
#   --plugins-root  Root to search (recursively) for stack.md files. Default
#                   ~/.claude/plugins/cache — the real installed-plugin location.
#   --write-cache   Also write the result to the session stack-cache file
#                   ({cache-dir}/{sha1(realpath(repo))[:16]}.json) after printing it.
#   --cache-dir     Override the cache directory. Default ~/.claude/.sdlc-stack-cache.
set -uo pipefail

CANONICAL_ASPECTS='["backend","frontend","database","infra","testing","messaging"]'

repo="."
plugins_root="${HOME}/.claude/plugins/cache"
write_cache=false
cache_dir="${HOME}/.claude/.sdlc-stack-cache"

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)         repo="${2:-.}"; shift 2 ;;
        --plugins-root) plugins_root="${2:-}"; shift 2 ;;
        --write-cache)  write_cache=true; shift ;;
        --cache-dir)    cache_dir="${2:-}"; shift 2 ;;
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

# $1 = rule JSON → returns 0 when the rule matches the repo
evaluate_rule() {
    local rule="$1" kind
    kind=$(jq -r 'keys[0]' <<<"$rule")
    case "$kind" in
        literal)
            [ "$(jq -r '.literal' <<<"$rule")" = "*" ] ;;
        file_exists)
            [ -f "${repo}/$(jq -r '.file_exists' <<<"$rule")" ] ;;
        file_contains)
            local path pattern
            path=$(jq -r '.file_contains.path' <<<"$rule")
            pattern=$(ere_pattern "$(jq -r '.file_contains.pattern' <<<"$rule")")
            [ -f "${repo}/${path}" ] && grep -Eq -- "$pattern" "${repo}/${path}" 2>/dev/null ;;
        *) return 1 ;;
    esac
}

# $1 = detect JSON {any|all: [rules]} → returns 0 when the profile matches
evaluate_detect() {
    local detect="$1" kind rule
    kind=$(jq -r 'keys[0]' <<<"$detect")
    local any_hit=false all_hit=true
    while IFS= read -r rule; do
        [ -n "$rule" ] || continue
        if evaluate_rule "$rule"; then any_hit=true; else all_hit=false; fi
    done < <(jq -c ".${kind}[]" <<<"$detect")
    if [ "$kind" = "any" ]; then [ "$any_hit" = true ]; else [ "$all_hit" = true ]; fi
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
                  '. + [{stack: $s, priority: $p, aspects: $a, source: $src, matched: $m}]' <<<"$profiles")
done < <(find "$plugins_root" -name stack.md -type f 2>/dev/null | sort)

result=$(jq -cn \
    --arg detected_at "$detected_at" --arg repo "$repo_abs" --arg root "$plugins_root" \
    --argjson scanned "$scanned" --argjson profiles "$profiles" --argjson errors "$parse_errors" \
    --argjson aspects "$CANONICAL_ASPECTS" '
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
