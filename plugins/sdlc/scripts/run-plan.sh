#!/usr/bin/env bash
# Read-only run planner for /sdlc:start. Emits a single JSON object on stdout.
#
# Precomputes everything pipeline-orchestrator/SKILL.md decides deterministically before
# the first agent is dispatched: Step 0a (dependency preflight), Step 0b (stack profiles),
# Step 0b-git (GIT-FLOW.md Steps A–E, F-2a and F-4 — observations and proposals only; the
# gate itself, `git checkout -b` and every other mutation stay with the orchestrator),
# Step 0c (diff signals and skip-rules), the Step 1b subset of .claude/sdlc.local.yaml the
# planner can read, Step 1c (RESOLVER.md Steps 1–5) and the Step 2 task slug. The
# orchestrator reads this object instead of re-deriving each decision with Glob/Read/Bash.
#
# What it deliberately leaves to the model: whether a documented-convention hit is a
# "statement" (GIT-FLOW Step B), phase_prompts_injection text, and any sdlc.local.yaml key
# outside the subset listed under `local_config`.
#
# Contract: never exits non-zero, never writes anything except the caches the reused
# detectors already own (stack-cache, deps-preflight). Every problem lands in `warnings[]`
# or `halts[]` (a halt is a condition the orchestrator must stop on, with the exact text
# SKILL.md / RESOLVER.md prescribe). Requires jq; without it prints a minimal object with
# `error` set and still exits 0.
#
# Usage:
#   run-plan.sh --repo <path> --arguments "<$ARGUMENTS>" [--plugins-root <path>]
#               [--dev-root <path>] [--headless] [--stack-cache-dir <path>]
#               [--deps-cache-dir <path>] [--workflows-dir <path>]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
PATTERNS_FILE="${PLUGIN_ROOT}/references/task-type-patterns.json"
MARKER_MAX_AGE_SECONDS=21600
GIT_FLOW_CACHE_MAX_AGE_SECONDS=$((30 * 24 * 3600))

repo="."
arguments=""
plugins_root="${HOME}/.claude/plugins/cache"
dev_root=""
headless=false
stack_cache_dir=""
deps_cache_dir=""
workflows_dir="${PLUGIN_ROOT}/workflows"

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)            repo="${2:-.}"; shift 2 ;;
        --arguments)       arguments="${2:-}"; shift 2 ;;
        --plugins-root)    plugins_root="${2:-}"; shift 2 ;;
        --dev-root)        dev_root="${2:-}"; shift 2 ;;
        --headless)        headless=true; shift ;;
        --stack-cache-dir) stack_cache_dir="${2:-}"; shift 2 ;;
        --deps-cache-dir)  deps_cache_dir="${2:-}"; shift 2 ;;
        --workflows-dir)   workflows_dir="${2:-}"; shift 2 ;;
        *)                 shift ;;
    esac
done

generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
now_epoch=$(date -u +%s)

if ! command -v jq >/dev/null 2>&1; then
    printf '{"schema_version":1,"generated_at":"%s","error":"jq required","warnings":[],"halts":[]}\n' "$generated_at"
    exit 0
fi

repo_abs=$(cd "$repo" 2>/dev/null && pwd -P) || repo_abs="$repo"
[ -n "$dev_root" ] && dev_root=$(cd "$dev_root" 2>/dev/null && pwd -P) || dev_root=""
plugins_root=$(cd "$plugins_root" 2>/dev/null && pwd -P) || plugins_root="$plugins_root"
if [ ! -d "$repo_abs" ]; then
    jq -cn --arg g "$generated_at" --arg r "$repo" '{schema_version:1, generated_at:$g, error:"repo not accessible", repo:$r, warnings:[], halts:[]}'
    exit 0
fi

warnings='[]'
halts='[]'
warn() { warnings=$(jq -c --arg w "$1" '. + [$w]' <<<"$warnings"); }
halt() { halts=$(jq -c --arg h "$1" '. + [$h]' <<<"$halts"); }

iso_to_epoch() {
    local ts="$1" bsd
    bsd=$(printf '%s' "$ts" | sed -E 's/\.[0-9]+//; s/Z$/+0000/; s/([+-][0-9]{2}):([0-9]{2})$/\1\2/')
    date -u -d "$ts" +%s 2>/dev/null \
        || date -u -j -f "%Y-%m-%dT%H:%M:%S%z" "$bsd" +%s 2>/dev/null \
        || echo ""
}

json_file() {
    [ -f "$1" ] && jq -c . "$1" 2>/dev/null
}

