#!/usr/bin/env bash
# Fixture-based test harness for run-plan.sh.
#
# Each case builds a throwaway git repository under a temp root and asserts on the planner's
# JSON output. The plugins root is this checkout's own plugins/ directory (real stack.md
# files), caches go to temp dirs, and no case touches the network, ~/.claude, or the real
# repo.
#
# Run: bash plugins/sdlc/scripts/test-run-plan.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN="${SCRIPT_DIR}/run-plan.sh"
PLUGINS_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not available"; exit 0; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-run-plan-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

pass_count=0
fail_count=0

assert_field() {
    local case_name="$1" filter="$2" expected="$3" json="$4" actual
    actual=$(printf '%s' "$json" | jq -r "$filter" 2>/dev/null)
    if [ "$actual" = "$expected" ]; then
        pass_count=$((pass_count + 1)); printf 'PASS  %-66s %s = %s\n' "$case_name" "$filter" "$actual"
    else
        fail_count=$((fail_count + 1)); printf 'FAIL  %-66s %s: expected %q, got %q\n' "$case_name" "$filter" "$expected" "$actual"
    fi
}

assert_contains() {
    local case_name="$1" needle="$2" haystack="$3"
    case "$haystack" in
        *"$needle"*) pass_count=$((pass_count + 1)); printf 'PASS  %-66s contains %q\n' "$case_name" "$needle" ;;
        *) fail_count=$((fail_count + 1)); printf 'FAIL  %-66s missing %q\n' "$case_name" "$needle" ;;
    esac
}

git_q() { git -C "$1" -c user.email=t@example.com -c user.name=Test -c commit.gpgsign=false "${@:2}"; }

# $1 = name, $2 = default branch, $3.. = extra branches off the seed commit. Prints the path.
fresh_repo() {
    local name="$1" default_branch="$2"; shift 2
    local dir="$TMP_ROOT/$name"
    mkdir -p "$dir/.claude"
    git -C "$dir" init --quiet 2>/dev/null
    git -C "$dir" symbolic-ref HEAD "refs/heads/$default_branch"
    printf 'seed\n' > "$dir/README.md"
    git_q "$dir" add README.md
    git_q "$dir" commit --quiet -m seed
    for branch in "$@"; do git -C "$dir" branch "$branch" >/dev/null 2>&1; done
    printf '%s' "$dir"
}

run_plan() {
    local dir="$1"; shift
    bash "$PLAN" --repo "$dir" --plugins-root "$PLUGINS_ROOT" \
        --stack-cache-dir "$TMP_ROOT/stack-cache" --deps-cache-dir "$TMP_ROOT/deps-cache" "$@" 2>/dev/null
}

echo "=== run-plan.sh ==="
echo

# --- github-flow repo ------------------------------------------------------------------
GH=$(fresh_repo gh main feature/a feature/b feature/c fix/d fix/e)
out=$(run_plan "$GH" --arguments "Add healthz endpoint")
assert_field "github-flow: model"                      '.git_flow.model' "github-flow" "$out"
assert_field "github-flow: task type from keyword"     '.git_flow.task_type' "feature" "$out"
assert_field "github-flow: task type confidence"       '.git_flow.task_type_confidence' "high" "$out"
assert_field "github-flow: slug"                       '.task_slug' "add-healthz-endpoint" "$out"
assert_field "github-flow: branch name"                '.git_flow.branch_name' "feature/add-healthz-endpoint" "$out"
assert_field "github-flow: base branch"                '.git_flow.base_branch' "main" "$out"
assert_field "github-flow: PR base"                    '.git_flow.pr_base_branch' "main" "$out"
assert_field "github-flow: creation method"            '.git_flow.branch_creation_method' "checkout-b" "$out"
assert_field "github-flow: current is base"            '.git_flow.current_branch_is_base' "true" "$out"
assert_field "github-flow: narrative language"         '.narrative_language' "en" "$out"
assert_field "github-flow: workflow"                   '.workflow.active_workflow' "default" "$out"
assert_field "github-flow: selection reason"           '.workflow.workflow_selection_reason' "task_type=feature" "$out"
assert_field "github-flow: resolved groups"            '.workflow.resolved_phases | tojson' '[["business_analysis"],["development"],["qa","security"],["documentation"]]' "$out"
assert_field "github-flow: parallel group"             '.workflow.parallel_groups[0]' "qa ∥ security" "$out"
assert_field "github-flow: prospective diff"           '.diff_signals.diff_scope' "prospective" "$out"
assert_field "github-flow: no skip rules"              '.skip_rules.skip_rules_applied | length' "0" "$out"
assert_field "github-flow: vanilla primary"            '.stack.primary_profile.stack' "vanilla" "$out"
assert_field "github-flow: roster qualified"           '.effective_profile.roster | index("sdlc:qa-engineer") != null' "true" "$out"
assert_field "github-flow: no halts"                   '.halts | length' "0" "$out"
assert_contains "github-flow: 🌿 block rendered"       "Proposed:    feature/add-healthz-endpoint" "$(jq -r '.print_blocks.git_flow' <<<"$out")"
assert_contains "github-flow: 🎯 block rendered"       "primary:  vanilla (priority 0, from sdlc/stack.md)" "$(jq -r '.print_blocks.stack' <<<"$out")"
assert_contains "github-flow: workflow line"           "workflow: default  (4 steps after skips, selected by task_type=feature)" "$(jq -r '.print_blocks.workflow' <<<"$out")"

