#!/usr/bin/env bash
# Tests for doctor.sh: the --json object carries every documented top-level key, the cost
# baseline is seeded exactly once, run-marker states are classified like the hooks classify
# them, shadowing is detected, and the human renderer prints each section.
#
# Each case runs against a throwaway git repository; this repository's plugins directory
# is the plugins root. Nothing touches ~/.claude.
#
# Run: bash plugins/sdlc/scripts/test-doctor.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOCTOR="${SCRIPT_DIR}/doctor.sh"
REAL_PLUGINS_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)/plugins"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not available"; exit 0; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-doctor-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT
export HOME="$TMP_ROOT/home"; mkdir -p "$HOME"
unset CLAUDE_PLUGIN_DATA CLAUDE_CODE_SUBAGENT_MODEL CLAUDE_CODE_SUBAGENT_MODEL_FORCE

pass_count=0
fail_count=0

assert_eq() {
    local case_name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        pass_count=$((pass_count + 1)); printf 'PASS  %-64s = %s\n' "$case_name" "$actual"
    else
        fail_count=$((fail_count + 1)); printf 'FAIL  %-64s expected %q, got %q\n' "$case_name" "$expected" "$actual"
    fi
}
assert_contains() {
    local case_name="$1" needle="$2" haystack="$3"
    case "$haystack" in
        *"$needle"*) pass_count=$((pass_count + 1)); printf 'PASS  %-64s contains %q\n' "$case_name" "$needle" ;;
        *) fail_count=$((fail_count + 1)); printf 'FAIL  %-64s missing %q\n' "$case_name" "$needle" ;;
    esac
}

iso_offset() {
    local off="$1" gnu_expr=""
    case "$off" in
        -*M) gnu_expr="${off#-}"; gnu_expr="${gnu_expr%M} minutes ago" ;;
        -*H) gnu_expr="${off#-}"; gnu_expr="${gnu_expr%H} hours ago" ;;
    esac
    if [ -n "$gnu_expr" ] && date -u -d "$gnu_expr" +"%Y-%m-%dT%H:%M:%S+00:00" 2>/dev/null; then return 0; fi
    date -u -v"$off" +"%Y-%m-%dT%H:%M:%S+00:00"
}

fresh_project() {
    PROJ="${TMP_ROOT}/$1"
    mkdir -p "$PROJ/.claude"
    git -C "$PROJ" init -q 2>/dev/null
    git -C "$PROJ" symbolic-ref HEAD refs/heads/main 2>/dev/null
    git -C "$PROJ" config user.email t@example.com
    git -C "$PROJ" config user.name Test
    printf '{"require":{"laravel/framework":"^11"}}\n' > "$PROJ/composer.json"
    git -C "$PROJ" add -A >/dev/null 2>&1 && git -C "$PROJ" commit -qm init >/dev/null 2>&1
}

doctor_json() { bash "$DOCTOR" --repo "$1" --plugins-root "$REAL_PLUGINS_ROOT" --json; }
doctor_text() { bash "$DOCTOR" --repo "$1" --plugins-root "$REAL_PLUGINS_ROOT"; }

# ── Case 1: clean Laravel project — JSON shape and baseline seeding ──
fresh_project clean
OUT=$(doctor_json "$PROJ"); rc=$?
assert_eq "case1 exit 0" "0" "$rc"
assert_eq "case1 valid JSON" "true" "$(jq -e . <<<"$OUT" >/dev/null 2>&1 && echo true || echo false)"
for key in deps_preflight stack cost_baseline model_routing local_agent_shadowing run_marker dispatch_telemetry git_flow would_abort_pipeline; do
    assert_eq "case1 has key $key" "true" "$(jq --arg k "$key" 'has($k)' <<<"$OUT")"