# Minimal YAML → JSON for the flat shapes this plugin ships (stack.md blocks, workflow
# recipes, sdlc.local.yaml). Scalars, nested maps, lists of scalars/maps, inline {a: b}
# maps and [a, b] lists. Comments and code fences are dropped. Anything else is a string.
yaml_to_json() {
    awk '
    function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
    function unquote(s) {
        s = trim(s)
        if (s ~ /^".*"$/ || s ~ /^\x27.*\x27$/) s = substr(s, 2, length(s) - 2)
        return s
    }
    function jstr(s) { gsub(/\\/, "\\\\", s); gsub(/"/, "\\\"", s); gsub(/\t/, "\\t", s); return "\"" s "\"" }
    function emit(path, value) { printf "%s\t%s\n", path, value }
    function child(path, key) { return path "," jstr(key) }
    function emit_value(path, raw,    v, n, parts, i, kv, k) {
        v = trim(raw)
        if (v ~ /^\{.*\}$/) {
            v = substr(v, 2, length(v) - 2)
            n = split(v, parts, ",")
            for (i = 1; i <= n; i++) {
                kv = parts[i]
                if (index(kv, ":") == 0) continue
                k = trim(substr(kv, 1, index(kv, ":") - 1))
                emit(child(path, k), unquote(substr(kv, index(kv, ":") + 1)))
            }
            return
        }
        if (v ~ /^\[.*\]$/) {
            v = substr(v, 2, length(v) - 2)
            if (trim(v) == "") { emit(path, "\x01[]"); return }
            n = split(v, parts, ",")
            for (i = 1; i <= n; i++) emit(path "," (i - 1), unquote(parts[i]))
            return
        }
        emit(path, unquote(v))
    }
    BEGIN { depth = 0; inds[0] = -1; paths[0] = "" }
    {
        line = $0
        sub(/\r$/, "", line)
        if (line ~ /^[ \t]*#/ || line ~ /^[ \t]*$/ || line ~ /^[ \t]*```/) next
        if (line ~ /^[ \t]*>/) next
        if (line !~ /^[ \t]*-?[ \t]*[A-Za-z_][A-Za-z0-9_.-]*:/ && line !~ /^[ \t]*-[ \t]/) next
        if (line ~ /[ \t]#/) sub(/[ \t]+#.*$/, "", line)
        match(line, /^ */); ind = RLENGTH
        rest = substr(line, ind + 1)
        while (depth > 0 && inds[depth] >= ind) depth--
        base = paths[depth]
        if (rest ~ /^- / || rest == "-") {
            rest = (rest == "-") ? "" : substr(rest, 3)
            count[base]++
            item = base "," (count[base] - 1)
            if (rest == "") { depth++; inds[depth] = ind + 1; paths[depth] = item; next }
            if (rest ~ /^[A-Za-z_][A-Za-z0-9_.-]*:([ \t]|$)/) {
                depth++; inds[depth] = ind + 1; paths[depth] = item
                ind += 2; base = item
            } else { emit(item, unquote(rest)); next }
        }
        if (rest ~ /^[A-Za-z_][A-Za-z0-9_.-]*:([ \t]|$)/) {
            key = substr(rest, 1, index(rest, ":") - 1)
            value = substr(rest, index(rest, ":") + 1)
            if (trim(value) == "" || trim(value) == "|" || trim(value) == ">") {
                depth++; inds[depth] = ind; paths[depth] = child(base, key)
                if (trim(value) != "") blockscalar = 1
                next
            }
            emit_value(child(base, key), value)
        }
    }' | jq -Rs '
        def conv: if . == "true" then true elif . == "false" then false
                  elif test("^-?[0-9]+(\\.[0-9]+)?$") then tonumber else . end;
        split("\n") | map(select(length > 0) | split("\t"))
        | reduce .[] as [$p, $v] (null;
            ($p | split(",") | map(select(length > 0) | if test("^[0-9]+$") then tonumber else fromjson end)) as $path
            | if $v == "\u0001[]" then setpath($path; []) else setpath($path; ($v | conv)) end)
        | if . == null then {} else . end'
}

# $1 = markdown file, $2 = "## Heading" → the section body up to the next "## " line.
md_section() {
    awk -v h="$2" 'index($0, h) == 1 { p = 1; next } p && /^## / { exit } p' "$1" 2>/dev/null
}

# ---------------------------------------------------------------------------
# $ARGUMENTS → flags + cleaned description
# ---------------------------------------------------------------------------

flag_value() {
    printf '%s' "$arguments" | grep -oE -- "--$1=[^[:space:]]+" | head -1 | sed -E "s/^--$1=//"
}
has_flag() {
    printf '%s' "$arguments" | grep -qE -- "(^|[[:space:]])--$1([[:space:]]|$)"
}

forced_stack=$(flag_value stack)
forced_type=$(flag_value type)
forced_workflow=$(flag_value workflow)
redetect_git_flow=false; has_flag redetect-git-flow && redetect_git_flow=true
redetect_stack=false;    has_flag redetect-stack && redetect_stack=true
force_preflight=false;   has_flag force-preflight && force_preflight=true
resume=false;            has_flag resume && resume=true

description=$(printf '%s' "$arguments" \
    | sed -E 's/(^|[[:space:]])--(stack|type|workflow)=[^[:space:]]+/ /g; s/(^|[[:space:]])--(redetect-git-flow|redetect-stack|force-preflight|resume)(=[^[:space:]]*)?(([[:space:]])|$)/ /g; s/(^|[[:space:]])--(redetect-git-flow|redetect-stack|force-preflight|resume)(([[:space:]])|$)/ /g' \
    | tr -s '[:space:]' ' ' | sed -E 's/^ +//; s/ +$//')

flags_json=$(jq -cn --arg s "$forced_stack" --arg t "$forced_type" --arg w "$forced_workflow" \
    --argjson rg "$redetect_git_flow" --argjson rs "$redetect_stack" --argjson fp "$force_preflight" --argjson r "$resume" '
    {stack: (if $s == "" then null else $s end), type: (if $t == "" then null else $t end),
     workflow: (if $w == "" then null else $w end), redetect_git_flow: $rg, redetect_stack: $rs,
     force_preflight: $fp, resume: $r}')

narrative_language=$(jq -rn --arg d "$description" '
    ($d | [scan("\\p{Cyrillic}")] | length) as $c | ($d | [scan("\\p{Latin}")] | length) as $l
    | if $c > $l then "uk" else "en" end')

transliterate() {
    sed -e 's/[Аа]/a/g; s/[Бб]/b/g; s/[Вв]/v/g; s/[Гг]/h/g; s/[Ґґ]/g/g; s/[Дд]/d/g; s/[Ее]/e/g; s/[Єє]/ie/g' \
        -e 's/[Жж]/zh/g; s/[Зз]/z/g; s/[Ии]/y/g; s/[Іі]/i/g; s/[Її]/i/g; s/[Йй]/i/g; s/[Кк]/k/g; s/[Лл]/l/g' \
        -e 's/[Мм]/m/g; s/[Нн]/n/g; s/[Оо]/o/g; s/[Пп]/p/g; s/[Рр]/r/g; s/[Сс]/s/g; s/[Тт]/t/g; s/[Уу]/u/g' \
        -e 's/[Фф]/f/g; s/[Хх]/kh/g; s/[Цц]/ts/g; s/[Чч]/ch/g; s/[Шш]/sh/g; s/[Щщ]/shch/g; s/[Ьь]//g; s/[Юю]/iu/g; s/[Яя]/ia/g; s/[ЫыЭэЁё]/e/g'
}

slugify() {
    printf '%s' "$1" | transliterate | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-40 | sed -E 's/-+$//'
}

task_slug=$(slugify "$description")

# ---------------------------------------------------------------------------
# Step R input: the run state file
# ---------------------------------------------------------------------------

state_path="${repo_abs}/.claude/.sdlc-run-active.json"
state_json=$(jq -cn '{present: false}')
if [ -f "$state_path" ]; then
    if state_raw=$(json_file "$state_path"); then
        ts=$(jq -r '.updated_at // .started_at // empty' <<<"$state_raw")
        epoch=$(iso_to_epoch "$ts")
        age="null"; fresh=false
        if [ -n "$epoch" ]; then
            age=$(( now_epoch - epoch ))
            [ "$age" -ge 0 ] && [ "$age" -lt "$MARKER_MAX_AGE_SECONDS" ] && fresh=true
        fi
        state_json=$(jq -c --argjson age "$age" --argjson fresh "$fresh" '
            {present: true, schema_version: (.schema_version // 1), fresh: $fresh, age_seconds: $age,
             task_slug: .task_slug, started_at: .started_at, updated_at: .updated_at,
             branch_name: .git_flow.branch_name, resume_count: (.resume_count // 0), phase_status: .phase_status}' <<<"$state_raw")
    else
        state_json=$(jq -cn '{present: true, schema_version: null, fresh: false, parse_error: true}')
    fi
fi

# ---------------------------------------------------------------------------
# Step 1b subset: .claude/sdlc.local.yaml
# ---------------------------------------------------------------------------

local_yaml="${repo_abs}/.claude/sdlc.local.yaml"
local_json='{}'
local_present=false
if [ -f "$local_yaml" ]; then
    local_present=true
    local_json=$(yaml_to_json < "$local_yaml" 2>/dev/null) || local_json='{}'
    [ -n "$local_json" ] || local_json='{}'
fi
local_config=$(jq -c --argjson present "$local_present" '
    {present: $present,
     active_workflow: (.active_workflow // null),
     skip_phases: ((.skip_phases // []) | if type == "array" then . else [.] end),
     git: (.git // null),
     post_check_fix_attempts: (.post_check_fix_attempts // null),
     aspect_execution: (.aspect_execution // "sequential"),
     agent_overrides: (.agent_overrides // {}),
     other_keys: ([keys[]] - ["active_workflow","skip_phases","git","post_check_fix_attempts","aspect_execution","agent_overrides"])}' <<<"$local_json")

# ---------------------------------------------------------------------------
# Step 0a: dependency preflight (cache fast-path)
# ---------------------------------------------------------------------------

if [ -n "$deps_cache_dir" ]; then
    deps_cache="${deps_cache_dir}/deps-preflight.json"
elif [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
    deps_cache="${CLAUDE_PLUGIN_DATA}/deps-preflight.json"
else
    deps_cache="${HOME}/.claude/.sdlc-deps-preflight.json"
fi

deps_source="scan"
deps_json=""
if [ "$force_preflight" = false ] && deps_cached=$(json_file "$deps_cache") \
    && [ "$(jq -r '.all_satisfied // false' <<<"$deps_cached")" = "true" ]; then
    deps_json="$deps_cached"; deps_source="cache"
fi
if [ -z "$deps_json" ]; then
    deps_args=(--plugins-root "$plugins_root" --write-cache)
    [ -n "$dev_root" ] && deps_args+=(--dev-root "$dev_root")
    [ -n "$deps_cache_dir" ] && deps_args+=(--cache-dir "$deps_cache_dir")
    deps_json=$(bash "${SCRIPT_DIR}/deps-preflight.sh" "${deps_args[@]}" 2>/dev/null) || deps_json=""
    [ -n "$deps_json" ] || deps_json='{"results":{},"all_satisfied":true,"dependencies":[],"security_guidance_available":false}'
fi
deps_json=$(jq -c --arg src "$deps_source" '. + {source: $src}' <<<"$deps_json")

if [ "$(jq -r '.security_guidance_available // "null"' <<<"$deps_json")" = "null" ]; then
    sg=false
    [ -d "$plugins_root" ] && [ -n "$(find "$plugins_root" -path "*/security-guidance/*.claude-plugin/plugin.json" -print -quit 2>/dev/null)" ] && sg=true
    deps_json=$(jq -c --argjson sg "$sg" '. + {security_guidance_available: $sg}' <<<"$deps_json")
fi

# ---------------------------------------------------------------------------
# Step 0b: stack profiles (session cache fast-path, else detect-stack.sh)
# ---------------------------------------------------------------------------

if [ -z "$stack_cache_dir" ]; then
    stack_cache_dir="${CLAUDE_PLUGIN_DATA:+${CLAUDE_PLUGIN_DATA}/stack-cache}"
    [ -n "$stack_cache_dir" ] || stack_cache_dir="${HOME}/.claude/.sdlc-stack-cache"
fi
ttl_hours="${CLAUDE_PLUGIN_OPTION_STACK_CACHE_TTL_HOURS:-6}"
case "$ttl_hours" in ''|*[!0-9.]*) ttl_hours=6 ;; esac
ttl_seconds=$(awk -v h="$ttl_hours" 'BEGIN { printf "%d", h * 3600 }')

digest=""
if command -v shasum >/dev/null 2>&1; then
    digest=$(printf '%s' "$repo_abs" | shasum -a 1 | cut -c1-16)
elif command -v sha1sum >/dev/null 2>&1; then
    digest=$(printf '%s' "$repo_abs" | sha1sum | cut -c1-16)
fi

stack_source="scan"
stack_json=""
if [ -z "$forced_stack" ] && [ "$redetect_stack" = false ] && [ -n "$digest" ] \
    && cached=$(json_file "${stack_cache_dir}/${digest}.json"); then
    c_schema=$(jq -r '.schema_version // 0' <<<"$cached")
    c_repo=$(jq -r '.repo // ""' <<<"$cached")
    c_epoch=$(iso_to_epoch "$(jq -r '.detected_at // ""' <<<"$cached")")
    if [ "$c_schema" = "1" ] && [ "$c_repo" = "$repo_abs" ] && [ -n "$c_epoch" ] \
        && [ $(( now_epoch - c_epoch )) -lt "$ttl_seconds" ] && [ $(( now_epoch - c_epoch )) -ge 0 ]; then
        stack_json="$cached"; stack_source="cache"
        stack_age_minutes=$(( (now_epoch - c_epoch) / 60 ))
    fi
fi

run_detect_stack() {
    bash "${SCRIPT_DIR}/detect-stack.sh" --repo "$repo_abs" --plugins-root "$1" --write-cache --cache-dir "$stack_cache_dir" 2>/dev/null
}
if [ -z "$stack_json" ]; then
    stack_json=$(run_detect_stack "$plugins_root") || stack_json=""
    if [ -n "$dev_root" ] && [ -d "$dev_root/plugins" ] \
        && [ "$(jq -r '.stack_md_scanned // 0' <<<"${stack_json:-{\}}")" = "0" ]; then
        stack_json=$(run_detect_stack "$dev_root/plugins") || stack_json=""
    fi
    [ -n "$stack_json" ] || stack_json='{"primary_profile":null,"active_profiles":{},"aspect_ties":{},"matched_profiles":[],"stack_md_scanned":0}'
fi

# A forced stack must still be read from some stack.md — it need not have matched.
if [ -n "$forced_stack" ]; then
    forced_source=""
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        if awk 'NR == 1 && $0 != "---" { exit 1 } NR > 1 && /^---/ { exit } NR > 1 { print }' "$f" 2>/dev/null \
            | grep -qE "^stack:[[:space:]]*['\"]?${forced_stack}['\"]?[[:space:]]*$"; then
            forced_source="$f"; break
        fi
    done < <({ [ -d "$plugins_root" ] && find "$plugins_root" -name stack.md -type f 2>/dev/null; \
               [ -n "$dev_root" ] && find "$dev_root/plugins" -maxdepth 2 -name stack.md -type f 2>/dev/null; } | sort)
    if [ -n "$forced_source" ]; then
        fm=$(awk 'NR > 1 && /^---/ { exit } NR > 1 { print }' "$forced_source")
        f_priority=$(printf '%s\n' "$fm" | sed -nE 's/^priority:[[:space:]]*([0-9]+).*/\1/p' | head -1)
        f_aspects=$(printf '%s\n' "$fm" | sed -nE 's/^aspects:[[:space:]]*\[(.*)\].*/\1/p' | head -1 \
            | jq -Rc 'split(",") | map(gsub("^\\s+|\\s+$"; "") | select(length > 0))')
        [ -n "$f_aspects" ] || f_aspects='[]'
        stack_json=$(jq -c --arg s "$forced_stack" --argjson p "${f_priority:-0}" --argjson a "$f_aspects" --arg src "$forced_source" '
            {stack: $s, priority: $p, source: $src} as $prof
            | . + {primary_profile: $prof, aspect_ties: {}, forced: true,
                   matched_profiles: [{stack: $s, priority: $p, aspects: $a, source: $src}],
                   active_profiles: (["backend","frontend","database","infra","testing","messaging"]
                        | map({key: ., value: (if ($a | index(.)) or ($a | length) == 0 then $prof else null end)}) | from_entries)}' <<<"$stack_json")
        stack_source="forced"
    else
        halt "❌ --stack=${forced_stack}: no installed stack.md declares stack: ${forced_stack}."
    fi
fi

if [ "$(jq -r '.aspect_ties | length' <<<"$stack_json")" != "0" ]; then
    while IFS= read -r line; do
        halt "$line"
    done < <(jq -r '.aspect_ties | to_entries[] | "Aspect \u0027\(.key)\u0027 has tie between \(.value | join(", ")). Use --stack=NAME to disambiguate."' <<<"$stack_json")
fi

stack_json=$(jq -c --arg src "$stack_source" --argjson age "${stack_age_minutes:-0}" '
    . + {source: $src, cache_age_minutes: (if $src == "cache" then $age else null end), forced: (.forced // false)}' <<<"$stack_json")

plugin_name_of() {
    local src="$1" dir
    dir=$(dirname "$src")
    case "$dir" in
        */plugins/*) printf '%s' "$(basename "$dir")" ;;
        *)
            # Installed cache: {marketplace}/{plugin}/{version}/stack.md
            printf '%s' "$(basename "$(dirname "$dir")")" ;;
    esac
}

# Distinct stack.md sources that own something in this run (primary + every aspect winner).
# detect-stack.sh reports sources relative to the plugins root it scanned.
profile_sources=$(jq -r '(.plugins_root // "") as $root
    | [.primary_profile.source?, (.active_profiles | to_entries[] | .value.source?)]
    | map(select(. != null)) | unique | .[]
    | "\(.)\t\(if startswith("/") then . else "\($root)/\(.)" end)"' <<<"$stack_json")

# ---------------------------------------------------------------------------
# Step 0b-git: GIT-FLOW Steps A–E (+ F-2a, F-4 decisions)
# ---------------------------------------------------------------------------

git_ok=false
command -v git >/dev/null 2>&1 && git -C "$repo_abs" rev-parse --git-dir >/dev/null 2>&1 && git_ok=true

detected='{}'
if [ "$git_ok" = true ]; then
    detected=$(bash "${SCRIPT_DIR}/detect-git-flow.sh" --repo "$repo_abs" 2>/dev/null) || detected='{}'
    [ -n "$detected" ] || detected='{}'
fi

git_config=$(jq -c '.git // null' <<<"$local_config")
git_flow_source="detection"
cache_info='{"present": false}'
cache_used='{}'

git_cache_path="${repo_abs}/.claude/.sdlc-git-flow.json"
if [ -f "$git_cache_path" ]; then
    if gc=$(json_file "$git_cache_path"); then
        gc_epoch=$(iso_to_epoch "$(jq -r '.detected_at // ""' <<<"$gc")")
        gc_age="null"; [ -n "$gc_epoch" ] && gc_age=$(( now_epoch - gc_epoch ))
        trusted=true
        [ "$(jq -r '.schema_version // 0' <<<"$gc")" = "1" ] || trusted=false
        [ "$(jq -r '.user_confirmed // false' <<<"$gc")" = "true" ] || trusted=false
        [ "$gc_age" != "null" ] && [ "$gc_age" -lt "$GIT_FLOW_CACHE_MAX_AGE_SECONDS" ] || trusted=false
        [ "$redetect_git_flow" = false ] || trusted=false
        if [ "$trusted" = true ] && [ "$git_ok" = true ]; then
            gc_default=$(jq -r '.default_branch // ""' <<<"$gc")
            git -C "$repo_abs" rev-parse --verify --quiet "$gc_default" >/dev/null 2>&1 || trusted=false
            if [ "$(jq -r '.model // ""' <<<"$gc")" = "git-flow" ]; then
                gc_dev=$(jq -r '.develop_branch // ""' <<<"$gc")
                [ -n "$gc_dev" ] && git -C "$repo_abs" rev-parse --verify --quiet "$gc_dev" >/dev/null 2>&1 || trusted=false
            fi
        fi
        cache_info=$(jq -c --argjson age "$gc_age" --argjson trusted "$trusted" \
            '{present: true, user_confirmed: (.user_confirmed // false), detected_at: .detected_at, age_seconds: $age, trusted: $trusted, model: .model,
              disagrees_with_detection: false}' <<<"$gc")
        [ "$trusted" = true ] && cache_used="$gc"
    else
        cache_info='{"present": true, "parse_error": true, "trusted": false}'
        warn "⚠️ .claude/.sdlc-git-flow.json could not be parsed — ignoring it and re-detecting."
    fi
fi

# Layering: detection ← cache ← explicit config. A present key replaces, absent falls through.
effective=$(jq -cn --argjson d "$detected" --argjson c "$cache_used" --argjson cfg "$git_config" '
    def layer($over): . as $base
        | ($over // {}) as $o
        | $base
        | if $o.model then .model = $o.model else . end
        | if $o.default_branch then .default_branch = $o.default_branch else . end
        | if ($o | has("develop_branch")) and $o.develop_branch != null then .develop_branch = $o.develop_branch else . end
        | if $o.prefix_style then .prefix_style = $o.prefix_style else . end
        | if $o.prefix_histogram then .prefix_histogram = $o.prefix_histogram else . end
        | if $o.naming then .naming = ((.naming // {}) + $o.naming) else . end
        | if $o.type_policy then .type_policy = $o.type_policy else . end
        | if ($o | has("auto_create_branch")) then .auto_create_branch = $o.auto_create_branch else . end
        | if $o.sources then .sources = $o.sources else . end
        | if $o.confidence then .confidence = $o.confidence else . end;
    ($d // {})
    | .model //= "unknown" | .confidence //= "low" | .sources //= [] | .naming //= {}
    | .prefix_style //= "none" | .prefix_histogram //= {}
    | layer($c) | layer($cfg)
    | .auto_create_branch //= true')

config_override_keys='[]'
if [ "$git_config" != "null" ]; then
    git_flow_source="config"
    config_override_keys=$(jq -c 'keys' <<<"$git_config")
elif [ "$(jq -r '.model // empty' <<<"$cache_used")" != "" ]; then
    git_flow_source="cache"
fi
if [ "$(jq -r '.present' <<<"$cache_info")" = "true" ] && [ "$(jq -r '.model // ""' <<<"$cache_info")" != "" ] \
    && [ "$(jq -r '.model // ""' <<<"$detected")" != "" ] \
    && [ "$(jq -r '.model' <<<"$cache_info")" != "$(jq -r '.model' <<<"$detected")" ]; then
    cache_info=$(jq -c '.disagrees_with_detection = true' <<<"$cache_info")
fi

# Step B: documented-convention scan. Hits are reported; the statement judgement is the model's.
convention_hits='[]'
for candidate in CLAUDE.md .claude/CLAUDE.md .claude/rules/*.md AGENTS.md GEMINI.md CONTRIBUTING.md .cursorrules .cursor/rules/* .github/pull_request_template.md .github/PULL_REQUEST_TEMPLATE.md; do
    for file in "$repo_abs"/$candidate; do
        [ -f "$file" ] || continue
        rel="${file#"$repo_abs"/}"
        while IFS= read -r hit; do
            [ -n "$hit" ] || continue
            ln="${hit%%:*}"; text="${hit#*:}"
            convention_hits=$(jq -c --arg p "$rel" --argjson l "$ln" --arg t "$text" '. + [{path: $p, line: $l, text: $t}]' <<<"$convention_hits")
        done < <(grep -n -i -E 'branch|git.flow|git-flow|develop|prefix|feature/' "$file" 2>/dev/null | head -8)
    done
done
convention_hits=$(jq -c '.[0:24]' <<<"$convention_hits")

# Step C: task-type classification against references/task-type-patterns.json. Oniguruma
# rejects a character class inside a look-behind, so the ECMAScript boundary is rewritten
# into two single-class look-behinds with identical meaning.
classification=$(jq -c --arg text "$description" --arg forced "$forced_type" '
    def compat: gsub("\\(\\?<!\\[\\\\p\\{L\\}\\\\p\\{N\\}\\]\\)"; "(?<!\\p{L})(?<!\\p{N})");
    . as $table
    | (.precedence) as $order
    | [ $order[] as $t | select(any($table.types[$t].patterns[]; . as $pat | ($text | test(($pat | compat); "ix")))) | $t ] as $matches
    | ($order | index($forced)) as $forced_ok
    | if $forced != "" and $forced_ok != null then
        {task_type: $forced, confidence: "high", source: "flag", runners_up: [], matches: $matches, invalid_flag: null}
      elif ($matches | length) == 0 then
        {task_type: "feature", confidence: "low", source: "default", runners_up: [], matches: [],
         invalid_flag: (if $forced != "" then $forced else null end)}
      elif ($matches | length) == 1 then
        {task_type: $matches[0], confidence: "high", source: "keyword", runners_up: [], matches: $matches,
         invalid_flag: (if $forced != "" then $forced else null end)}
      else
        {task_type: $matches[0], confidence: "medium", source: "keyword", runners_up: $matches[1:], matches: $matches,
         invalid_flag: (if $forced != "" then $forced else null end)}
      end
    | . + {typo_fix_match: any($table.skip_rules.typo_fix.patterns[]; . as $pat | ($text | test(($pat | compat); "ix")))}' "$PATTERNS_FILE" 2>/dev/null) \
    || classification='{"task_type":"feature","confidence":"low","source":"default","runners_up":[],"matches":[],"invalid_flag":null,"typo_fix_match":false}'
task_type=$(jq -r '.task_type' <<<"$classification")
if [ "$(jq -r '.invalid_flag // empty' <<<"$classification")" != "" ]; then
    warn "⚠️ --type=${forced_type} is not one of feature, fix, bugfix, hotfix, release, refactor, docs, chore — classified from keywords instead."
fi

# Steps D + E: policy, prefix spelling, branch name. Pure functions of what is known so far.
release_branch=$(jq -r '(.release_branches // []) | .[]' <<<"$effective" | sort -V | tail -1)
policy=$(jq -c --arg t "$task_type" --arg rel "$release_branch" --arg slug "$task_slug" --arg args "$description" '
    .default_branch as $main | .develop_branch as $dev
    | (if $rel == "" then $main else $rel end) as $relbase
    | ({feature: {prefix: "feature", from: $dev, pr_base: $dev},
        fix: {prefix: "fix", from: $dev, pr_base: $dev},
        bugfix: {prefix: "bugfix", from: $relbase, pr_base: $relbase},
        hotfix: {prefix: "hotfix", from: $relbase, pr_base: $relbase},
        release: {prefix: "release", from: $dev, pr_base: $main},
        refactor: {prefix: "refactor", from: $dev, pr_base: $dev},
        docs: {prefix: "docs", from: $dev, pr_base: $dev},
        chore: {prefix: "chore", from: $dev, pr_base: $dev}}) as $gitflow
    | ($gitflow[$t] // $gitflow.feature) as $row
    | (if .model == "git-flow" and $dev != null then $row
       elif .model == "custom" and (.type_policy[$t]? != null) then
            {prefix: (.type_policy[$t].prefix // $row.prefix), from: (.type_policy[$t].from // $main), pr_base: (.type_policy[$t].pr_base // $main)}
       elif .model == "custom" and $dev != null then $row
       else {prefix: $row.prefix, from: $main, pr_base: $main} end) as $p
    | ($p.from // $main) as $from | ($p.pr_base // $main) as $pr_base
    | (.prefix_histogram // {}) as $h
    | ([["feature","feat"],["fix","bugfix","hotfix"],["docs","doc"],["chore","build","ci"],["refactor","perf","style"]]
       | map(select(index($p.prefix))) | .[0] // []) as $syn
    | (if .prefix_style == "none" then {prefix: "", note: "no prefix (project uses none)"}
       elif ($h | has($p.prefix)) then {prefix: $p.prefix, note: null}
       elif ([$syn[] | select($h[.] != null)] | length) > 0 then
            ([$syn[] | select($h[.] != null)] | .[0]) as $obs | {prefix: $obs, note: ("observed synonym \u0027\($obs)\u0027 used instead of \u0027\($p.prefix)\u0027")}
       elif ($h | length) > 0 then {prefix: $p.prefix, note: ("prefix \u0027\($p.prefix)\u0027 is new to this project")}
       else {prefix: $p.prefix, note: null} end) as $spelling
    | (.naming.separator // "/") as $sep | (.naming.word_separator // "-") as $wsep
    | ($slug | gsub("-"; $wsep)) as $slug2
    | (.naming.ticket_pattern // null) as $tp
    | (if $tp != null then ($args | [match($tp; "g")] | map(.string) | .[0] // null) else null end) as $ticket
    | (.naming.ticket_position // "after-prefix") as $tpos
    | (if $spelling.prefix == "" then "" else $spelling.prefix + $sep end) as $head
    | (if $ticket == null then $head + $slug2
       elif $tpos == "leading" then $ticket + $wsep + $slug2
       else $head + $ticket + $wsep + $slug2 end) as $raw
    | (.naming.max_length // 60) as $cap
    | (if ($raw | length) <= $cap then $raw else ($raw[0:$cap] | sub("[-_/]+$"; "")) end) as $name
    | (if $ticket == null then $slug2 else $ticket + $wsep + $slug2 end) as $topic
    | {prefix: $spelling.prefix, prefix_note: $spelling.note, base_branch: $from, pr_base_branch: $pr_base,
       requires_back_merge: (if (.model == "git-flow" or .model == "custom") and $dev != null and ($t == "release" or $t == "hotfix") then $dev else null end),
       branch_name: $name, topic: $topic, ticket: $ticket,
       native_subcommand: ({feature: "feature", release: "release", hotfix: "hotfix"}[$t] // null)}' <<<"$effective")

branch_name=$(jq -r '.branch_name' <<<"$policy")
base_branch=$(jq -r '.base_branch // ""' <<<"$policy")

# Step E collision suffix.
if [ "$git_ok" = true ] && [ -n "$branch_name" ]; then
    branch_exists() {
        git -C "$repo_abs" show-ref --verify --quiet "refs/heads/$1" && return 0
        [ -n "$(git -C "$repo_abs" for-each-ref "refs/remotes/*/$1" 2>/dev/null)" ]
    }
    if branch_exists "$branch_name"; then
        candidate=""
        for n in 2 3 4 5 6 7 8 9; do
            if ! branch_exists "${branch_name}-${n}"; then candidate="${branch_name}-${n}"; break; fi
        done
        if [ -n "$candidate" ]; then
            warn "⚠️ Branch ${branch_name} already exists — proposing ${candidate}."
            branch_name="$candidate"
        else
            warn "⚠️ Branch ${branch_name} and every -2…-9 variant already exist — the gate must ask for a name."
        fi
        policy=$(jq -c --arg b "$branch_name" '.branch_name = $b' <<<"$policy")
    fi
fi

# F-2a: how "create" would create the branch.
creation_method=$(jq -r --argjson p "$policy" '
    if .model == "git-flow" and (.git_flow_cli_available // false) and (.git_flow_initialized // false) and $p.native_subcommand != null
    then "git-flow-cli" else "checkout-b" end' <<<"$effective")

current_branch=$(jq -r '.current_branch // ""' <<<"$effective")
current_is_base=$(jq -r '.current_branch_is_base // false' <<<"$effective")
base_resolves=false
[ "$git_ok" = true ] && [ -n "$base_branch" ] && git -C "$repo_abs" rev-parse --verify --quiet "$base_branch" >/dev/null 2>&1 && base_resolves=true

# F-4: the decision a headless run takes without asking.
headless_decision=$(jq -cn --argjson e "$effective" --argjson p "$policy" --argjson base "$current_is_base" \
    --arg cur "$current_branch" --arg method "$creation_method" --argjson headless "$headless" '
    ($e.confidence == "low" or $e.model == "unknown") as $low
    | (if $low then "github-flow" else $e.model end) as $model
    | (if $low then {base_branch: $e.default_branch, pr_base_branch: $e.default_branch, requires_back_merge: null} else {} end) as $fb
    | (if ($e.auto_create_branch // true) == false then "declined"
       elif $base then "create" else "continued" end) as $action
    | {applies: $headless, model: $model, fallback: (if $low then "low-confidence" else null end),
       branch_action: $action,
       branch_creation_method: (if $low or $action != "create" then "checkout-b" else $method end),
       branch_name: (if $action == "create" then $p.branch_name else $cur end)} + $fb')

git_flow_json=$(jq -cn --argjson e "$effective" --argjson p "$policy" --argjson cls "$classification" \
    --arg src "$git_flow_source" --argjson cfgkeys "$config_override_keys" --argjson cache "$cache_info" \
    --argjson det "$detected" --argjson hits "$convention_hits" --arg method "$creation_method" \
    --argjson base_resolves "$base_resolves" --argjson hd "$headless_decision" --argjson git_ok "$git_ok" '
    {git_available: $git_ok, source: $src, config_override_keys: $cfgkeys, cache: $cache,
     model: $e.model, confidence: $e.confidence, sources: $e.sources,
     default_branch: $e.default_branch, develop_branch: $e.develop_branch, release_branches: ($e.release_branches // []),
     prefix_style: $e.prefix_style, prefix_histogram: $e.prefix_histogram, naming: $e.naming,
     branches_analyzed: ($e.branches_analyzed // 0),
     git_flow_cli_available: ($e.git_flow_cli_available // false), git_flow_initialized: ($e.git_flow_initialized // false),
     auto_create_branch: ($e.auto_create_branch // true),
     current_branch: $e.current_branch, current_branch_is_base: ($e.current_branch_is_base // false),
     dirty_file_count: ($e.dirty_file_count // 0),
     documented_convention_hits: $hits,
     task_type: $cls.task_type, task_type_confidence: $cls.confidence, task_type_source: $cls.source,
     task_type_runners_up: $cls.runners_up,
     prefix: $p.prefix, prefix_note: $p.prefix_note, ticket: $p.ticket,
     branch_name: $p.branch_name, git_flow_topic: $p.topic,
     base_branch: $p.base_branch, base_branch_resolves: $base_resolves,
     pr_base_branch: $p.pr_base_branch, requires_back_merge: $p.requires_back_merge,
     branch_creation_method: $method, native_subcommand: $p.native_subcommand,
     topology_conflict: null,
     gate_default: (if ($e.current_branch_is_base // false) then "create"
                    elif ($e.current_branch // "") != "" and ($e.current_branch | test("^[A-Za-z][A-Za-z0-9._-]*/")) then "continue"
                    else "create" end),
     headless_decision: $hd,
     detected_raw: $det}')

# ---------------------------------------------------------------------------
# Step 0c: diff signals and skip-rules
# ---------------------------------------------------------------------------

diff_json='{"diff_scope":"prospective","reason":"git unavailable","loc_touched":999999,"has_migrations":true,"config_only":false,"whitespace_only":false,"commits_ahead":0,"changed_files":[],"added":0,"deleted":0}'
rule4_path_hit=""; rule4_content_hit=""
if [ "$git_ok" = true ] && [ "$base_resolves" = true ]; then
    range="${base_branch}...HEAD"
    if changed_files=$(git -C "$repo_abs" diff --name-only "$range" 2>/dev/null); then
        commits_ahead=$(git -C "$repo_abs" rev-list --count "${base_branch}..HEAD" 2>/dev/null || echo 0)
        if [ "$commits_ahead" = "0" ] || [ -z "$changed_files" ]; then
            reason="nothing to measure"; [ "$commits_ahead" = "0" ] && reason="no commits ahead of ${base_branch}"
            [ "$commits_ahead" != "0" ] && [ -z "$changed_files" ] && reason="commits present but the net diff is empty"
            diff_json=$(jq -c --arg r "$reason" --argjson c "$commits_ahead" '.reason = $r | .commits_ahead = $c' <<<"$diff_json")
        else
            numstat=$(git -C "$repo_abs" diff --numstat "$range" 2>/dev/null | awk '{ i += $1; d += $2 } END { print i + 0, d + 0 }')
            added=${numstat%% *}; deleted=${numstat##* }
            shortstat=$(git -C "$repo_abs" diff --shortstat "$range" 2>/dev/null)
            shortstat_w=$(git -C "$repo_abs" diff --shortstat -w "$range" 2>/dev/null)
            whitespace_only=false
            if [ -z "$shortstat" ]; then
                whitespace_only=true
            elif [ -n "$shortstat" ] && ! printf '%s' "$shortstat_w" | grep -qE '[0-9]+ (insertion|deletion)'; then
                whitespace_only=true
            fi
            files_json=$(printf '%s\n' "$changed_files" | jq -Rsc 'split("\n") | map(select(length > 0))')
            has_migrations=$(jq -r 'any(.[]; test("(database/migrations|/migrations/)"))' <<<"$files_json")
            config_only=$(jq -r 'all(.[]; test("\\.(env|env\\..+|ya?ml|json|toml|ini)$"; "i"))' <<<"$files_json")
            rule4_path_hit=$(jq -r '[.[] | select(test("auth|password|crypt|secret|token|jwt|session|upload|exec|shell|raw|query|fetch|http|storage|serializ"; "i"))] | .[0] // ""' <<<"$files_json")
            rule4_content_hit=$(git -C "$repo_abs" diff "$range" 2>/dev/null | grep '^+' | grep -nE 'DB::raw|eval\(|exec\(|shell_exec|child_process|subprocess|pickle|unserialize' | head -1 | cut -c1-160)
            diff_json=$(jq -cn --argjson a "$added" --argjson d "$deleted" --argjson c "$commits_ahead" --argjson f "$files_json" \
                --argjson m "$has_migrations" --argjson co "$config_only" --argjson w "$whitespace_only" '
                {diff_scope: "retrospective", reason: null, loc_touched: ($a + $d), added: $a, deleted: $d, commits_ahead: $c,
                 changed_files: $f, has_migrations: $m, config_only: $co, whitespace_only: $w}')
        fi
    else
        diff_json=$(jq -c '.reason = "git diff against the base failed"' <<<"$diff_json")
    fi
elif [ "$git_ok" = true ]; then
    diff_json=$(jq -c --arg b "$base_branch" '.reason = "base ref \($b) does not resolve"' <<<"$diff_json")
fi

skip_rules=$(jq -cn --argjson d "$diff_json" --argjson cls "$classification" --argjson local "$local_config" \
    --arg p4 "$rule4_path_hit" --arg c4 "$rule4_content_hit" '
    ($local.skip_phases) as $pre
    | {removed: $pre, applied: []}
    | def fire($rule; $phases; $reason):
        reduce $phases[] as $ph (.; if (.removed | index($ph)) == null then
            .removed += [$ph] | .applied += [{rule: $rule, phase_skipped: $ph, reason: $reason}] else . end);
    (if $d.diff_scope == "retrospective" then . else . end)
    | if $cls.typo_fix_match and $d.diff_scope == "retrospective" and $d.loc_touched < 30 then
        fire("typo-fix"; ["business_analysis"]; "$ARGUMENTS matched a typo_fix pattern AND LOC_TOUCHED=\($d.loc_touched) < 30") else . end
    | if $d.diff_scope == "retrospective" and $d.whitespace_only then
        fire("whitespace-only"; ["business_analysis", "qa"]; "diff is whitespace-only (LOC_TOUCHED=\($d.loc_touched))") else . end
    | if $d.diff_scope == "retrospective" and $d.config_only and $d.loc_touched < 200 then
        fire("config-only"; ["qa"]; "all \($d.changed_files | length) changed paths matched /\\.(env|ya?ml|json|toml|ini)$/i; LOC_TOUCHED=\($d.loc_touched)") else . end
    | if $d.diff_scope == "retrospective" and $d.loc_touched < 50 and ($d.has_migrations | not) and $p4 == "" and $c4 == "" then
        fire("lightweight-no-db"; ["security"]; "LOC_TOUCHED=\($d.loc_touched) < 50, no migrations, path check empty, content check empty") else . end
    | {skip_rules_applied: .applied,
       phases_removed: .removed,
       security_lite: ((.applied | map(.rule) | index("lightweight-no-db")) != null),
       rule4_path_hit: (if $p4 == "" then null else $p4 end),
       rule4_content_hit: (if $c4 == "" then null else $c4 end)}')

# ---------------------------------------------------------------------------
# Profiles: agents, convention skills, post checks, extra phases, injections
# ---------------------------------------------------------------------------

profiles='[]'
while IFS=$'\t' read -r rel src; do
    [ -n "$src" ] && [ -f "$src" ] || continue
    pname=$(plugin_name_of "$src")
    owned=$(find "$(dirname "$src")/agents" -maxdepth 1 -name '*.md' 2>/dev/null | sed -E 's|.*/||; s|\.md$||' | jq -Rsc 'split("\n") | map(select(length > 0))')
    stack_name=$(awk 'NR > 1 && /^---/ { exit } NR > 1 { print }' "$src" | sed -nE "s/^stack:[[:space:]]*['\"]?([A-Za-z0-9_-]+)['\"]?.*/\1/p" | head -1)
    agents=$(md_section "$src" "## Agents per phase" | sed -E 's/^- //' | yaml_to_json 2>/dev/null) || agents='{}'
    [ -n "$agents" ] || agents='{}'
    extras=$(md_section "$src" "## Extra phases" | yaml_to_json 2>/dev/null) || extras='[]'
    extras=$(jq -c 'if type == "object" then [to_entries[] | select(.key | test("^[0-9]+$")) | .value] elif type == "array" then . else [] end
                    | map(select(type == "object" and .name != null) | {name, after, agent, aspect})' <<<"${extras:-[]}" 2>/dev/null || echo '[]')
    skills=$(md_section "$src" "## Convention skills" | sed -nE 's/^- +([A-Za-z0-9_.:-]+).*/\1/p' | jq -Rsc 'split("\n") | map(select(length > 0))')
    checks=$(md_section "$src" "## Post-pipeline checks" | sed -nE 's/^- +`?(.*[^`])`?[[:space:]]*$/\1/p' | sed -E 's/^`//; s/`$//' | jq -Rsc 'split("\n") | map(select(length > 0))')
    injections=$(md_section "$src" "## Phase prompts injection" | sed -nE 's/^For ([a-z_]+) phase.*inject:.*/\1/p' | jq -Rsc 'split("\n") | map(select(length > 0)) | unique')
    profiles=$(jq -c --arg s "$stack_name" --arg p "$pname" --arg src "$rel" --arg abs "$src" --argjson a "$agents" --argjson e "$extras" \
        --argjson sk "$skills" --argjson ch "$checks" --argjson inj "$injections" --argjson owned "$owned" \
        '. + [{stack: $s, plugin: $p, source: $src, path: $abs, owned_agents: $owned, agents: $a, extra_phases: $e, convention_skills: $sk, post_pipeline_checks: $ch, injection_phases: $inj}]' <<<"$profiles")
done <<<"$profile_sources"

effective_profile=$(jq -cn --argjson stack "$stack_json" --argjson profiles "$profiles" --argjson local "$local_config" '
    def by_source($s): ($profiles | map(select(.source == $s)) | .[0]);
    ($stack.primary_profile.source) as $psrc
    | (by_source($psrc) // {stack: "vanilla", plugin: "sdlc", agents: {}, extra_phases: [], convention_skills: [], post_pipeline_checks: [], injection_phases: []}) as $primary
    | {business_analysis: "business-analyst", qa: "qa-engineer", security: "security-analyst", documentation: "document-writer", development: "developer"} as $core
    | ($stack.active_profiles | to_entries | map(select(.value != null))) as $aspects
    | ($aspects | map(.value.source) | unique) as $distinct
    | def agent_for($prof; $phase; $aspect):
        ($prof.agents[$phase]) as $v
        | if ($v | type) == "object" then ($v[$aspect] // null)
          elif ($v | type) == "string" then $v else null end;
    ($aspects | map(. as $e | by_source($e.value.source) as $prof
        | {key: $e.key, value: (agent_for($prof; "development"; $e.key))} | select(.value != null)) | from_entries) as $dev_by_aspect
    | (($distinct | length) <= 1 and (($primary.agents.development | type) == "string")) as $dev_scalar
    | (if $dev_scalar then {} else $dev_by_aspect end) as $dev
    | (if ($distinct | length) > 1 then
         ($aspects | map(. as $e | by_source($e.value.source) as $prof
            | {key: $e.key, value: (agent_for($prof; "qa"; $e.key) // $core.qa)} | select($dev[.key] != null)) | from_entries)
       else ($primary.agents.qa // $core.qa) end) as $qa
    | ($profiles | map(.extra_phases) | add // [] | unique_by(.name)) as $extras
    | ({business_analysis: ($primary.agents.business_analysis // $core.business_analysis),
        development: (if $dev_scalar then $primary.agents.development elif ($dev | length) > 0 then $dev else $core.development end),
        qa: $qa,
        security: ($primary.agents.security // $core.security),
        documentation: ($primary.agents.documentation // $core.documentation)}
       + ($extras | map({key: .name, value: .agent}) | from_entries)
       + ($local.agent_overrides // {})) as $pa
    | def plugin_for($agent):
        ([$profiles[] | select(.owned_agents | index($agent)) | .plugin] | .[0]) // "sdlc";
    ($pa | [to_entries[] | .value | if type == "object" then .[] else . end] | unique
          | map(select(. != null) | if contains(":") then . else "\(plugin_for(.)):\(.)" end)) as $roster
    | {primary: {stack: $primary.stack, plugin: $primary.plugin, source: $psrc},
       active_profiles: ($aspects | map({key: .key, value: .value.stack}) | from_entries),
       distinct_profiles: ($distinct | length),
       phase_agents: $pa,
       roster: $roster,
       phase_status_keys: ([("business_analysis"),
                            (if ($pa.development | type) == "object" then ($pa.development | keys[] | "development/\(.)") else "development" end),
                            ($extras[] | .name),
                            (if ($pa.qa | type) == "object" then ($pa.qa | keys[] | "qa/\(.)") else "qa" end),
                            "security", "documentation"]),
       extra_phases: $extras,
       convention_skills: ($profiles | map(.convention_skills) | add // [] | unique | sort),
       post_pipeline_checks: (($primary.post_pipeline_checks // []) + ($profiles | map(select(.source != $psrc) | .post_pipeline_checks) | add // []) | unique),
       injection_phases: ($profiles | map({key: .plugin, value: .injection_phases}) | from_entries),
       aspect_execution: $local.aspect_execution}')

# ---------------------------------------------------------------------------
# Step 1c: workflow resolution (RESOLVER.md Steps 1–5)
# ---------------------------------------------------------------------------

recipe_path_for() {
    local name="$1"
    if [ -f "${repo_abs}/.claude/sdlc-workflows/${name}.yaml" ]; then
        printf '%s' "${repo_abs}/.claude/sdlc-workflows/${name}.yaml"
    elif [ -f "${workflows_dir}/${name}.yaml" ]; then
        printf '%s' "${workflows_dir}/${name}.yaml"
    else
        return 1
    fi
}

parse_recipe() {
    local path="$1" scalars phases
    scalars=$(grep -vE '^[[:space:]]*(phases:|-)' "$path" | grep -vE '^[[:space:]]+(parallel:|- )' | yaml_to_json 2>/dev/null) || scalars='{}'
    phases=$(awk '
        function trim(s) { sub(/^[ \t]+/, "", s); sub(/[ \t]+$/, "", s); return s }
        function flush() { if (cur != "") { out = out (out == "" ? "" : ",") cur; cur = "" } }
        /^phases:/ { inp = 1; next }
        inp && /^[^ \t]/ { inp = 0 }
        !inp { next }
        /^[ \t]*#/ || /^[ \t]*$/ { next }
        {
            line = $0; sub(/[ \t]+#.*$/, "", line)
            match(line, /^ */); ind = RLENGTH; rest = trim(substr(line, ind + 1))
            if (rest ~ /^- parallel:/) { flush(); cur = "{\"parallel\":["; mode = "par"; pind = ind; next }
            if (mode == "par" && ind > pind) {
                if (rest ~ /^- name:/) { v = trim(substr(rest, 8)); cur = cur (cur ~ /\[$/ ? "" : ",") "{\"name\":\"" v "\"}"; next }
                if (rest ~ /^when:/) { v = trim(substr(rest, 6)); gsub(/"/, "\\\"", v); sub(/}$/, "", cur); cur = cur ",\"when\":\"" v "\"}"; next }
                if (rest ~ /^- /) { v = trim(substr(rest, 3)); cur = cur (cur ~ /\[$/ ? "" : ",") "\"" v "\""; next }
                next
            }
            if (mode == "par") { cur = cur "]}"; flush(); mode = "" }
            if (rest ~ /^- name:/) { flush(); v = trim(substr(rest, 8)); cur = "{\"name\":\"" v "\"}"; mode = "obj"; oind = ind; next }
            if (mode == "obj" && rest ~ /^when:/ && ind > oind) { v = trim(substr(rest, 6)); gsub(/"/, "\\\"", v); sub(/}$/, "", cur); cur = cur ",\"when\":\"" v "\"}"; next }
            if (rest ~ /^- /) { flush(); mode = ""; v = trim(substr(rest, 3)); cur = "\"" v "\""; flush(); next }
        }
        END { if (mode == "par") cur = cur "]}"; flush(); print "[" out "]" }' "$path")
    jq -cn --argjson s "${scalars:-{\}}" --argjson p "$phases" --arg path "$path" '
        $s | .phases = $p | .path = $path
        | .match //= {} | .caps //= {}
        | .phases |= map(if type == "string" then [{name: .}]
                         elif has("parallel") then (.parallel | map(if type == "string" then {name: .} else . end))
                         else [.] end)' 2>/dev/null
}

workflow_name=""; selection_reason=""; recipe=""; project_local=false

match_holds() {
    # $1 = recipe JSON, $2 = "select" | "veto". Prints true/false.
    jq -rn --argjson r "$1" --argjson d "$diff_json" --arg mode "$2" --arg args "$description" '
        def compat: gsub("\\(\\?<!\\[\\\\p\\{L\\}\\\\p\\{N\\}\\]\\)"; "(?<!\\p{L})(?<!\\p{N})");
        ($d.diff_scope == "retrospective") as $measured
        | ($r.match // {}) as $m
        | [ (if $m.loc_touched_max != null then (if $measured then $d.loc_touched <= $m.loc_touched_max else ($mode == "veto") end) else true end),
            (if $m.loc_touched_min != null then (if $measured then $d.loc_touched >= $m.loc_touched_min else ($mode == "veto") end) else true end),
            (if $m.has_migrations != null then (if $measured then $d.has_migrations == $m.has_migrations else ($mode == "veto") end) else true end),
            (if $m.config_only != null then (if $measured then $d.config_only == $m.config_only else ($mode == "veto") end) else true end),
            (if $m.arguments_pattern != null and $mode == "select" then ($args | test(($m.arguments_pattern | compat); "ix")) else true end) ]
        | all'
}

try_named() {
    # $1 = name, $2 = reason, $3 = halt-on-missing (true/false). Sets recipe/workflow_name on success.
    local path
    if path=$(recipe_path_for "$1"); then
        recipe=$(parse_recipe "$path")
        workflow_name="$1"; selection_reason="$2"
        case "$path" in "${repo_abs}/.claude/sdlc-workflows/"*) project_local=true ;; esac
        return 0
    fi
    if [ "$3" = true ]; then
        halt "❌ Workflow '$1' not found.
   Searched: <project>/.claude/sdlc-workflows/$1.yaml
             ~/.claude/plugins/cache/sdlc/workflows/$1.yaml
   Available: $(find "$workflows_dir" -maxdepth 1 -name "*.yaml" 2>/dev/null | sed "s|.*/||; s/\.yaml$//" | sort | tr "\n" " " | sed "s/ $//")
   Omit --workflow=NAME to use the default workflow."
    else
        warn "⚠️ Inferred workflow '$1' not found — falling back."
    fi
    return 1
}

local_workflow=$(jq -r '.active_workflow // ""' <<<"$local_config")
mapped=$(jq -rn --arg t "$task_type" '{fix: "bugfix", bugfix: "bugfix", hotfix: "hotfix", refactor: "refactor", docs: "docs-only", feature: "default", release: "default", chore: "default"}[$t] // "default"')

if [ -n "$forced_workflow" ]; then
    try_named "$forced_workflow" "flag" true
elif [ -n "$local_workflow" ]; then
    try_named "$local_workflow" "config" true
fi
if [ -z "$workflow_name" ] && [ "$(jq -r 'length' <<<"$halts")" = "0" ]; then
    if try_named "$mapped" "task_type=${task_type}" false; then
        if [ "$(match_holds "$recipe" veto)" != "true" ]; then
            warn "ℹ️ task_type=${task_type} maps to '${mapped}' but its match constraints contradict the measured diff — continuing the resolution order."
            workflow_name=""; recipe=""
        fi
    fi
fi
if [ -z "$workflow_name" ] && [ "$(jq -r 'length' <<<"$halts")" = "0" ]; then
    for path in "${repo_abs}"/.claude/sdlc-workflows/*.yaml "${workflows_dir}"/*.yaml; do
        [ -f "$path" ] || continue
        name=$(basename "$path" .yaml)
        case "$name" in default|bugfix|hotfix|refactor|docs-only) continue ;; esac
        cand=$(parse_recipe "$path") || continue
        [ -n "$cand" ] || continue
        if [ "$(match_holds "$cand" select)" = "true" ]; then
            recipe="$cand"; workflow_name="$name"; selection_reason="match:${name}"
            case "$path" in "${repo_abs}/.claude/sdlc-workflows/"*) project_local=true ;; esac
            break
        fi
    done
fi
if [ -z "$workflow_name" ] && [ "$(jq -r 'length' <<<"$halts")" = "0" ]; then
    try_named "default" "fallback" true
fi

workflow_json='{"active_workflow":null,"resolved_phases":[],"workflow_selection_reason":null}'
if [ -n "$workflow_name" ] && [ -n "$recipe" ]; then
    workflow_json=$(jq -cn --argjson r "$recipe" --argjson ep "$effective_profile" --argjson sr "$skip_rules" \
        --arg name "$workflow_name" --arg reason "$selection_reason" --argjson pl "$project_local" \
        --arg opt "${CLAUDE_PLUGIN_OPTION_DEFAULT_COST_CAP_USD:-0}" '
        def names: [.[][] | .name];
        ($r.phases) as $groups
        | ($groups | names | group_by(.) | map(select(length > 1) | .[0])) as $dups
        | ($ep.extra_phases) as $extras
        | reduce $extras[] as $x ({groups: $groups, warnings: []};
            (.groups | map(any(.[]; .name == $x.after)) | index(true)) as $i
            | if $i == null then .warnings += ["⚠️ Extra phase \u0027\($x.name)\u0027 has after=\u0027\($x.after)\u0027 which is not present in workflow \u0027\($name)\u0027 — skipping."]
              else .groups = (.groups[0:$i + 1] + [[{name: $x.name, aspect: $x.aspect}]] + .groups[$i + 1:]) end)
        | . as $st
        | ($st.groups | names | group_by(.) | map(select(length > 1) | .[0])) as $dups2
        | ($sr.phases_removed) as $skip
        | ($st.groups | map(map(select((.name as $n | $skip | index($n)) == null)) | select(length > 0))) as $resolved
        | {active_workflow: $name, workflow_selection_reason: $reason, project_local: $pl, recipe_path: $r.path,
           recipe_phases: $groups, duplicate_phase: ($dups[0] // $dups2[0] // null),
           resolved_phases: ($resolved | map(map(.name))),
           resolved_members: $resolved,
           steps: ($resolved | length),
           parallel_groups: ($resolved | map(select(length > 1) | map(.name) | join(" ∥ "))),
           max_total_cost_usd: ($r.caps.max_total_cost_usd // (if ($opt | tonumber? // 0) > 0 then ($opt | tonumber) else null end)),
           cost_cap_source: (if $r.caps.max_total_cost_usd != null then "recipe" elif ($opt | tonumber? // 0) > 0 then "plugin_option" else null end),
           warnings: $st.warnings}')
    while IFS= read -r w; do [ -n "$w" ] && warn "$w"; done < <(jq -r '.warnings[]' <<<"$workflow_json")
    dup=$(jq -r '.duplicate_phase // ""' <<<"$workflow_json")
    [ -n "$dup" ] && halt "❌ Workflow '${workflow_name}' contains duplicate phase '${dup}'. A workflow DAG must be acyclic — each phase may appear at most once."
fi

# ---------------------------------------------------------------------------
# Pre-rendered MUST PRINT VERBATIM blocks
# ---------------------------------------------------------------------------

print_blocks=$(jq -cn --argjson deps "$deps_json" --argjson stack "$stack_json" --argjson ep "$effective_profile" \
    --argjson gf "$git_flow_json" --argjson sr "$skip_rules" --argjson wf "$workflow_json" --argjson headless "$headless" '
    def pad($n): . + (" " * ($n - length) | if . == null then "" else . end);
    (if $deps.source == "cache" then "🔧 Dependency preflight: cached (all satisfied)"
     elif ($deps.dependencies | length) == 0 then "🔌 Dependency preflight: no external dependencies declared."
     else "🔌 Dependency preflight:\n" + ($deps.dependencies | map(
        "   \(.name) (\(.version // "any"), policy=\(.policy)): " +
        (if .status == "available" then "✅ available" elif .policy == "block" then "❌ missing" else "⚠️ degraded" end) +
        "\n     missing: " + (if (.missing_skills | length) == 0 then "—" else (.missing_skills | join(", ")) end)) | join("\n")) end) as $preflight
    | ("🎯 Active stack profiles:\n" +
       "   primary:  \($stack.primary_profile.stack // "vanilla") (priority \($stack.primary_profile.priority // 0), from \($ep.primary.plugin)/stack.md)\n" +
       (["backend", "frontend", "database", "infra", "testing"] | map("   \(. + ":" | pad(9)) \($stack.active_profiles[.].stack // "—")") | join("\n")) +
       "\n   forced via --stack: \(if $stack.forced then "yes" else "no" end)" +
       (if $stack.source == "cache" then "\n   (🔧 Stack detection: cached (session start hook, \($stack.cache_age_minutes)m old))" else "" end)) as $stack_block
    | ($gf.prefix as $p | $gf.naming.separator as $sep | $gf.naming.word_separator as $ws
       | (if $gf.prefix_style == "none" then "{slug}" else "{prefix}\($sep // "/"){" + (if $gf.naming.ticket_pattern then "ticket}\($ws){" else "" end) + "slug}" end)) as $convention
    | ("🌿 Git flow\n" +
       "   Model:       \($gf.model) (confidence: \($gf.confidence) — \($gf.sources | join(", ")))\n" +
       "   Convention:  \($convention)  (learned from \($gf.branches_analyzed) branches)\n" +
       "   Task type:   \($gf.task_type) (\($gf.task_type_source)" + (if $gf.task_type_confidence == "medium" then ", runners-up: \($gf.task_type_runners_up | join(", "))" else "" end) + ")\n" +
       "   Current:     \($gf.current_branch // "(detached)")" + (if $gf.current_branch_is_base then " (base branch — a task branch is required)" else "" end) + "\n" +
       "   Proposed:    \($gf.branch_name)\n" +
       "   Branch from: \($gf.base_branch)\n" +
       "   PR base:     \($gf.pr_base_branch)\n" +
       "   Creation:    " + (if $gf.branch_creation_method == "git-flow-cli" then "git flow \($gf.native_subcommand) start" else "git checkout -b" end) +
       (if $gf.dirty_file_count > 0 then "\n   ⚠️  Uncommitted changes: \($gf.dirty_file_count) file(s) — they follow you onto the new branch" else "" end) +
       (if $gf.prefix_note then "\n   ℹ️  \($gf.prefix_note)" else "" end) +
       (if $gf.requires_back_merge then "\n   ↩️  Requires back-merge to \($gf.requires_back_merge) after the PR merges" else "" end)) as $git_block
    | ($gf.headless_decision | "GIT-FLOW: model=\(.model) confidence=\($gf.confidence) type=\($gf.task_type) branch=\(.branch_name) base=\(.base_branch // $gf.base_branch) pr_base=\(.pr_base_branch // $gf.pr_base_branch) action=\(.branch_action) creation=\(.branch_creation_method)" + (if .fallback then " fallback=\(.fallback)" else "" end)) as $headless_line
    | (if ($sr.skip_rules_applied | length) == 0 then ""
       else "✂️ Skip-rules applied:\n" + ($sr.skip_rules_applied | map("   \(.rule) → skipped \(.phase_skipped): \(.reason)") | join("\n")) end) as $skip_block
    | (if $wf.active_workflow == null then "" else
        "   workflow: \($wf.active_workflow)\(if $wf.project_local then " (project-local)" else "" end)  (\($wf.steps) steps after skips, selected by \($wf.workflow_selection_reason))" +
        (if ($wf.parallel_groups | length) > 0 then "\n   parallel: \($wf.parallel_groups | join(", "))" else "" end) end) as $workflow_line
    | {preflight: (if $headless then "" else $preflight end), stack: $stack_block, git_flow: $git_block,
       git_flow_headless_stderr: $headless_line, skip_rules: $skip_block, workflow: $workflow_line}')

# ---------------------------------------------------------------------------
# Emit
# ---------------------------------------------------------------------------

jq -cn --arg g "$generated_at" --arg repo "$repo_abs" --arg args "$arguments" --arg desc "$description" \
    --argjson flags "$flags_json" --arg slug "$task_slug" --arg lang "$narrative_language" --argjson headless "$headless" \
    --argjson state "$state_json" --argjson deps "$deps_json" --argjson stack "$stack_json" --argjson gf "$git_flow_json" \
    --argjson diff "$diff_json" --argjson sr "$skip_rules" --argjson local "$local_config" --argjson ep "$effective_profile" \
    --argjson wf "$workflow_json" --argjson pb "$print_blocks" --argjson warnings "$warnings" --argjson halts "$halts" '
    {schema_version: 1, generated_at: $g, repo: $repo,
     arguments: $args, description: $desc, flags: $flags,
     task_slug: $slug, narrative_language: $lang, headless_mode: $headless,
     state_file: $state,
     deps_preflight: $deps,
     stack: ($stack | del(.matched_profiles) + {matched_profiles: ($stack.matched_profiles // [] | map({stack, priority, aspects}))}),
     git_flow: ($gf | del(.detected_raw)),
     diff_signals: $diff,
     skip_rules: $sr,
     local_config: $local,
     effective_profile: $ep,
     workflow: ($wf | del(.warnings, .recipe_phases, .duplicate_phase)),
     print_blocks: $pb,
     warnings: $warnings,
     halts: $halts}'
exit 0