out=$(run_plan "$GH" --arguments "Add healthz endpoint --redetect-stack --force-preflight --resume")
assert_field "flags: redetect_stack"                   '.flags.redetect_stack' "true" "$out"
assert_field "flags: force_preflight"                  '.flags.force_preflight' "true" "$out"
assert_field "flags: resume"                           '.flags.resume' "true" "$out"
assert_field "flags: description cleaned"              '.description' "Add healthz endpoint" "$out"

git -C "$GH" branch feature/add-healthz-endpoint >/dev/null 2>&1
out=$(run_plan "$GH" --arguments "Add healthz endpoint")
assert_field "collision: suffix appended"              '.git_flow.branch_name' "feature/add-healthz-endpoint-2" "$out"

# --- git-flow repo with develop ------------------------------------------------------
GF=$(fresh_repo gf main develop feature/one feature/two fix/three release/1.0)
out=$(run_plan "$GF" --arguments "Urgent production fix: null pointer in payment handler")
assert_field "git-flow: model"                         '.git_flow.model' "git-flow" "$out"
assert_field "git-flow: hotfix classified"             '.git_flow.task_type' "hotfix" "$out"
assert_field "git-flow: runners-up recorded"           '.git_flow.task_type_runners_up | index("fix") != null' "true" "$out"
assert_field "git-flow: hotfix branches from release"  '.git_flow.base_branch' "release/1.0" "$out"
assert_field "git-flow: back-merge to develop"         '.git_flow.requires_back_merge' "develop" "$out"
assert_field "git-flow: hotfix workflow"               '.workflow.active_workflow' "hotfix" "$out"
assert_field "git-flow: recipe cap"                    '.workflow.max_total_cost_usd * 1' "8" "$out"
assert_field "git-flow: cost cap source"               '.workflow.cost_cap_source' "recipe" "$out"
assert_field "git-flow: BA not in hotfix recipe"       '.workflow.resolved_phases | flatten | index("business_analysis")' "null" "$out"
assert_contains "git-flow: back-merge line rendered"   "Requires back-merge to develop" "$(jq -r '.print_blocks.git_flow' <<<"$out")"

out=$(run_plan "$GF" --arguments "Add invoice export")
assert_field "git-flow: feature from develop"          '.git_flow.base_branch' "develop" "$out"
assert_field "git-flow: feature PR base develop"       '.git_flow.pr_base_branch' "develop" "$out"
assert_field "git-flow: topic without prefix"          '.git_flow.git_flow_topic' "add-invoice-export" "$out"

# --- sdlc.local.yaml: git block, skip_phases, agent_overrides ----------------------
LC=$(fresh_repo lc main develop feature/x feature/y)
cat > "$LC/.claude/sdlc.local.yaml" <<'YAML'
git:
  model: github-flow
  default_branch: main
  naming:
    word_separator: "_"
skip_phases:
  - security
agent_overrides:
  qa: tester
post_check_fix_attempts: 1
post_pipeline_checks:
  - npm test
