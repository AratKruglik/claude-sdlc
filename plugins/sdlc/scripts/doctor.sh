#!/usr/bin/env bash
# Collects everything /sdlc:doctor reports and prints it — JSON with --json, the human
# table otherwise. Read-only, with one exception: it seeds <repo>/docs/cost-baseline.md from
# the plugin's template when that file is absent (create-if-absent, never an overwrite).
#
# Mirrors commands/doctor.md steps 1–9. Every sub-detector is the script the pipeline itself
# runs (deps-preflight.sh, detect-stack.sh, detect-git-flow.sh, usage-report.sh), always
# executed fresh: a doctor that echoed a cache could not diagnose a stale cache. Caches are
# read only to be compared against the fresh result.
#
# Usage: doctor.sh [--repo DIR] [--plugins-root DIR] [--dev-root DIR] [--json]
#
#   --plugins-root  Installed plugins. Default ~/.claude/plugins/cache.
#   --dev-root      Marketplace checkout; its plugins/ dir is used when the plugins root
#                   holds no sdlc plugin (running doctor from this repository).
#
# Exit codes: 0 normally; 1 only when a runtime-dependencies.json is malformed JSON;
#             2 usage error; 3 jq missing.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
MARKER_MAX_AGE_SECONDS=21600

repo="."
plugins_root="${HOME}/.claude/plugins/cache"
dev_root=""
json_out=false

while [ $# -gt 0 ]; do
    case "$1" in
        --repo)         repo="${2:-.}"; shift 2 ;;
        --plugins-root) plugins_root="${2:-}"; shift 2 ;;
        --dev-root)     dev_root="${2:-}"; shift 2 ;;
        --json)         json_out=true; shift ;;
        -h|--help)      sed -n '2,19p' "$0"; exit 0 ;;
        *)              echo "usage: doctor.sh [--repo DIR] [--plugins-root DIR] [--dev-root DIR] [--json]" >&2; exit 2 ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo '{"error":"jq is required"}'; exit 3; }

repo_abs=$(cd "$repo" 2>/dev/null && pwd -P) || repo_abs="$repo"
scan_root="$plugins_root"
if [ -z "$(find "$plugins_root" -name stack.md -type f 2>/dev/null | head -1)" ] && [ -n "$dev_root" ]; then
    scan_root="${dev_root%/plugins}/plugins"
    [ -d "$scan_root" ] || scan_root="$dev_root"
fi

now_epoch=$(date -u +%s)
iso_to_epoch() {
    local ts="$1" bsd
    bsd=$(printf '%s' "$ts" | sed -E 's/\.[0-9]+//; s/Z$/+0000/; s/([+-][0-9]{2}):([0-9]{2})$/\1\2/')
    date -u -d "$ts" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%S%z" "$bsd" +%s 2>/dev/null || echo ""
}

plugin_name_of_dir() {
    local base
    base=$(basename "$1")
    case "$base" in [0-9]*) basename "$(dirname "$1")" ;; *) printf '%s' "$base" ;; esac
}

# ── 1–2. dependencies ───────────────────────────────────────────────────────────────────────
while IFS= read -r f; do
    [ -n "$f" ] || continue
    jq -e . "$f" >/dev/null 2>&1 || { echo "{\"error\":\"malformed runtime-dependencies.json: $f\"}"; exit 1; }
done < <(find "$scan_root" -maxdepth 5 -name runtime-dependencies.json 2>/dev/null)
if [ -f "${SCRIPT_DIR}/deps-preflight.sh" ]; then
    deps=$(bash "${SCRIPT_DIR}/deps-preflight.sh" --plugins-root "$plugins_root" ${dev_root:+--dev-root "$dev_root"})
else
    deps='{"results":{},"all_satisfied":true,"dependencies":[],"security_guidance_available":false}'
fi
deps_preflight=$(jq -c '(.dependencies // []) | map({(.name): {status, policy, missing_skills: (.missing_skills // []), install_command: (.install_command // []), version: (.version // null)}}) | add // {}' <<<"$deps")
would_abort=$(jq -r '[(.dependencies // [])[] | select(.status == "missing" and .policy == "block")] | length > 0' <<<"$deps")