done
assert_eq "case1 active profile laravel" "laravel" "$(jq -r '.stack.active_profile' <<<"$OUT")"
assert_eq "case1 session cache absent" "false" "$(jq -r '.stack.session_cache.present' <<<"$OUT")"
assert_eq "case1 baseline seeded" "true" "$(jq -r '.cost_baseline.seeded' <<<"$OUT")"
assert_eq "case1 baseline file exists" "yes" "$([ -f "$PROJ/docs/cost-baseline.md" ] && echo yes || echo no)"
assert_eq "case1 baseline not yet available" "false" "$(jq -r '.cost_baseline.available' <<<"$OUT")"
assert_eq "case1 declared tier laravel-architect plan" "opus" "$(jq -r '.model_routing.declared_tiers["laravel-architect"].model_plan' <<<"$OUT")"
assert_eq "case1 declared tier document-writer" "haiku" "$(jq -r '.model_routing.declared_tiers["document-writer"].model' <<<"$OUT")"
assert_eq "case1 extra-phase agent listed" "sonnet" "$(jq -r '.model_routing.declared_tiers["artisan-specialist"].model' <<<"$OUT")"
assert_eq "case1 no override" "false" "$(jq -r '.model_routing.override_active' <<<"$OUT")"
assert_eq "case1 no shadowing" "0" "$(jq -r '.local_agent_shadowing | length' <<<"$OUT")"
assert_eq "case1 run marker absent" "false" "$(jq -r '.run_marker.present' <<<"$OUT")"
assert_eq "case1 hooks registered" "true" "$(jq -r '.dispatch_telemetry.hooks_registered' <<<"$OUT")"
assert_eq "case1 pre-commit guard registered" "true" "$(jq -r '.dispatch_telemetry.pre_commit_guard_registered' <<<"$OUT")"
assert_eq "case1 laravel guard parsed" "pint.json" "$(jq -r '.dispatch_telemetry.stack_guards[] | select(.plugin == "laravel-plugin") | .protected_globs[0]' <<<"$OUT")"
assert_eq "case1 laravel check command parsed" "true" "$(jq -r '.dispatch_telemetry.stack_guards[] | select(.plugin == "laravel-plugin") | .post_implement_check | startswith("./vendor/bin/phpstan")' <<<"$OUT")"
assert_eq "case1 last run null" "null" "$(jq -r '.dispatch_telemetry.last_run' <<<"$OUT")"
assert_eq "case1 git flow source detection" "detection" "$(jq -r '.git_flow.source' <<<"$OUT")"
assert_eq "case1 git flow cache absent" "false" "$(jq -r '.git_flow.cache.present' <<<"$OUT")"
assert_eq "case1 creation method" "checkout-b" "$(jq -r '.git_flow.branch_creation_method' <<<"$OUT")"
assert_eq "case1 would_abort is boolean" "boolean" "$(jq -r '.would_abort_pipeline | type' <<<"$OUT")"

# ── Case 2: second run does not re-seed or overwrite the baseline ──
printf '\ncustom line\n' >> "$PROJ/docs/cost-baseline.md"
OUT=$(doctor_json "$PROJ")
assert_eq "case2 not seeded again" "false" "$(jq -r '.cost_baseline.seeded' <<<"$OUT")"
assert_eq "case2 user edit preserved" "custom line" "$(tail -1 "$PROJ/docs/cost-baseline.md")"

# ── Case 3: populated baseline is parsed ──
cat > "$PROJ/docs/cost-baseline.md" <<'EOF'
# Cost Baseline
```json summary
{"runs_aggregated": 22, "avg_cost_per_medium_run_usd": 1.62, "p90_cost_per_medium_run_usd": 2.31, "cache_hit_ratio": 0.61, "cost_scope": "subagent_phases_only", "last_updated": "2026-05-04"}
```
EOF
OUT=$(doctor_json "$PROJ")
assert_eq "case3 baseline available" "true" "$(jq -r '.cost_baseline.available' <<<"$OUT")"
assert_eq "case3 runs aggregated" "22" "$(jq -r '.cost_baseline.runs_aggregated' <<<"$OUT")"
assert_eq "case3 avg parsed" "1.62" "$(jq -r '.cost_baseline.avg_cost_per_medium_run_usd' <<<"$OUT")"

# ── Case 4: run marker fresh / stale v2 / v1 ──
write_state() {
    printf '{"schema_version":%s,"task_slug":"demo","started_at":"%s","updated_at":"%s","resume_count":1,"phase_status":{"business_analysis":"completed","development/backend":"pending","qa":"pending"}}\n' "$1" "$2" "$2" > "$PROJ/.claude/.sdlc-run-active.json"
}
write_state 2 "$(iso_offset -5M)"
OUT=$(doctor_json "$PROJ")
assert_eq "case4 fresh marker present" "true" "$(jq -r '.run_marker.present' <<<"$OUT")"
assert_eq "case4 fresh marker not stale" "false" "$(jq -r '.run_marker.stale' <<<"$OUT")"
assert_eq "case4 fresh marker resumable" "true" "$(jq -r '.run_marker.resumable' <<<"$OUT")"
assert_eq "case4 completed steps counted" "1" "$(jq -r '.run_marker.completed_steps' <<<"$OUT")"
assert_eq "case4 total steps counted" "3" "$(jq -r '.run_marker.total_steps' <<<"$OUT")"
assert_eq "case4 guards armed while fresh" "true" "$(jq -r '.dispatch_telemetry.guards_armed' <<<"$OUT")"
TEXT=$(doctor_text "$PROJ")
assert_contains "case4 human: active run line" '🏃 run "demo" active' "$TEXT"
assert_contains "case4 human: guards armed" "armed (run active)" "$TEXT"

write_state 2 "$(iso_offset -7H)"
OUT=$(doctor_json "$PROJ")
assert_eq "case4 stale v2 marker stale" "true" "$(jq -r '.run_marker.stale' <<<"$OUT")"
assert_eq "case4 stale v2 still resumable" "true" "$(jq -r '.run_marker.resumable' <<<"$OUT")"
assert_contains "case4 human: resumable hint" "resumable with: /sdlc:start --resume" "$(doctor_text "$PROJ")"