YAML
out=$(run_plan "$LC" --arguments "Add report page")
assert_field "local yaml: git source config"           '.git_flow.source' "config" "$out"
assert_field "local yaml: config overrides detection"  '.git_flow.model' "github-flow" "$out"
assert_field "local yaml: override keys listed"        '.git_flow.config_override_keys | sort | join(",")' "default_branch,model,naming" "$out"
assert_field "local yaml: word separator applied"      '.git_flow.branch_name' "feature/add_report_page" "$out"
assert_field "local yaml: skip_phases parsed"          '.local_config.skip_phases[0]' "security" "$out"
assert_field "local yaml: security removed"            '.workflow.resolved_phases | tojson' '[["business_analysis"],["development"],["qa"],["documentation"]]' "$out"
assert_field "local yaml: agent override applied"      '.effective_profile.phase_agents.qa' "tester" "$out"
assert_field "local yaml: override in roster"          '.effective_profile.roster | index("sdlc:tester") != null' "true" "$out"
assert_field "local yaml: fix attempts"                '.local_config.post_check_fix_attempts' "1" "$out"
assert_field "local yaml: other keys for the model"    '.local_config.other_keys | join(",")' "post_pipeline_checks" "$out"

# --- --type override ---------------------------------------------------------------
out=$(run_plan "$GH" --arguments "Rework the invoice exporter --type=refactor")
assert_field "--type: task type"                       '.git_flow.task_type' "refactor" "$out"
assert_field "--type: source flag"                     '.git_flow.task_type_source' "flag" "$out"
assert_field "--type: flag recorded"                   '.flags.type' "refactor" "$out"
assert_field "--type: refactor workflow"               '.workflow.active_workflow' "refactor" "$out"
assert_field "--type: branch prefix"                   '.git_flow.branch_name' "refactor/rework-the-invoice-exporter" "$out"

out=$(run_plan "$GH" --arguments "Add thing --type=bogus")
assert_field "--type invalid: keyword fallback"        '.git_flow.task_type' "feature" "$out"
assert_contains "--type invalid: warned"               "--type=bogus is not one of" "$(jq -r '.warnings | join("\n")' <<<"$out")"

# --- Ukrainian arguments -----------------------------------------------------------
out=$(run_plan "$GH" --arguments "Виправити баг у формі логіну")
assert_field "uk: narrative language"                  '.narrative_language' "uk" "$out"
assert_field "uk: fix classified"                      '.git_flow.task_type' "fix" "$out"
assert_field "uk: slug transliterated"                 '.task_slug' "vypravyty-bah-u-formi-lohinu" "$out"
assert_field "uk: bugfix workflow"                     '.workflow.active_workflow' "bugfix" "$out"

out=$(run_plan "$GH" --arguments "Терміново: аварія на проді")
assert_field "uk: hotfix classified"                   '.git_flow.task_type' "hotfix" "$out"

# --- typo-fix skip rule on a small committed diff ----------------------------------
TF=$(fresh_repo tf main feature/a fix/b)
git -C "$TF" checkout -q -b fix/typo
printf 'seed\nfixed heading\n' > "$TF/README.md"
git_q "$TF" commit --quiet -am "typo"
out=$(run_plan "$TF" --arguments "Fix typo in README header")
assert_field "typo-fix: retrospective diff"            '.diff_signals.diff_scope' "retrospective" "$out"
assert_field "typo-fix: loc touched"                   '.diff_signals.loc_touched' "1" "$out"
assert_field "typo-fix: rule fired"                    '.skip_rules.skip_rules_applied[0].rule' "typo-fix" "$out"
assert_field "typo-fix: BA skipped"                    '.skip_rules.skip_rules_applied[0].phase_skipped' "business_analysis" "$out"
assert_field "typo-fix: lightweight-no-db fired"       '[.skip_rules.skip_rules_applied[].rule] | index("lightweight-no-db") != null' "true" "$out"
assert_field "typo-fix: security removed"              '.workflow.resolved_phases | flatten | index("security")' "null" "$out"
assert_field "typo-fix: security-lite flag"            '.skip_rules.security_lite' "true" "$out"
assert_field "typo-fix: bugfix recipe within cap"      '.workflow.active_workflow' "bugfix" "$out"
assert_field "typo-fix: gate default continue"         '.git_flow.gate_default' "continue" "$out"
assert_contains "typo-fix: ✂️ block rendered"          "typo-fix → skipped business_analysis" "$(jq -r '.print_blocks.skip_rules' <<<"$out")"