# ── 3. stack ────────────────────────────────────────────────────────────────────────────────
stack_fresh=$(bash "${SCRIPT_DIR}/detect-stack.sh" --repo "$repo" --plugins-root "$scan_root")
cache_dir="${CLAUDE_PLUGIN_DATA:+${CLAUDE_PLUGIN_DATA}/stack-cache}"
[ -n "$cache_dir" ] || cache_dir="${HOME}/.claude/.sdlc-stack-cache"
if command -v shasum >/dev/null 2>&1; then digest=$(printf '%s' "$repo_abs" | shasum -a 1 | cut -c1-16)
elif command -v sha1sum >/dev/null 2>&1; then digest=$(printf '%s' "$repo_abs" | sha1sum | cut -c1-16)
else digest=""; fi
stack_cache='{"present":false,"age_seconds":null,"cached_primary":null,"agrees_with_fresh_detection":null}'
if [ -n "$digest" ] && [ -f "${cache_dir}/${digest}.json" ]; then
    cached=$(cat "${cache_dir}/${digest}.json" 2>/dev/null)
    if jq -e . <<<"$cached" >/dev/null 2>&1; then
        cached_at=$(iso_to_epoch "$(jq -r '.detected_at // empty' <<<"$cached")")
        age=null; [ -n "$cached_at" ] && age=$((now_epoch - cached_at))
        stack_cache=$(jq -cn --argjson age "$age" --argjson c "$cached" --argjson f "$stack_fresh" '
            {present: true, age_seconds: $age, cached_primary: ($c.primary_profile.stack // null),
             agrees_with_fresh_detection: (($c.primary_profile.stack // null) == ($f.primary_profile.stack // null) and ($c.aspect_ties // {}) == ($f.aspect_ties // {}))}')
    fi
fi
stack_json=$(jq -cn --argjson f "$stack_fresh" --argjson c "$stack_cache" '
    {active_profile: ($f.primary_profile.stack // null), primary_priority: ($f.primary_profile.priority // null),
     profile_source: ($f.primary_profile.source // null),
     all_installed: ($f.all_profiles // [] | map(.stack)), active_profiles: $f.active_profiles,
     aspect_ties: $f.aspect_ties, project_shape: ($f.project_shape // null), session_cache: $c}')

# ── 4. cost baseline ────────────────────────────────────────────────────────────────────────
baseline="${repo}/docs/cost-baseline.md"
baseline_seeded=false
if [ ! -f "$baseline" ] && [ -f "${PLUGIN_DIR}/templates/cost-baseline.md" ]; then
    mkdir -p "${repo}/docs" 2>/dev/null && cp "${PLUGIN_DIR}/templates/cost-baseline.md" "$baseline" 2>/dev/null && baseline_seeded=true
fi
cost_baseline='{"available":false,"runs_aggregated":null,"avg_cost_per_medium_run_usd":null,"p90_cost_per_medium_run_usd":null,"cache_hit_ratio":null,"cost_scope":null,"last_updated":null,"seeded":false,"file_present":false}'
if [ -f "$baseline" ]; then
    summary=$(awk '/^```json summary/ { inb = 1; next } inb && /^```/ { exit } inb { print }' "$baseline")
    if [ -n "$summary" ] && jq -e . <<<"$summary" >/dev/null 2>&1; then
        cost_baseline=$(jq -c --argjson seeded "$baseline_seeded" '
            {available: ((.runs_aggregated // 0) > 0), runs_aggregated: (.runs_aggregated // 0),
             avg_cost_per_medium_run_usd, p90_cost_per_medium_run_usd, cache_hit_ratio,
             cost_scope: (.cost_scope // "subagent_phases_only"), last_updated, seeded: $seeded, file_present: true}' <<<"$summary")
    else
        cost_baseline=$(jq -c --argjson seeded "$baseline_seeded" '.file_present = true | .seeded = $seeded' <<<"$cost_baseline")
    fi
fi

# ── 5. model routing ────────────────────────────────────────────────────────────────────────
# Agent names from the primary profile's "## Agents per phase" section, in either the
# `- phase: agent` list form or the fenced-yaml form with aspect sub-keys.
profile_agents() {
    local file="$1"
    awk '/^## Agents per phase/ { inb = 1; next } inb && /^## / { exit } inb { print }' "$file" \
        | sed -nE 's/^[-[:space:]]*[a-z_]+:[[:space:]]*([a-z][a-z0-9-]*)[[:space:]]*(#.*)?$/\1/p' \
        | grep -Ev '^(backend|frontend|database|infra|testing|messaging)$' | sort -u
}
profile_roles() {
    local file="$1"
    awk '/^## Agents per phase/ { inb = 1; next } inb && /^## / { exit } inb { print }' "$file" \
        | sed -nE 's/^[-[:space:]]*([a-z_]+):[[:space:]]*([a-z][a-z0-9-]*)?[[:space:]]*(#.*)?$/\1=\2/p' \
        | awk -F= '
            $1 ~ /^(backend|frontend|database|infra|testing|messaging)$/ { if (phase != "" && $2 != "") print phase "=" $2; next }
            { phase = $1; if ($2 != "") print $1 "=" $2 }'
}
primary_source=$(jq -r '.primary_profile.source // empty' <<<"$stack_fresh")
agents='[]'
roles='[]'
if [ -n "$primary_source" ] && [ -f "${scan_root}/${primary_source}" ]; then
    agents=$(profile_agents "${scan_root}/${primary_source}" | jq -R . | jq -sc .)
    roles=$(profile_roles "${scan_root}/${primary_source}" | jq -R 'split("=") | {role: .[0], agent: .[1]}' | jq -sc .)
    while IFS= read -r src; do
        [ -n "$src" ] && [ -f "${scan_root}/${src}" ] || continue
        extra=$(profile_agents "${scan_root}/${src}" | jq -R . | jq -sc .)
        agents=$(jq -cn --argjson a "$agents" --argjson b "$extra" '$a + $b | unique')
    done < <(jq -r '.active_profiles | to_entries[] | .value.source // empty' <<<"$stack_fresh" | sort -u)
fi
fm_value() {
    awk 'NR == 1 && $0 != "---" { exit } NR == 1 { next } /^---[[:space:]]*$/ { exit } { print }' "$1" \
        | awk -v k="^$2:" '$0 ~ k { sub(/^[^:]*:[[:space:]]*/, ""); gsub(/["\x27 \r]/, ""); print; exit }'
}
declared='{}'
for agent in $(jq -r '.[]' <<<"$agents"); do
    file=$(find "$scan_root" -maxdepth 5 -path "*/agents/${agent}.md" 2>/dev/null | sort -r | head -1)
    if [ -n "$file" ]; then
        model=$(fm_value "$file" model); plan=$(fm_value "$file" model_plan)
        declared=$(jq -c --arg a "$agent" --arg m "$model" --arg p "$plan" \
            '.[$a] = ({model: (if $m == "" then null else $m end)} + (if $p == "" then {} else {model_plan: $p} end))' <<<"$declared")
    else
        declared=$(jq -c --arg a "$agent" '.[$a] = {model: null, missing: true}' <<<"$declared")
    fi
done
force="${CLAUDE_CODE_SUBAGENT_MODEL_FORCE:-}"
override="${CLAUDE_CODE_SUBAGENT_MODEL:-}"
[ "$override" = "inherit" ] && override=""
plugin_options=$(jq -cn \
    --arg ni "${CLAUDE_PLUGIN_OPTION_NONINTERACTIVE:-}" --arg cap "${CLAUDE_PLUGIN_OPTION_DEFAULT_COST_CAP_USD:-}" \
    --arg ttl "${CLAUDE_PLUGIN_OPTION_STACK_CACHE_TTL_HOURS:-}" --arg fix "${CLAUDE_PLUGIN_OPTION_POST_CHECK_FIX_ATTEMPTS:-}" \
    --arg env_ni "${SDLC_NONINTERACTIVE:-}" '
    def v: if . == "" then "default" else . end;
    {noninteractive: ($ni | v), default_cost_cap_usd: ($cap | v), stack_cache_ttl_hours: ($ttl | v),
     post_check_fix_attempts: ($fix | v), sdlc_noninteractive_env: (if $env_ni == "" then null else $env_ni end),
     noninteractive_overridden_by_env: ($env_ni != "" and $ni != "")}')
model_routing=$(jq -cn --arg o "$override" --arg f "$force" --argjson d "$declared" --argjson po "$plugin_options" '
    {subagent_model_override: (if $o == "" then null else $o end), subagent_model_force: ($f == "1"),
     override_active: ($f == "1"), declared_tiers: $d, plugin_options: $po}')

# ── 6. shadowing + run marker ───────────────────────────────────────────────────────────────
shadowing='[]'
for dir in "${repo}/.claude/agents" "${HOME}/.claude/agents"; do
    [ -d "$dir" ] || continue
    for f in "$dir"/*.md; do
        [ -f "$f" ] || continue
        name=$(basename "$f" .md)
        hit=$(jq -r --arg n "$name" '.[] | select(. == $n)' <<<"$agents")
        role=""
        if [ -z "$hit" ]; then
            case "$name" in
                developer|dev|architect) role=development ;;
                qa|tester|test|qa-engineer) role=qa ;;
                security|security-reviewer) role=security ;;
                docs|writer|documenter) role=documentation ;;
                ba|analyst) role=business_analysis ;;
            esac
            [ -n "$role" ] && hit=$(jq -r --arg r "$role" '.[] | select(.role == $r) | .agent' <<<"$roles" | head -1)
        fi
        [ -n "$hit" ] || continue
        rel="$f"; case "$f" in "${repo}"/*) rel="${f#"${repo}"/}" ;; "${HOME}"/*) rel="\$HOME/${f#"${HOME}"/}" ;; esac
        shadowing=$(jq -c --arg p "$rel" --arg s "$hit" --arg r "${role:-$name}" '. + [{path: $p, shadows: $s, profile_role: $r}]' <<<"$shadowing")
    done
done

marker="${repo}/.claude/.sdlc-run-active.json"
run_marker='{"present":false,"schema_version":null,"stale":null,"resumable":null,"task_slug":null,"started_at":null,"updated_at":null,"age_seconds":null,"resume_count":null,"phase_status":null,"completed_steps":null,"total_steps":null}'
if [ -f "$marker" ] && state=$(cat "$marker" 2>/dev/null) && jq -e . <<<"$state" >/dev/null 2>&1; then
    ts=$(jq -r '.updated_at // .started_at // empty' <<<"$state")
    ep=$(iso_to_epoch "$ts"); age=null; [ -n "$ep" ] && age=$((now_epoch - ep))
    run_marker=$(jq -cn --argjson s "$state" --argjson age "$age" --argjson max "$MARKER_MAX_AGE_SECONDS" '
        ($s.phase_status // null) as $ps
        | {present: true, schema_version: ($s.schema_version // null),
           stale: (if $age == null then null else $age >= $max end),
           resumable: (($s.schema_version // 0) >= 2), task_slug: ($s.task_slug // null),
           started_at: ($s.started_at // null), updated_at: ($s.updated_at // null), age_seconds: $age,
           resume_count: ($s.resume_count // null), phase_status: $ps,
           completed_steps: (if $ps == null then null else [$ps[] | select(. == "completed" or . == "skipped" or . == "skipped-cost-cap")] | length end),
           total_steps: (if $ps == null then null else ($ps | length) end)}')
fi

# ── 7. dispatch telemetry ───────────────────────────────────────────────────────────────────
sdlc_hooks="${PLUGIN_DIR}/hooks/hooks.json"
hooks_registered=false
events='[]'
if [ -f "$sdlc_hooks" ]; then
    events=$(jq -c '.hooks | keys' "$sdlc_hooks")
    hooks_registered=$(jq -r '
        (.hooks.SubagentStart // [] | map(.hooks[].command) | any(test("dispatch-log"))) and
        (.hooks.SubagentStop  // [] | map(.hooks[].command) | any(test("subagent-usage")))' "$sdlc_hooks")
fi
precommit=$(jq -r '.hooks.PreToolUse // [] | map(select(.matcher == "Bash") | .hooks[].command) | any(test("pre-commit-guard"))' "$sdlc_hooks" 2>/dev/null || echo false)
json_tool=neither; command -v jq >/dev/null 2>&1 && json_tool=jq
run_armed=$(jq -r 'if .present and .stale == false then true else false end' <<<"$run_marker")
guards='[]'
seen_guard_plugins=" "
while IFS= read -r hj; do
    [ -n "$hj" ] || continue
    pdir=$(dirname "$(dirname "$hj")")
    [ -f "${pdir}/stack.md" ] || continue
    pname=$(plugin_name_of_dir "$pdir")
    [ "$pname" = "sdlc" ] && continue
    case "$seen_guard_plugins" in *" ${pname} "*) continue ;; esac
    seen_guard_plugins="${seen_guard_plugins}${pname} "
    globs=$(jq -r '[.hooks.PreToolUse // [] | .[] | .hooks[].command | select(test("config-protection")) | capture("exec bash \"\\$s\" (?<args>[^;]*);").args] | .[0] // ""' "$hj" 2>/dev/null | tr -d "'" )
    check=$(jq -r '[.hooks.SubagentStop // [] | .[] | .hooks[].command | select(test("post-implement-check")) | capture("exec bash \"\\$s\" (?<args>[^;]*);").args] | .[0] // ""' "$hj" 2>/dev/null | sed -E "s/^(--lang [^ ]+ )?(--service-hint [^ ]+ )?-- //")
    matcher=$(jq -r '[.hooks.SubagentStop // [] | .[] | .matcher // ""] | .[0] // ""' "$hj" 2>/dev/null)
    resolves=false
    if [ -n "$check" ]; then
        first=${check%% *}
        (cd "$repo" 2>/dev/null && command -v "$first" >/dev/null 2>&1) && resolves=true
    fi
    guards=$(jq -c --arg p "$pname" --arg g "$globs" --arg c "$check" --arg m "$matcher" --argjson r "$resolves" --argjson a "$run_armed" '
        . + [{plugin: $p, protected_globs: ($g | split(" ") | map(select(. != ""))), post_implement_check: (if $c == "" then null else $c end),
              architect_matcher: (if $m == "" then null else $m end), check_resolves_in_project: $r, armed: $a}]' <<<"$guards")
done < <(find "$scan_root" -maxdepth 5 -path '*/hooks/hooks.json' 2>/dev/null | sort)
last_run=null
newest=$(ls -t "${repo}"/docs/plans/*/_usage.jsonl 2>/dev/null | head -1)
if [ -n "$newest" ]; then
    slug=$(basename "$(dirname "$newest")")
    report=$(bash "${SCRIPT_DIR}/usage-report.sh" "$slug" --project-root "$repo" 2>/dev/null)
    jq -e . <<<"$report" >/dev/null 2>&1 && last_run=$(jq -c '
        {task_slug, dispatches: (.dispatches | length), usage_source_summary, total_cost_usd, nested_cost_usd,
         unknown_model_ids: ([.dispatches[] | select(.pricing_note == "unknown model") | .model] | unique)}' <<<"$report")
fi
dispatch_telemetry=$(jq -cn --argjson hr "$hooks_registered" --argjson ev "$events" --arg jt "$json_tool" --argjson pc "$precommit" \
    --argjson g "$guards" --argjson lr "$last_run" --argjson armed "$run_armed" '
    {hooks_registered: $hr, events_registered: $ev, json_tool: $jt, pre_commit_guard_registered: $pc, guards_armed: $armed, stack_guards: $g, last_run: $lr}')

# ── 8. git flow ─────────────────────────────────────────────────────────────────────────────
detected=$(bash "${SCRIPT_DIR}/detect-git-flow.sh" --repo "$repo" 2>/dev/null)
jq -e . <<<"$detected" >/dev/null 2>&1 || detected='{"model":"unknown","confidence":"low"}'
local_yaml="${repo}/.claude/sdlc.local.yaml"
config_keys='[]'
config_model=""
if [ -f "$local_yaml" ]; then
    git_block=$(awk '/^git:[[:space:]]*$/ { inb = 1; next } inb && /^[^[:space:]]/ { exit } inb { print }' "$local_yaml")
    config_keys=$(printf '%s\n' "$git_block" | sed -nE 's/^  ([a-z_]+):.*$/\1/p' | jq -R . | jq -sc .)
    config_model=$(printf '%s\n' "$git_block" | sed -nE 's/^  model:[[:space:]]*([a-z-]+).*$/\1/p' | head -1)
fi
documented='[]'
for cand in CLAUDE.md .claude/CLAUDE.md AGENTS.md GEMINI.md CONTRIBUTING.md .cursorrules .github/pull_request_template.md .github/PULL_REQUEST_TEMPLATE.md; do
    [ -f "${repo}/${cand}" ] || continue
    states=false
    grep -Eiq 'git[- ]flow|github[- ]flow|trunk[- ]based|branch(es)? (off|from) (develop|main|master)|branches? must|feature/<|feature/\{|naming convention.*branch|branch.*naming convention' "${repo}/${cand}" 2>/dev/null && states=true
    documented=$(jq -c --arg p "$cand" --argjson s "$states" '. + [{path: $p, states_convention: $s}]' <<<"$documented")
done
for cand in "${repo}"/.claude/rules/*.md "${repo}"/.cursor/rules/*; do
    [ -f "$cand" ] || continue
    states=false
    grep -Eiq 'git[- ]flow|github[- ]flow|trunk[- ]based|branch(es)? (off|from) (develop|main|master)|branches? must' "$cand" 2>/dev/null && states=true
    documented=$(jq -c --arg p "${cand#"${repo}"/}" --argjson s "$states" '. + [{path: $p, states_convention: $s}]' <<<"$documented")
done
gf_cache="${repo}/.claude/.sdlc-git-flow.json"
cache_json='{"present":false,"user_confirmed":null,"stale":null,"disagrees_with_detection":null,"detected_at":null,"model":null}'
if [ -f "$gf_cache" ] && cached=$(cat "$gf_cache" 2>/dev/null) && jq -e . <<<"$cached" >/dev/null 2>&1; then
    cep=$(iso_to_epoch "$(jq -r '.detected_at // empty' <<<"$cached")")
    cstale=null; [ -n "$cep" ] && { [ $((now_epoch - cep)) -ge 2592000 ] && cstale=true || cstale=false; }
    cache_json=$(jq -cn --argjson c "$cached" --argjson d "$detected" --argjson stale "$cstale" '
        {present: true, user_confirmed: ($c.user_confirmed // null), stale: $stale,
         disagrees_with_detection: (($c.model // null) != ($d.model // null)), detected_at: ($c.detected_at // null), model: ($c.model // null)}')
fi
git_flow=$(jq -cn --argjson d "$detected" --argjson keys "$config_keys" --arg cm "$config_model" --argjson doc "$documented" --argjson c "$cache_json" '
    ($d.model == "git-flow" and ($d.git_flow_cli_available // false) and ($d.git_flow_initialized // false)) as $cli
    | ($doc | map(select(.states_convention)) | length > 0) as $rules
    | {source: (if ($keys | length) > 0 then "config" else "detection" end), config_override_keys: $keys,
       config_model: (if $cm == "" then null else $cm end), detected: $d,
       branch_creation_method: (if $cli then "git-flow-cli" else "checkout-b" end),
       documented_conventions: $doc,
       topology_conflict: (if $rules and ($cm != "" and $cm != $d.model) then "config says \($cm), topology says \($d.model)" else null end),
       cache: $c}')

# ── 9. assemble ─────────────────────────────────────────────────────────────────────────────
doc=$(jq -cn --argjson dp "$deps_preflight" --argjson st "$stack_json" --argjson cb "$cost_baseline" --argjson mr "$model_routing" \
    --argjson sh "$shadowing" --argjson rm "$run_marker" --argjson dt "$dispatch_telemetry" --argjson gf "$git_flow" \
    --argjson wa "$would_abort" --argjson sg "$(jq -c '.security_guidance_available // false' <<<"$deps")" '
    {deps_preflight: $dp, security_guidance_available: $sg, stack: $st, cost_baseline: $cb, model_routing: $mr,
     local_agent_shadowing: $sh, run_marker: $rm, dispatch_telemetry: $dt, git_flow: $gf, would_abort_pipeline: $wa}')

if [ "$json_out" = true ]; then
    jq . <<<"$doc"
    exit 0
fi

# ── human rendering ─────────────────────────────────────────────────────────────────────────
age_text() {
    local s="$1"
    [ "$s" = null ] && { printf '?'; return; }
    if [ "$s" -ge 3600 ]; then printf '%dh' $((s / 3600)); else printf '%dm' $((s / 60)); fi
}

echo "🩺 SDLC Doctor"
echo
echo "Dependencies (from runtime-dependencies.json):"
if [ "$(jq -r 'length' <<<"$deps_preflight")" = "0" ]; then
    echo "  🔌 no external dependencies declared."
else
    jq -r 'to_entries[] | .key as $n | .value
        | "  \($n) \(.version // "") [policy=\(.policy)]\n    status: \(if .status == "available" then "✅ available" else "❌ missing" end)"
          + (if (.missing_skills | length) > 0 then "\n    missing skills: \(.missing_skills | join(", "))" else "" end)
          + (if .status != "available" and (.install_command | length) > 0 then "\n    install:\n" + (.install_command | map("      " + .) | join("\n")) else "" end)
          + "\n"' <<<"$deps_preflight"
fi

echo "Stack profiles:"
jq -r '
    (if .active_profile then "  🎯 active: \(.active_profile) (priority=\(.primary_priority), from \(.profile_source))" else "  🎯 active: none matched" end),
    "  also installed: \((.all_installed | map(select(. != $a)) | join(", ")) // "—")",
    (if .session_cache.present | not then "  session cache: absent — /sdlc:start will run a full scan"
     elif .session_cache.agrees_with_fresh_detection then "  session cache: fresh (written \(.session_cache.age_seconds / 60 | floor)m ago by SessionStart hook) — /sdlc:start will use it"
     else "  ⚠️  session cache disagrees with fresh detection: cached=\(.session_cache.cached_primary), detected=\(.active_profile) — run /sdlc:start --redetect-stack" end),
    (.aspect_ties | to_entries[] | "  ⚠️  aspect \(.key): tie between \(.value | join(", ")) — /sdlc:start will HALT; use --stack=NAME"),
    "  project shape: pm=\(.project_shape.package_manager // "—") test=\(.project_shape.test_command // "—") typecheck=\(.project_shape.typecheck_command // "—") framework=\(.project_shape.test_framework // "—")"
' --arg a "$(jq -r '.active_profile // ""' <<<"$stack_json")" <<<"$stack_json"
echo

if [ "$(jq -r '.file_present' <<<"$cost_baseline")" = true ]; then
    echo "Cost baseline (docs/cost-baseline.md, last updated $(jq -r '.last_updated // "never"' <<<"$cost_baseline"), $(jq -r '.runs_aggregated // 0' <<<"$cost_baseline") runs):"
    [ "$(jq -r '.seeded' <<<"$cost_baseline")" = true ] && echo "  seeded from the plugin template just now — not yet baselined"
    jq -r '"  avg medium-run: \(if .avg_cost_per_medium_run_usd then "$" + (.avg_cost_per_medium_run_usd | tostring) else "—" end)",
           "  p90 medium-run: \(if .p90_cost_per_medium_run_usd then "$" + (.p90_cost_per_medium_run_usd | tostring) else "—" end)",
           "  cache hit ratio: \(.cache_hit_ratio // "—")",
           "  note: subagent phases only — orchestrator overhead is not metered"' <<<"$cost_baseline"
else
    echo "Cost baseline: no baseline file and no template found"
fi
echo

echo "Model routing:"
if [ "$(jq -r '.override_active' <<<"$model_routing")" = true ]; then
    echo "  ⚠️  CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 — OVERRIDES all model enforcement."
    echo "      Every phase will run on $(jq -r '.subagent_model_override // "the session model"' <<<"$model_routing") regardless of"
    echo "      agent frontmatter. Cost estimates in README/telemetry do not apply."
else
    echo "  ✅ no routing override"
    o=$(jq -r '.subagent_model_override // empty' <<<"$model_routing")
    [ -n "$o" ] && echo "  ℹ️  CLAUDE_CODE_SUBAGENT_MODEL=${o} — informational; it does not override the parameter or frontmatter on its own"
fi
echo "  declared tiers for active profile ($(jq -r '.active_profile // "none"' <<<"$stack_json")):"
jq -r '.declared_tiers | to_entries[] | "    \(.key | . + (" " * (20 - length | if . < 1 then 1 else . end)))\(if .value.missing then "⚠️  agent file not found" elif .value.model_plan then "\(.value.model_plan) (plan) / \(.value.model) (implement)" else (.value.model // "—") end)"' <<<"$model_routing"
echo "  plugin options:"
jq -r '.plugin_options | "    noninteractive=\(.noninteractive) default_cost_cap_usd=\(.default_cost_cap_usd) stack_cache_ttl_hours=\(.stack_cache_ttl_hours) post_check_fix_attempts=\(.post_check_fix_attempts)"
        + (if .noninteractive_overridden_by_env then "\n    ⚠️  SDLC_NONINTERACTIVE=\(.sdlc_noninteractive_env) in the environment overrides the noninteractive option" else "" end)' <<<"$model_routing"
echo

echo "Local-agent shadowing:"
if [ "$(jq -r 'length' <<<"$shadowing")" = "0" ]; then
    echo "  ✅ no local-agent shadowing detected"
else
    jq -r '.[] | "  ⚠️  \(.path) shadows profile agent \"\(.shadows)\" (as role \"\(.profile_role)\")"' <<<"$shadowing"
    echo "  (dispatch already qualifies subagent_type as \"{plugin}:{agent}\" — these are informational"
    echo "   unless something dispatches the bare name)"
fi
echo

echo "Run marker:"
if [ "$(jq -r '.present' <<<"$run_marker")" != true ]; then
    echo "  ✅ no .claude/.sdlc-run-active.json present"
else
    slug=$(jq -r '.task_slug // "?"' <<<"$run_marker"); age=$(jq -r '.age_seconds' <<<"$run_marker")
    done_n=$(jq -r '.completed_steps // "?"' <<<"$run_marker"); total_n=$(jq -r '.total_steps // "?"' <<<"$run_marker")
    if [ "$(jq -r '.stale' <<<"$run_marker")" = false ]; then
        echo "  🏃 run \"${slug}\" active (started $(age_text "$(( now_epoch - $(iso_to_epoch "$(jq -r '.started_at' <<<"$run_marker")") ))") ago, last update $(age_text "$age") ago, ${done_n}/${total_n} phase steps) — /sdlc:start will offer to resume it"
    elif [ "$(jq -r '.resumable' <<<"$run_marker")" = true ]; then
        echo "  ⚠️  interrupted run \"${slug}\" (last update $(age_text "$age") ago, ${done_n}/${total_n} phase steps) — resumable with: /sdlc:start --resume   (or discard: rm .claude/.sdlc-run-active.json)"
    else
        echo "  ⚠️  stale pre-2.0 run marker (started $(age_text "$age") ago, task_slug=${slug}) — not resumable. Remove with: rm .claude/.sdlc-run-active.json"
    fi
fi
echo

echo "Dispatch telemetry:"
if [ "$(jq -r '.hooks_registered' <<<"$dispatch_telemetry")" = true ]; then
    echo "  hooks: ✅ SubagentStart + SubagentStop registered ($(jq -r '.json_tool' <<<"$dispatch_telemetry") available) — events: $(jq -r '.events_registered | join(", ")' <<<"$dispatch_telemetry")"
else
    echo "  hooks: ❌ dispatch-log.sh / subagent-usage.sh not registered in hooks/hooks.json — every run will be estimated"
fi
armed_text="inert (no active run)"; [ "$run_armed" = true ] && armed_text="armed (run active)"
echo "  guards: $(if [ "$precommit" = true ]; then printf '✅'; else printf '❌'; fi) pre-commit — ${armed_text}"
jq -r '.stack_guards[] | "    \(.plugin): config-protection (\(.protected_globs | join(", ") | if . == "" then "—" else . end)), post-implement (\(.post_implement_check // "—"))\(if .post_implement_check and (.check_resolves_in_project | not) then " — not resolvable here, check silently skipped" else "" end)"' <<<"$dispatch_telemetry"
if [ "$(jq -r '.last_run' <<<"$dispatch_telemetry")" = null ]; then
    echo "  last run: none — no docs/plans/*/_usage.jsonl in this project"
else
    jq -r '.last_run | "  last run: \(.task_slug) — \(.dispatches) dispatches, measured=\(.usage_source_summary.measured) unmeasured=\(.usage_source_summary.unmeasured) not_started=\(.usage_source_summary.not_started)\n    total $\(.total_cost_usd) (phases) + $\(.nested_cost_usd) nested; "
        + (if (.unknown_model_ids | length) > 0 then "⚠️  \(.unknown_model_ids | length) model id(s) missing from references/pricing.json: \(.unknown_model_ids | join(", "))" else "no unknown model ids" end)' <<<"$dispatch_telemetry"
fi
echo

echo "Git flow:"
jq -r '
    (if .source == "config" then "  ⚠️  config overrides detection: model=\(.config_model // "detected") (keys: \(.config_override_keys | join(", ")))" else "  source: detection (no `git:` block in .claude/sdlc.local.yaml)" end),
    (if .detected.model == "unknown" then "  ⚠️  model=unknown — no commits or branches; /sdlc:start will not create a branch"
     else "  🎯 model: \(.detected.model) (confidence=\(.detected.confidence)) — \(.detected.sources // [] | join(", "))" end),
    "  branches: default=\(.detected.default_branch // "—"), develop=\(.detected.develop_branch // "—"), release=\(.detected.release_branches // [] | if length == 0 then "—" else join(", ") end)",
    "  convention: separator=\(.detected.naming.separator // "—")  word_separator=\(.detected.naming.word_separator // "—")  ticket=\(.detected.naming.ticket_pattern // "—")",
    "    observed prefixes: \(.detected.prefix_histogram // {} | to_entries | map("\(.key)=\(.value)") | join(", ") | if . == "" then "none" else . end)",
    "  documented conventions: \(.documented_conventions | if length == 0 then "none of the Step B files exist" else map("\(.path) (\(if .states_convention then "states a convention" else "no branch statement" end))") | join(", ") end)",
    (if .topology_conflict then "  ⚠️  rules/topology conflict: \(.topology_conflict)" else empty end),
    (if .cache.present | not then "  cache: .claude/.sdlc-git-flow.json absent — next /sdlc:start will detect and ask"
     elif .cache.disagrees_with_detection then "  ⚠️  cache disagrees with fresh detection: cached=\(.cache.model), detected=\(.detected.model) — run /sdlc:start --redetect-git-flow"
     elif .cache.stale then "  cache: stale (detected \(.cache.detected_at)) — will be re-detected"
     elif .cache.user_confirmed | not then "  cache: present but unconfirmed — next interactive run re-asks"
     else "  cache: fresh and confirmed (\(.cache.detected_at))" end),
    "  creation method: \(if .branch_creation_method == "git-flow-cli" then "git flow {subcommand} start" else "git checkout -b" end)"
      + (if .detected.model == "git-flow" and (.detected.git_flow_cli_available | not) then "\n  ⚠️  model=git-flow but git-flow CLI unavailable — falling back to git checkout -b. Install git-flow (AVH edition) to use \"git flow {subcommand} start\"."
         elif .detected.model == "git-flow" and (.detected.git_flow_initialized | not) then "\n  ⚠️  model=git-flow but repo not initialized (no gitflow.branch.master/develop) — falling back to git checkout -b. Run \"git flow init\" to use the CLI path."
         else "" end)
' <<<"$git_flow"
echo

echo "Heads-up:"
heads=0
if [ "$would_abort" = true ]; then
    echo "  ❌ blocking dependency missing — /sdlc:start would abort. Run the install commands above, then retry."; heads=$((heads + 1))
fi
if [ "$(jq -r '.override_active' <<<"$model_routing")" = true ]; then
    echo "  ⚠️  model routing override active — cost estimates do not apply."; heads=$((heads + 1))
fi
if [ "$(jq -r '.session_cache.present and (.session_cache.agrees_with_fresh_detection | not)' <<<"$stack_json")" = true ]; then
    echo "  ⚠️  stale stack cache — /sdlc:start --redetect-stack."; heads=$((heads + 1))
fi
if [ "$(jq -r '.cache.present and .cache.disagrees_with_detection' <<<"$git_flow")" = true ]; then
    echo "  ⚠️  stale git-flow cache — /sdlc:start --redetect-git-flow."; heads=$((heads + 1))
fi
[ "$heads" -eq 0 ] && echo "  ✅ nothing blocking — /sdlc:start can run."
exit 0
