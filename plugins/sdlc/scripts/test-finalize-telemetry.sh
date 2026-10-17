#!/usr/bin/env bash
# Fixture-based test harness for finalize-telemetry.sh. Builds a throwaway project with a
# usage log, a state file, agent definitions under a temp plugins root, and a post-checks
# report; asserts on the written _telemetry.json and the printed summary. Nothing touches
# the real repo or ~/.claude.
#
# Run: bash plugins/sdlc/scripts/test-finalize-telemetry.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FINALIZE="${SCRIPT_DIR}/finalize-telemetry.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-finalize.XXXXXX")
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

assert_contains() {
    local case_name="$1" needle="$2" haystack="$3"
    case "$haystack" in
        *"$needle"*) pass_count=$((pass_count + 1)); printf 'PASS  %-64s contains %q\n' "$case_name" "$needle" ;;
        *) fail_count=$((fail_count + 1)); printf 'FAIL  %-64s missing %q\n' "$case_name" "$needle" ;;
    esac
}

PLUGINS="$TMP_ROOT/plugins"
mkdir -p "$PLUGINS/sdlc/agents" "$PLUGINS/laravel-plugin/agents"
printf -- '---\nname: business-analyst\nmodel: opus\neffort: high\n---\n' > "$PLUGINS/sdlc/agents/business-analyst.md"
printf -- '---\nname: qa-engineer\nmodel: sonnet\n---\n' > "$PLUGINS/sdlc/agents/qa-engineer.md"
printf -- '---\nname: laravel-architect\nmodel: sonnet\nmodel_plan: opus\n---\n' > "$PLUGINS/laravel-plugin/agents/laravel-architect.md"

# Sets PROJ and writes the usage log + state file. $1 = project name.
fresh_project() {
    PROJ="$TMP_ROOT/$1"
    mkdir -p "$PROJ/.claude" "$PROJ/docs/plans/demo"
    cat > "$PROJ/.claude/.sdlc-run-active.json" <<'EOF'
{
  "schema_version": 2, "task_slug": "demo",
  "started_at": "2026-10-17T10:00:00Z", "updated_at": "2026-10-17T10:20:00Z",
  "stack": {"primary": "laravel", "active_profiles": {"backend": "laravel"}, "profile_source": "laravel-plugin/stack.md", "forced": false},
  "git_flow": {"model": "git-flow", "task_type": "hotfix", "branch_name": "hotfix/demo", "branch_action": "created",
               "base_branch": "main", "pr_base_branch": "main", "requires_back_merge": "develop", "diff_scope": "prospective"},
  "narrative_language": "uk", "headless_mode": false,
  "active_workflow": "hotfix", "workflow_selection_reason": "task_type=hotfix",
  "max_total_cost_usd": 8, "cost_cap_overridden": false,
  "resolved_phases": [["development"], ["qa", "security"], ["documentation"]],
  "skip_rules_applied": [{"rule": "typo-fix", "phase_skipped": "business_analysis", "reason": "matched"}],
  "phase_status": {"development/backend": "completed", "qa": "completed", "security": "failed", "documentation": "pending"},
  "resume_count": 1
}
EOF
    cat > "$PROJ/docs/plans/demo/_usage.jsonl" <<'EOF'
{"event":"pending","ts":"2026-10-17T10:01:00.000Z","agent_type":"laravel-architect","description":"Phase 1/3: development — backend [pass:plan]","phase":"development","aspect":"backend","pass":"plan"}
{"event":"start","ts":"2026-10-17T10:01:01.000Z","agent_id":"a1","agent_type":"laravel-architect"}
{"event":"stop","ts":"2026-10-17T10:05:00.000Z","agent_id":"a1","agent_type":"laravel-architect","model":"claude-opus-5","input_tokens":1000,"output_tokens":500,"cache_creation_input_tokens":200,"cache_read_input_tokens":800,"turns":5,"cost_usd":0.02,"pricing_note":null,"last_message_chars":2000,"usage_source":"measured"}
{"event":"pending","ts":"2026-10-17T10:06:00.000Z","agent_type":"laravel-architect","description":"Phase 1/3: development — backend [pass:implement]","phase":"development","aspect":"backend","pass":"implement"}
{"event":"start","ts":"2026-10-17T10:06:01.000Z","agent_id":"a2","agent_type":"laravel-architect"}
{"event":"stop","ts":"2026-10-17T10:12:00.000Z","agent_id":"a2","agent_type":"laravel-architect","model":"claude-future-9","input_tokens":2000,"output_tokens":1000,"cache_creation_input_tokens":0,"cache_read_input_tokens":2000,"turns":9,"cost_usd":null,"pricing_note":"unknown model","last_message_chars":14000,"usage_source":"measured"}
{"event":"pending","ts":"2026-10-17T10:13:00.000Z","agent_type":"qa-engineer","description":"Phase 2/3: qa","phase":"qa","aspect":null,"pass":null}
{"event":"start","ts":"2026-10-17T10:13:01.000Z","agent_id":"a3","agent_type":"qa-engineer"}
{"event":"stop","ts":"2026-10-17T10:15:00.000Z","agent_id":"a3","agent_type":"qa-engineer","model":null,"input_tokens":null,"output_tokens":null,"cache_creation_input_tokens":null,"cache_read_input_tokens":null,"turns":null,"cost_usd":null,"pricing_note":null,"last_message_chars":900,"usage_source":"transcript_missing"}
{"event":"start","ts":"2026-10-17T10:13:30.000Z","agent_id":"n1","agent_type":"Explore"}
{"event":"stop","ts":"2026-10-17T10:14:00.000Z","agent_id":"n1","agent_type":"Explore","model":"claude-haiku-5","input_tokens":100,"output_tokens":50,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"turns":1,"cost_usd":0.00035,"pricing_note":null,"last_message_chars":10,"usage_source":"measured"}
EOF
    cat > "$PROJ/docs/plans/demo/05-post-checks.md" <<'EOF'
# Post-pipeline checks

```json post-checks
[{"command": "./vendor/bin/pint --test", "exit_code": 0}, {"command": "php artisan test", "exit_code": 1}]
```
EOF
}

