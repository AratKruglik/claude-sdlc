#!/usr/bin/env bash
# Assemble docs/plans/{task_slug}/_telemetry.json (pipeline-orchestrator Step 5) from what is
# already on disk, and print the final summary block so the orchestrator only echoes it.
#
# Sources, in merge order (later wins):
#   1. usage-report.sh     — one phases[] entry per non-nested dispatch, priced and mapped
#                            exactly as Step 3d-1 describes (input_tokens is the total input
#                            the API saw; cached_input_tokens is cache_read_input_tokens).
#   2. the run state file  — .claude/.sdlc-run-active.json: git_flow, stack, workflow, skips,
#                            phase_status (→ phases[].status), resume_count, started_at.
#   3. deps-preflight cache — ${CLAUDE_PLUGIN_DATA}/deps-preflight.json, else
#                            ~/.claude/.sdlc-deps-preflight.json.
#   4. 05-post-checks.md   — a fenced ```json post-checks block holding [{command, exit_code}].
#   5. --extra JSON        — deep-merged last, for values only the orchestrator knows
#                            (pr_url, model_enforcement_corrections, post_check_fix_* ...).
#
# Model tiers come from the dispatched agent's frontmatter (`model:`, or `model_plan:` for a
# [pass:plan] dispatch), looked up under --plugins-root and the dev checkout this script
# lives in. A measured row whose model id pricing.json does not know is priced from that tier
# and keeps its pricing_note, so a confident wrong number is never written silently.
#
# Never deletes the state file — the orchestrator is its single writer. Exit codes: 0 for any
# readable-or-absent input (partial data is written, not raised); 2 usage; 3 jq missing.
#
# Usage: finalize-telemetry.sh TASK_SLUG [--project-root DIR] [--plugins-root DIR]
#                              [--completed-at ISO] [--aborted-at-phase NAME] [--extra JSON]
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRICING="${SDLC_PRICING_FILE:-${SCRIPT_DIR}/../references/pricing.json}"

usage() {
    echo "usage: finalize-telemetry.sh TASK_SLUG [--project-root DIR] [--plugins-root DIR] [--completed-at ISO] [--aborted-at-phase NAME] [--extra JSON]"
}

slug=""; root="."; plugins_root="${HOME}/.claude/plugins/cache"
completed_at=""; aborted_at=""; extra='{}'
while [ $# -gt 0 ]; do
    case "$1" in
        --project-root)     root="${2:-}"; shift 2 ;;
        --plugins-root)     plugins_root="${2:-}"; shift 2 ;;
        --completed-at)     completed_at="${2:-}"; shift 2 ;;
        --aborted-at-phase) aborted_at="${2:-}"; shift 2 ;;
        --extra)            extra="${2:-{\}}"; shift 2 ;;
        -h|--help)          usage; exit 0 ;;
        -*)                 usage >&2; exit 2 ;;
        *)                  slug="$1"; shift ;;
    esac
done
[ -n "$slug" ] || { usage >&2; exit 2; }

if ! command -v jq >/dev/null 2>&1; then
    printf '{"error":"jq is required to finalize telemetry","task_slug":"%s"}\n' "$slug"
    exit 3
fi
printf '%s' "$extra" | jq -e 'type == "object"' >/dev/null 2>&1 || { echo "error: --extra must be a JSON object" >&2; exit 2; }

[ -n "$completed_at" ] || completed_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
plan_dir="${root}/docs/plans/${slug}"
mkdir -p "$plan_dir" 2>/dev/null

# ── usage report ──────────────────────────────────────────────────────────
report='{}'
if [ -f "${SCRIPT_DIR}/usage-report.sh" ]; then
    report=$(bash "${SCRIPT_DIR}/usage-report.sh" "$slug" --project-root "$root" 2>/dev/null) || report='{}'
fi
printf '%s' "$report" | jq -e 'type == "object"' >/dev/null 2>&1 || report='{}'