# --- prospective diff on a fresh branch ------------------------------------------------
PR=$(fresh_repo pr main)
git -C "$PR" checkout -q -b feature/new
out=$(run_plan "$PR" --arguments "Fix typo in README")
assert_field "prospective: scope"                      '.diff_signals.diff_scope' "prospective" "$out"
assert_field "prospective: reason"                     '.diff_signals.reason' "no commits ahead of main" "$out"
assert_field "prospective: no skip rules"              '.skip_rules.skip_rules_applied | length' "0" "$out"
assert_field "prospective: bugfix not vetoed"          '.workflow.active_workflow' "bugfix" "$out"

# --- rule-4 content check keeps security ---------------------------------------------
R4=$(fresh_repo r4 main)
git -C "$R4" checkout -q -b fix/exec
printf 'seed\nconst out = exec("ls");\n' > "$R4/README.md"
git_q "$R4" commit --quiet -am "exec"
out=$(run_plan "$R4" --arguments "Fix typo in README")
assert_field "rule 4: content hit recorded"            '.skip_rules.rule4_content_hit != null' "true" "$out"
assert_field "rule 4: security kept"                   '[.skip_rules.skip_rules_applied[].rule] | index("lightweight-no-db")' "null" "$out"

# --- project-local workflow + match scan ------------------------------------------
PL=$(fresh_repo pl main feature/a)
mkdir -p "$PL/.claude/sdlc-workflows"
cat > "$PL/.claude/sdlc-workflows/spike.yaml" <<'YAML'
name: spike
description: Throwaway exploration.
match:
  arguments_pattern: "(?<![\\p{L}\\p{N}])spike(?![\\p{L}\\p{N}])"
caps:
  max_total_cost_usd: 1.5
phases:
  - development
  - documentation
YAML
out=$(run_plan "$PL" --arguments "Add caching --workflow=spike")
assert_field "project-local: selected by flag"         '.workflow.workflow_selection_reason' "flag" "$out"
assert_field "project-local: flagged"                  '.workflow.project_local' "true" "$out"
assert_field "project-local: phases"                   '.workflow.resolved_phases | tojson' '[["development"],["documentation"]]' "$out"
assert_field "project-local: cap"                      '.workflow.max_total_cost_usd' "1.5" "$out"
assert_contains "project-local: line marks it"         "workflow: spike (project-local)" "$(jq -r '.print_blocks.workflow' <<<"$out")"

out=$(run_plan "$PL" --arguments "Quick spike on caching")
assert_field "match scan: default would map feature"   '.git_flow.task_type' "feature" "$out"
assert_field "match scan: default recipe wins"         '.workflow.active_workflow' "default" "$out"

out=$(run_plan "$PL" --arguments "Spike on caching --type=chore")
assert_field "match scan: still default for chore"     '.workflow.active_workflow' "default" "$out"

out=$(run_plan "$PL" --arguments "Add caching --workflow=nope")
assert_field "missing workflow: halted"                '.halts | length' "1" "$out"
assert_contains "missing workflow: exact text"         "❌ Workflow 'nope' not found." "$(jq -r '.halts[0]' <<<"$out")"
assert_contains "missing workflow: lists available"    "Available:" "$(jq -r '.halts[0]' <<<"$out")"

# --- forced stack + a real stack profile ----------------------------------------------
LV=$(fresh_repo lv main develop feature/a)
printf '{"require":{"laravel/framework":"^11"}}\n' > "$LV/composer.json"
git_q "$LV" add composer.json; git_q "$LV" commit --quiet -m laravel
git -C "$LV" branch -f develop >/dev/null 2>&1
out=$(run_plan "$LV" --arguments "Add subscription billing")
assert_field "laravel: primary profile"                '.stack.primary_profile.stack' "laravel" "$out"
assert_field "laravel: backend agent"                  '.effective_profile.phase_agents.development.backend' "laravel-architect" "$out"
assert_field "laravel: extra phase agent"              '.effective_profile.phase_agents.database' "artisan-specialist" "$out"
assert_field "laravel: extra phase inserted"           '.workflow.resolved_phases | tojson' '[["business_analysis"],["development"],["database"],["qa","security"],["documentation"]]' "$out"
assert_field "laravel: roster qualified by plugin"     '.effective_profile.roster | index("laravel-plugin:laravel-architect") != null' "true" "$out"
assert_field "laravel: core agent stays sdlc"          '.effective_profile.roster | index("sdlc:business-analyst") != null' "true" "$out"
assert_field "laravel: phase status keys"              '.effective_profile.phase_status_keys | join(",")' "business_analysis,development/backend,database,qa,security,documentation" "$out"
assert_field "laravel: convention skills sorted"       '.effective_profile.convention_skills[0]' "laravel-plugin:eloquent-patterns" "$out"
assert_field "laravel: post checks"                    '.effective_profile.post_pipeline_checks | index("php artisan test") != null' "true" "$out"
assert_field "laravel: injection phases"               '.effective_profile.injection_phases["laravel-plugin"] | join(",")' "development,qa,security" "$out"