# ── full run ───────────────────────────────────────────────────────────────
fresh_project full
summary=$(bash "$FINALIZE" demo --project-root "$PROJ" --plugins-root "$PLUGINS" \
    --completed-at "2026-10-17T10:30:00Z" --extra '{"pr_url":"https://example.com/pr/1","model_enforcement_corrections":2}')
json=$(cat "$PROJ/docs/plans/demo/_telemetry.json")
assert_field "full: slug"                     '.task_slug' demo "$json"
assert_field "full: stack"                    '.stack' laravel "$json"
assert_field "full: workflow"                 '.active_workflow' hotfix "$json"
assert_field "full: wall clock"               '.wall_clock_seconds' 1800 "$json"
assert_field "full: resumed"                  '.resumed' true "$json"
assert_field "full: resume count"             '.resume_count' 1 "$json"
assert_field "full: phases count"             '.phases | length' 3 "$json"
assert_field "full: nested excluded"          '[.phases[] | .agent] | index("Explore")' null "$json"
assert_field "full: plan tier"                '.phases[0].model' opus "$json"
assert_field "full: implement tier"           '.phases[1].model' sonnet "$json"
assert_field "full: plan input total"         '.phases[0].input_tokens' 2000 "$json"
assert_field "full: plan cached"              '.phases[0].cached_input_tokens' 800 "$json"
assert_field "full: plan cost copied"         '.phases[0].cost_usd' 0.02 "$json"
assert_field "full: plan status from state"   '.phases[0].status' completed "$json"
assert_field "full: plan group index"         '.phases[0].group_index' 0 "$json"
assert_field "full: unknown model priced"     '.phases[1].cost_usd' 0.0144 "$json"
assert_field "full: unknown model note"       '.phases[1].pricing_note' "unknown model" "$json"
assert_field "full: handoff violation"        '.phases[1].compact_handoff_violation' true "$json"
assert_field "full: qa unmeasured"            '.phases[2].usage_source' unmeasured "$json"
assert_field "full: qa tokens null"           '.phases[2].input_tokens' null "$json"
assert_field "full: qa group index"           '.phases[2].group_index' 1 "$json"
assert_field "full: qa fields present"        '.phases[2] | has("qa_iterations_used")' true "$json"
assert_field "full: total input"              '.total_input_tokens' 6000 "$json"
assert_field "full: total output"             '.total_output_tokens' 1500 "$json"
assert_field "full: total cached"             '.total_cached_input_tokens' 2800 "$json"
assert_field "full: total cost"               '.total_cost_usd' 0.0344 "$json"
assert_field "full: cache hit ratio"          '.cache_hit_ratio' 0.47 "$json"
assert_field "full: nested cost"              '.nested_cost_usd' 0.00035 "$json"
assert_field "full: including nested"         '.total_cost_usd_including_nested' 0.03475 "$json"
assert_field "full: source summary"           '.usage_source_summary | "\(.measured)/\(.estimated)/\(.unmeasured)"' "2/0/1" "$json"
assert_field "full: post checks"              '.post_pipeline_checks | length' 2 "$json"
assert_field "full: post check exit"          '.post_pipeline_checks[1].exit_code' 1 "$json"
assert_field "full: skip rules"               '.skip_rules_applied[0].rule' typo-fix "$json"
assert_field "full: cost scope"               '.cost_scope' subagent_phases_only "$json"
assert_field "full: max cost"                 '.max_total_cost_usd' 8 "$json"
assert_field "full: aborted null"             '.aborted_at_phase' null "$json"
assert_field "full: extra pr_url"             '.pr_url' "https://example.com/pr/1" "$json"
assert_field "full: extra overrides"          '.model_enforcement_corrections' 2 "$json"
assert_field "full: git_flow carried"         '.git_flow.requires_back_merge' develop "$json"
assert_contains "full: summary header"        "✅ SDLC pipeline completed for \"demo\"" "$summary"
assert_contains "full: summary branch"        "Branch:          hotfix/demo (created, from main) → PR base main" "$summary"
assert_contains "full: summary phase line"    "development — backend [pass:plan] (laravel-architect, 2500 tok, \$0.02)" "$summary"
assert_contains "full: summary failed check"  "❌ php artisan test" "$summary"
assert_contains "full: summary PR"            "PR: https://example.com/pr/1" "$summary"
assert_contains "full: summary back-merge"    "back-merge main into develop" "$summary"
assert_contains "full: summary reminder"      "state_file: delete .claude/.sdlc-run-active.json now" "$summary"
assert_contains "full: summary skip"          "typo-fix → skipped business_analysis" "$summary"

