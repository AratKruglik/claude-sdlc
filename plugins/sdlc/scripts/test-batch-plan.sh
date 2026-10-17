#!/usr/bin/env bash
# Fixture-based test harness for batch-plan.sh. Every case runs against task text only,
# so nothing touches the real repo or the file system beyond one temp task list.
#
# Run: bash plugins/sdlc/scripts/test-batch-plan.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN="${SCRIPT_DIR}/batch-plan.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-batch-plan.XXXXXX")
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

# ── overlap → chain, independent → parallel ────────────────────────────────
out=$(bash "$PLAN" -- "Add /healthz endpoint" "Rename /api to /v1 [complex]" "Fix typo in README [simple]")
assert_field "three tasks: count"                 '.tasks | length' 3 "$out"
assert_field "three tasks: slug 1"                '.tasks[0].task_slug' "add-healthz-endpoint" "$out"
assert_field "three tasks: hint stripped"         '.tasks[1].task' "Rename /api to /v1" "$out"
assert_field "three tasks: hint complex"          '.tasks[1].complexity_hint' complex "$out"
assert_field "three tasks: hint simple"           '.tasks[2].complexity_hint' simple "$out"
assert_field "three tasks: endpoint paths"        '.tasks[0].likely_paths | join(",")' "routes/,controllers/,/healthz" "$out"
assert_field "three tasks: readme paths"          '.tasks[2].likely_paths | join(",")' "README.md,docs/" "$out"
assert_field "three tasks: group count"           '.group_count' 2 "$out"
assert_field "three tasks: parallel group first"  '.groups[0].kind' parallel "$out"
assert_field "three tasks: parallel members"      '.groups[0].members | join(",")' "3" "$out"
assert_field "three tasks: chain members"         '.groups[1].members | join(",")' "1,2" "$out"
assert_field "three tasks: chain overlap"         '.groups[1].overlap | join(",")' "routes/,controllers/" "$out"
assert_field "three tasks: parallel count"        '.parallel_task_count' 1 "$out"
assert_field "three tasks: cost 1x"               '.tasks[0].estimated_cost_usd' "2.4" "$out"
assert_field "three tasks: cost 2x"               '.tasks[1].estimated_cost_usd' "4.8" "$out"
assert_field "three tasks: cost 0.5x"             '.tasks[2].estimated_cost_usd' "1.2" "$out"
assert_field "three tasks: total"                 '.total_estimated_cost_usd' "8.4" "$out"
assert_field "three tasks: stack default"         '.stack' auto-detect "$out"
blocks=$(printf '%s' "$out" | jq -r '.print_blocks | .scope, .plan, .cost')
assert_contains "three tasks: scope header"       "📋 Batch scope (3 tasks):" "$blocks"
assert_contains "three tasks: scope line"         "1. add-healthz-endpoint [unspecified] — likely: routes/, controllers/, /healthz" "$blocks"
assert_contains "three tasks: plan chain"         "add-healthz-endpoint → rename-api-to-v1" "$blocks"
assert_contains "three tasks: plan overlap"       "sequential chain, overlap: routes/, controllers/" "$blocks"
assert_contains "three tasks: cost line"          "💰 Estimated cost: \$8.4 across 3 tasks (2 groups, 1 run in parallel)" "$blocks"
assert_contains "three tasks: disclosure"         "batch-dispatched pipelines auto-approve" "$blocks"
assert_contains "three tasks: prompt"             "Proceed? (yes / adjust / abort)" "$blocks"

# ── no overlap at all → one parallel group ─────────────────────────────────
out=$(bash "$PLAN" --stack nodejs --baseline-usd 2 -- "Add auth middleware" "Add rate limiting")
assert_field "independent: group count"           '.group_count' 1 "$out"
assert_field "independent: kind"                  '.groups[0].kind' parallel "$out"
assert_field "independent: unknown paths"         '.tasks[0].likely_paths | length' 0 "$out"
assert_field "independent: baseline"              '.total_estimated_cost_usd' "4" "$out"
assert_contains "independent: forced stack line"  "stack: nodejs (forced for all tasks)" "$(printf '%s' "$out" | jq -r '.print_blocks.plan')"
assert_contains "independent: unknown label"      "likely: unknown" "$(printf '%s' "$out" | jq -r '.print_blocks.scope')"

# ── --file parsing ─────────────────────────────────────────────────────────
cat > "$TMP_ROOT/tasks.md" <<'EOF'
# Sprint 12

- Add billing [complex]
* Fix login redirect [simple]

Write migration for invoices table
EOF
out=$(bash "$PLAN" --file "$TMP_ROOT/tasks.md")
assert_field "file: count"                        '.tasks | length' 3 "$out"
assert_field "file: dash stripped"                '.tasks[0].task' "Add billing" "$out"
assert_field "file: star stripped"                '.tasks[1].task' "Fix login redirect" "$out"
assert_field "file: migration paths"              '.tasks[2].likely_paths | join(",")' "database/migrations/,migrations/" "$out"

# ── slug cap and literal file token ───────────────────────────────────────
out=$(bash "$PLAN" -- "Refactor the extremely long invoice exporter service into smaller composable units please" "Update src/config/app.ts defaults")
assert_field "slug: capped at 40"                 '.tasks[0].task_slug | length <= 40' true "$out"
assert_field "slug: no trailing dash"             '.tasks[0].task_slug | endswith("-")' false "$out"
assert_field "literal: path token kept"           '.tasks[1].likely_paths | join(",")' "src/config/app.ts" "$out"

# ── empty input ────────────────────────────────────────────────────────────
out=$(bash "$PLAN" --)
assert_field "empty: tasks"                       '.tasks | length' 0 "$out"
assert_field "empty: total"                       '.total_estimated_cost_usd' 0 "$out"

printf '\n%d passed, %d failed\n' "$pass_count" "$fail_count"
[ "$fail_count" -eq 0 ]