# Installed layout: ~/.claude/plugins/cache/{marketplace}/{plugin}/{version}/ — the path holds
# "/plugins/" as well, which once made the version directory pass for the plugin name.
CACHE_ROOT="$TMP_ROOT/home/.claude/plugins/cache"
for p in "$PLUGINS_ROOT"/*/; do
    p=$(basename "$p")
    mkdir -p "$CACHE_ROOT/mkt/$p"
    cp -R "$PLUGINS_ROOT/$p" "$CACHE_ROOT/mkt/$p/9.9.9"
done
out=$(bash "$PLAN" --repo "$LV" --plugins-root "$CACHE_ROOT" --stack-cache-dir "$TMP_ROOT/stack-cache-installed" \
    --deps-cache-dir "$TMP_ROOT/deps-cache" --arguments "Add subscription billing" 2>/dev/null)
assert_field "installed cache: roster qualified by plugin" '.effective_profile.roster | index("laravel-plugin:laravel-architect") != null' "true" "$out"
assert_field "installed cache: no version as plugin"   '[.effective_profile.roster[] | select(startswith("9.9.9:"))] | length' "0" "$out"
assert_field "installed cache: primary plugin name"    '.effective_profile.primary.plugin' "laravel-plugin" "$out"

out=$(run_plan "$LV" --arguments "Add subscription billing --stack=vanilla")
assert_field "--stack: forced"                         '.stack.forced' "true" "$out"
assert_field "--stack: vanilla primary"                '.stack.primary_profile.stack' "vanilla" "$out"
assert_field "--stack: vanilla agent"                  '.effective_profile.phase_agents.development' "developer" "$out"
assert_contains "--stack: block says forced"           "forced via --stack: yes" "$(jq -r '.print_blocks.stack' <<<"$out")"

out=$(run_plan "$LV" --arguments "Add billing --stack=nonexistent")
assert_contains "--stack unknown: halted"              "no installed stack.md declares stack: nonexistent" "$(jq -r '.halts[0]' <<<"$out")"

# --- run state file -------------------------------------------------------------------
now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
printf '{"schema_version":2,"task_slug":"old-run","started_at":"%s","updated_at":"%s","git_flow":{"branch_name":"feature/old-run"},"phase_status":{"business_analysis":"completed","development":"pending"}}\n' "$now" "$now" > "$GH/.claude/.sdlc-run-active.json"
out=$(run_plan "$GH" --arguments "--resume")
assert_field "state: present"                          '.state_file.present' "true" "$out"
assert_field "state: fresh"                            '.state_file.fresh' "true" "$out"
assert_field "state: slug"                             '.state_file.task_slug' "old-run" "$out"
assert_field "state: phase status carried"             '.state_file.phase_status.business_analysis' "completed" "$out"
rm -f "$GH/.claude/.sdlc-run-active.json"

# --- headless decision -----------------------------------------------------------
out=$(run_plan "$GH" --arguments "Add metrics" --headless)
assert_field "headless: applies"                       '.git_flow.headless_decision.applies' "true" "$out"
assert_field "headless: creates on base branch"        '.git_flow.headless_decision.branch_action' "create" "$out"
assert_field "headless: preflight print suppressed"    '.print_blocks.preflight' "" "$out"
assert_contains "headless: stderr line"                "GIT-FLOW: model=github-flow" "$(jq -r '.print_blocks.git_flow_headless_stderr' <<<"$out")"

echo
printf '%d passed, %d failed\n' "$pass_count" "$fail_count"
[ "$fail_count" -eq 0 ]