printf '{"task_slug":"old","started_at":"%s"}\n' "$(iso_offset -7H)" > "$PROJ/.claude/.sdlc-run-active.json"
OUT=$(doctor_json "$PROJ")
assert_eq "case4 v1 marker schema null" "null" "$(jq -r '.run_marker.schema_version' <<<"$OUT")"
assert_eq "case4 v1 marker not resumable" "false" "$(jq -r '.run_marker.resumable' <<<"$OUT")"
assert_contains "case4 human: pre-2.0 marker" "stale pre-2.0 run marker" "$(doctor_text "$PROJ")"
rm -f "$PROJ/.claude/.sdlc-run-active.json"

# ── Case 5: local-agent shadowing, exact name and role alias ──
mkdir -p "$PROJ/.claude/agents"
printf -- '---\nname: qa-engineer\n---\n' > "$PROJ/.claude/agents/qa-engineer.md"
printf -- '---\nname: developer\n---\n' > "$PROJ/.claude/agents/developer.md"
OUT=$(doctor_json "$PROJ")
assert_eq "case5 two collisions" "2" "$(jq -r '.local_agent_shadowing | length' <<<"$OUT")"
assert_eq "case5 exact-name collision" "qa-engineer" "$(jq -r '.local_agent_shadowing[] | select(.path | endswith("qa-engineer.md")) | .shadows' <<<"$OUT")"
assert_eq "case5 role alias collision" "laravel-architect" "$(jq -r '.local_agent_shadowing[] | select(.path | endswith("developer.md")) | .shadows' <<<"$OUT")"
assert_contains "case5 human: shadowing warning" "shadows profile agent" "$(doctor_text "$PROJ")"
rm -rf "$PROJ/.claude/agents"

# ── Case 6: routing override and git config block ──
OUT=$(CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 CLAUDE_CODE_SUBAGENT_MODEL=opus doctor_json "$PROJ")
assert_eq "case6 override active" "true" "$(jq -r '.model_routing.override_active' <<<"$OUT")"
assert_eq "case6 override model" "opus" "$(jq -r '.model_routing.subagent_model_override' <<<"$OUT")"
assert_contains "case6 human: force warning" "CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1" "$(CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1 CLAUDE_CODE_SUBAGENT_MODEL=opus doctor_text "$PROJ")"
printf 'git:\n  model: git-flow\n  develop_branch: develop\n' > "$PROJ/.claude/sdlc.local.yaml"
OUT=$(doctor_json "$PROJ")
assert_eq "case6 git source config" "config" "$(jq -r '.git_flow.source' <<<"$OUT")"
assert_eq "case6 config keys" "model,develop_branch" "$(jq -r '.git_flow.config_override_keys | join(",")' <<<"$OUT")"
assert_contains "case6 human: config overrides" "config overrides detection: model=git-flow" "$(doctor_text "$PROJ")"
rm -f "$PROJ/.claude/sdlc.local.yaml"

# ── Case 7: last run via usage log ──
mkdir -p "$PROJ/docs/plans/demo"
cat > "$PROJ/docs/plans/demo/_usage.jsonl" <<'EOF'
{"event":"pending","ts":"2026-01-01T00:00:00Z","agent_type":"qa-engineer","description":"Phase 1/1: qa","phase":"qa","aspect":null,"pass":null}
{"event":"start","ts":"2026-01-01T00:00:01Z","agent_id":"a1","agent_type":"qa-engineer"}
{"event":"stop","ts":"2026-01-01T00:01:00Z","agent_id":"a1","agent_type":"qa-engineer","model":"claude-sonnet-5","input_tokens":1000,"output_tokens":100,"cache_creation_input_tokens":0,"cache_read_input_tokens":0,"turns":3,"cost_usd":0.003,"pricing_note":null,"last_message_chars":200,"usage_source":"measured"}
EOF
OUT=$(doctor_json "$PROJ")
assert_eq "case7 last run slug" "demo" "$(jq -r '.dispatch_telemetry.last_run.task_slug' <<<"$OUT")"
assert_eq "case7 last run measured" "1" "$(jq -r '.dispatch_telemetry.last_run.usage_source_summary.measured' <<<"$OUT")"
assert_contains "case7 human: last run line" "last run: demo — 1 dispatches" "$(doctor_text "$PROJ")"

# ── Case 8: human output has every section ──
TEXT=$(doctor_text "$PROJ")
for section in "🩺 SDLC Doctor" "Dependencies (from runtime-dependencies.json):" "Stack profiles:" "Cost baseline" "Model routing:" "Local-agent shadowing:" "Run marker:" "Dispatch telemetry:" "Git flow:" "Heads-up:"; do
    assert_contains "case8 section present" "$section" "$TEXT"
done

# ── Case 9: usage error ──
bash "$DOCTOR" --nope >/dev/null 2>&1; assert_eq "case9 usage error exit code" "2" "$?"

echo
echo "=== ${pass_count} passed, ${fail_count} failed ==="
[ "$fail_count" -eq 0 ]