# ── state file ────────────────────────────────────────────────────────────
state='{}'
if [ -f "${root}/.claude/.sdlc-run-active.json" ]; then
    state=$(jq -c . "${root}/.claude/.sdlc-run-active.json" 2>/dev/null) || state='{}'
fi

# ── deps preflight cache ──────────────────────────────────────────────────
deps='{}'
deps_file="${CLAUDE_PLUGIN_DATA:+${CLAUDE_PLUGIN_DATA}/deps-preflight.json}"
[ -n "$deps_file" ] && [ -f "$deps_file" ] || deps_file="${HOME}/.claude/.sdlc-deps-preflight.json"
if [ -f "$deps_file" ]; then
    deps=$(jq -c '(.results // {}) | with_entries(.value = {status: .value, missing_skills: []})' "$deps_file" 2>/dev/null) || deps='{}'
fi

# ── post-pipeline checks ──────────────────────────────────────────────────
post_checks='[]'
if [ -f "${plan_dir}/05-post-checks.md" ]; then
    block=$(awk '
        /^```json[[:space:]]+post-checks[[:space:]]*$/ { inside = 1; next }
        inside && /^```/ { exit }
        inside { print }
    ' "${plan_dir}/05-post-checks.md")
    if [ -n "$block" ]; then
        post_checks=$(printf '%s' "$block" | jq -c 'if type == "array" then map({command, exit_code}) else [] end' 2>/dev/null) || post_checks='[]'
    fi
fi

# ── agent tier map from frontmatter ───────────────────────────────────────
tiers='{}'
dev_root="$(cd "${SCRIPT_DIR}/../../.." 2>/dev/null && pwd)"
frontmatter_value() {
    awk -v k="^$2:" '
        NR == 1 && $0 != "---" { exit }
        NR == 1 { next }
        /^---$/ { exit }
        $0 ~ k { sub(/^[^:]*:[[:space:]]*/, ""); gsub(/["'\''[:space:]]/, ""); print; exit }
    ' "$1"
}
while IFS= read -r file; do
    [ -n "$file" ] || continue
    name=$(basename "$file" .md)
    model=$(frontmatter_value "$file" model)
    plan=$(frontmatter_value "$file" model_plan)
    tiers=$(jq -c --arg n "$name" --arg m "$model" --arg p "$plan" \
        'if has($n) then . else .[$n] = {model: (if $m == "" then null else $m end), model_plan: (if $p == "" then null else $p end)} end' <<<"$tiers")
done < <({ [ -d "$plugins_root" ] && find "$plugins_root" -path '*/agents/*.md' -type f 2>/dev/null;
           [ -d "$dev_root/plugins" ] && find "$dev_root/plugins" -path '*/agents/*.md' -type f 2>/dev/null; } | sort)

pricing=$(cat "$PRICING" 2>/dev/null || echo '{}')
printf '%s' "$pricing" | jq -e 'type == "object"' >/dev/null 2>&1 || pricing='{}'

# ── assemble ──────────────────────────────────────────────────────────────
JQ_PROGRAM=$(cat <<'JQ'
def r2: (. * 100 | round) / 100;
def r6: (. * 1000000 | round) / 1000000;
def tsnum: if . == null then null else (sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | try fromdateiso8601 catch null) end;

def price($tier; $in; $cw; $cr; $out):
  ($pricing.tiers[$tier] // null) as $p
  | if $p == null then null
    else (($in * $p.input + $cw * $p.input * $p.cache_write_multiplier
           + $cr * $p.input * $p.cache_read_multiplier + $out * $p.output) / 1000000) | r6 end;

def group_index($phase):
  ($state.resolved_phases // []) as $g
  | [ range(0; $g | length) | select($g[.] | index($phase)) ] | first;

def status_key: if .pass == "fix" or .pass == "verify" then "\(.phase)/\(.pass)"
                elif .aspect != null then "\(.phase)/\(.aspect)" else .phase end;

def entry:
  . as $d
  | ($tiers[$d.agent_type] // {}) as $t
  | (if $d.pass == "plan" then ($t.model_plan // $t.model) else $t.model end) as $tier
  | ($d.input_tokens // 0) as $in | ($d.cache_creation_input_tokens // 0) as $cw
  | ($d.cache_read_input_tokens // 0) as $cr | ($d.output_tokens // 0) as $out
  | ($d.status == "completed") as $measured
  | (($state.phase_status // {})[$d | status_key]) as $ps
  | ($d.last_message_chars // null) as $chars
  | {
      phase: $d.phase, aspect: $d.aspect, pass: $d.pass, agent: $d.agent_type,
      agent_id: $d.agent_id,
      model: $tier, model_id: $d.model,
      status: ($ps // (if $measured then "completed" else $d.status end)),
      usage_source: (if $measured then "measured" else "unmeasured" end),
      started_at: $d.started_at, completed_at: $d.completed_at, turns: $d.turns,
      group_index: group_index($d.phase),
      input_tokens: (if $measured then $in + $cw + $cr else null end),
      output_tokens: (if $measured then $out else null end),
      cached_input_tokens: (if $measured then $cr else null end),
      cache_creation_input_tokens: (if $measured then $cw else null end),
      cache_read_input_tokens: (if $measured then $cr else null end),
      cost_usd: (if $measured then ($d.cost_usd // price($tier; $in; $cw; $cr; $out)) else null end),
      pricing_note: $d.pricing_note,
      compact_summary_chars: $chars,
      compact_handoff_violation: (if $chars == null then false else ($chars / 4) > 3000 end)
    }
  | if .phase == "qa" then . + {qa_iterations_used: null, qa_status: null} else . end;

([ ($report.dispatches // [])[] | select(.nested | not) | entry ]) as $phases
| ([ $phases[] | .input_tokens // 0 ] | add // 0) as $tin
| ([ $phases[] | .output_tokens // 0 ] | add // 0) as $tout
| ([ $phases[] | .cached_input_tokens // 0 ] | add // 0) as $tcached
| ([ $phases[] | .cost_usd // 0 ] | add // 0 | r6) as $tcost
| ($report.nested_cost_usd // 0) as $nested
| ($state.started_at | tsnum) as $s0
| ($completed_at | tsnum) as $s1
| {
    task_slug: $slug,
    stack: ($state.stack.primary // null),
    primary_profile: ($state.stack.primary // null),
    active_profiles: ($state.stack.active_profiles // {}),
    profile_source: ($state.stack.profile_source // null),
    narrative_language: ($state.narrative_language // null),
    headless_mode: ($state.headless_mode // false),
    git_flow: ($state.git_flow // {}),
    active_workflow: ($state.active_workflow // null),
    workflow_selection_reason: ($state.workflow_selection_reason // null),
    started_at: ($state.started_at // null),
    completed_at: $completed_at,
    wall_clock_seconds: (if $s0 != null and $s1 != null then ($s1 - $s0 | floor) else null end),
    resumed: (($state.resume_count // 0) > 0),
    resume_count: ($state.resume_count // 0),
    model_enforcement_corrections: 0,
    phases: $phases,
    usage_source_summary: {
      measured:   ([ $phases[] | select(.usage_source == "measured") ] | length),
      estimated:  ([ $phases[] | select(.usage_source == "estimated") ] | length),
      unmeasured: ([ $phases[] | select(.usage_source == "unmeasured") ] | length)
    },
    nested_cost_usd: $nested,
    total_cost_usd_including_nested: (($tcost + $nested) | r6),
    skip_rules_applied: ($state.skip_rules_applied // []),
    post_pipeline_checks: $post_checks,
    total_input_tokens: $tin,
    total_output_tokens: $tout,
    total_cached_input_tokens: $tcached,
    total_cost_usd: $tcost,
    cost_scope: "subagent_phases_only",
    max_total_cost_usd: ($state.max_total_cost_usd // null),
    cost_cap_overridden: ($state.cost_cap_overridden // false),
    cache_hit_ratio: (($tcached / ([$tin, 1] | max)) | r2),
    deps_preflight: $deps,
    aborted_at_phase: (if $aborted == "" then null else $aborted end)
  }
| . * $extra
JQ
)

telemetry=$(jq -n --arg slug "$slug" --arg completed_at "$completed_at" --arg aborted "$aborted_at" \
    --argjson report "$report" --argjson state "$state" --argjson deps "$deps" \
    --argjson post_checks "$post_checks" --argjson tiers "$tiers" --argjson pricing "$pricing" \
    --argjson extra "$extra" "$JQ_PROGRAM") || { echo "error: could not assemble telemetry" >&2; exit 0; }

printf '%s\n' "$telemetry" | jq . > "${plan_dir}/_telemetry.json" 2>/dev/null

# ── final summary block ───────────────────────────────────────────────────
printf '%s' "$telemetry" | jq -r '
  def icon: if . == "completed" then "✅" elif . == "failed" then "❌"
            elif (. | startswith("skipped")) then "⏭️" else "⚠️" end;
  def money: if . == null then "—" else "$" + (. | tostring) end;
  def phase_label: .phase + (if .aspect != null then " — " + .aspect else "" end)
                    + (if .pass != null then " [pass:" + .pass + "]" else "" end);
  def tokens: if .input_tokens == null then "unmeasured"
              else ((.input_tokens + (.output_tokens // 0)) | tostring) + " tok" end;
  (if .aborted_at_phase != null
   then "⛔ SDLC pipeline aborted at phase \(.aborted_at_phase) for \"\(.task_slug)\""
   else "✅ SDLC pipeline completed for \"\(.task_slug)\"" end),
  "",
  "Stack:           \(.stack // "vanilla")",
  "Branch:          \(.git_flow.branch_name // "—") (\(.git_flow.branch_action // "—"), from \(.git_flow.base_branch // "—")) → PR base \(.git_flow.pr_base_branch // "—")",
  "Task type:       \(.git_flow.task_type // "—") · workflow \(.active_workflow // "default")",
  "Phases run:      \(.phases | length) (\(if (.skip_rules_applied | length) == 0 then "no skip-rules fired" else (.skip_rules_applied | map(.rule + " → skipped " + .phase_skipped) | join(", ")) end))",
  "Wall clock:      \(.wall_clock_seconds // "—")s",
  "Cost:            \(.total_cost_usd | money) (+ \(.nested_cost_usd | money) nested)",
  "",
  "Phase results:",
  (.phases[] | "  \(.status | icon) \(phase_label | . + (" " * (22 - (. | length) | if . < 1 then 1 else . end)))(\(.agent), \(tokens), \(.cost_usd | money))"),
  "",
  "Artifacts:",
  (([.phases[] | .phase] | unique | .[]
    | if . == "business_analysis" then "01-business-analysis.md"
      elif . == "development" then "02-development.md"
      elif . == "qa" then "03-qa.md"
      elif . == "security" then "04-security.md"
      elif . == "documentation" then "05-pr.md"
      else . + ".md" end) | "  docs/plans/\($slug)/\(.)"),
  "  docs/plans/\(.task_slug)/_telemetry.json",
  "",
  "Post-pipeline checks:",
  (if (.post_pipeline_checks | length) == 0 then "  (none)"
   else (.post_pipeline_checks[] | "  \(if .exit_code == 0 then "✅" else "❌" end) \(.command)") end),
  "",
  "PR: \(.pr_url // "—")",
  (if .git_flow.requires_back_merge != null then
     "", "↩️  After the PR merges, back-merge \(.git_flow.pr_base_branch) into \(.git_flow.requires_back_merge) — this",
     "    pipeline does not open that second PR."
   else empty end),
  "",
  "state_file: delete .claude/.sdlc-run-active.json now"
' --arg slug "$slug"
exit 0