# ── aborted run, no post-checks, no deps cache ─────────────────────────────
fresh_project aborted
rm "$PROJ/docs/plans/demo/05-post-checks.md"
mkdir -p "$TMP_ROOT/home"
summary=$(HOME="$TMP_ROOT/home" bash "$FINALIZE" demo --project-root "$PROJ" --plugins-root "$PLUGINS" --aborted-at-phase security)
json=$(cat "$PROJ/docs/plans/demo/_telemetry.json")
assert_field "aborted: phase"                 '.aborted_at_phase' security "$json"
assert_field "aborted: post checks empty"     '.post_pipeline_checks | length' 0 "$json"
assert_field "aborted: deps empty"            '.deps_preflight | length' 0 "$json"
assert_field "aborted: completed_at set"      '.completed_at | length' 20 "$json"
assert_contains "aborted: summary header"     "⛔ SDLC pipeline aborted at phase security for \"demo\"" "$summary"
assert_contains "aborted: no checks"          "(none)" "$summary"

# ── deps cache via CLAUDE_PLUGIN_DATA, no state file, empty log ───────────
mkdir -p "$TMP_ROOT/data" "$TMP_ROOT/bare/docs/plans/demo"
printf '{"checked_at":"x","results":{"superpowers":"available","frontend-design":"missing"},"all_satisfied":false}\n' > "$TMP_ROOT/data/deps-preflight.json"
summary=$(CLAUDE_PLUGIN_DATA="$TMP_ROOT/data" bash "$FINALIZE" demo --project-root "$TMP_ROOT/bare" --plugins-root "$PLUGINS")
json=$(cat "$TMP_ROOT/bare/docs/plans/demo/_telemetry.json")
assert_field "bare: deps available"           '.deps_preflight.superpowers.status' available "$json"
assert_field "bare: deps missing"             '.deps_preflight["frontend-design"].status' missing "$json"
assert_field "bare: phases empty"             '.phases | length' 0 "$json"
assert_field "bare: ratio zero"               '.cache_hit_ratio' 0 "$json"
assert_field "bare: wall clock null"          '.wall_clock_seconds' null "$json"
assert_contains "bare: summary still prints"  "SDLC pipeline completed" "$summary"

# ── usage errors ───────────────────────────────────────────────────────────
bash "$FINALIZE" >/dev/null 2>&1; assert_field "usage: no slug" '.' 2 "$?"
bash "$FINALIZE" demo --extra 'nope' >/dev/null 2>&1; assert_field "usage: bad extra" '.' 2 "$?"

printf '\n%d passed, %d failed\n' "$pass_count" "$fail_count"
[ "$fail_count" -eq 0 ]
