#!/usr/bin/env bash
# Deterministic batch-pipeline Steps 1–3: per-task slug, complexity hint, likely-path
# heuristic, conflict grouping, cost estimate, and the three verbatim announcement blocks the
# batch-pipeline skill must print. Emits one JSON object; the blocks are under `print_blocks`.
#
# The path heuristic reads task text only — no worktree exists yet to check against — so the
# grouping is a scheduling aid, never a conflict guarantee, exactly as the skill says. Tasks
# whose likely paths intersect land in one sequential chain (input order preserved); every
# other task is a member of the single parallel group.
#
# Exit codes: 0 with a plan (an empty task list is reported as `tasks: []`, not raised);
# 2 usage; 3 jq missing.
#
# Usage: batch-plan.sh [--stack NAME] [--baseline-usd 2.40] -- "Task 1" "Task 2" ...
#        batch-plan.sh [--stack NAME] [--baseline-usd 2.40] --file PATH
set -uo pipefail

usage() {
    echo "usage: batch-plan.sh [--stack NAME] [--baseline-usd N] -- \"Task 1\" \"Task 2\" ... | --file PATH"
}

stack="auto-detect"; baseline="2.40"; file=""
tasks=()
while [ $# -gt 0 ]; do
    case "$1" in
        --stack)        stack="${2:-auto-detect}"; shift 2 ;;
        --baseline-usd) baseline="${2:-2.40}"; shift 2 ;;
        --file)         file="${2:-}"; shift 2 ;;
        --)             shift; while [ $# -gt 0 ]; do tasks+=("$1"); shift; done ;;
        -h|--help)      usage; exit 0 ;;
        -*)             usage >&2; exit 2 ;;
        *)              tasks+=("$1"); shift ;;
    esac
done

if ! command -v jq >/dev/null 2>&1; then
    printf '{"error":"jq is required to plan a batch"}\n'
    exit 3
fi
printf '%s' "$baseline" | grep -Eq '^[0-9]+(\.[0-9]+)?$' || { echo "error: --baseline-usd must be a number" >&2; exit 2; }

if [ -n "$file" ]; then
    [ -f "$file" ] || { echo "error: --file ${file} not found" >&2; exit 2; }
    while IFS= read -r line || [ -n "$line" ]; do
        line=$(printf '%s' "$line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')
        [ -n "$line" ] || continue
        case "$line" in \#*) continue ;; esac
        line=$(printf '%s' "$line" | sed -E 's/^[-*][[:space:]]+//')
        tasks+=("$line")
    done < "$file"
fi

slugify() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//' | cut -c1-40 | sed -E 's/-+$//'
}

likely_paths() {
    local text="$1" lower paths="" word
    lower=$(printf '%s' "$text" | tr '[:upper:]' '[:lower:]')
    add() { case " $paths " in *" $1 "*) ;; *) paths="${paths:+$paths }$1" ;; esac; }
    printf '%s' "$lower" | grep -Eq '(^|[^a-z])(endpoint|route|routes|api)([^a-z]|$)' && { add routes/; add controllers/; }
    printf '%s' "$lower" | grep -Eq '(^|[^a-z])(test|tests|spec|specs)([^a-z]|$)' && add tests/
    printf '%s' "$lower" | grep -Eq '(^|[^a-z])(migration|migrations|schema|table)([^a-z]|$)' && { add database/migrations/; add migrations/; }
    printf '%s' "$lower" | grep -Eq '(^|[^a-z])(model|models|entity|entities)([^a-z]|$)' && { add models/; add app/Models/; }
    printf '%s' "$lower" | grep -Eq '(^|[^a-z])(component|components|page|pages|ui|screen|screens)([^a-z]|$)' && { add components/; add pages/; add resources/js/; }
    printf '%s' "$lower" | grep -Eq '(^|[^a-z])(readme|docs|documentation)([^a-z]|$)' && { add README.md; add docs/; }
    for word in $text; do
        word=$(printf '%s' "$word" | sed -E 's/^[`"'"'"'(]+//; s/[`"'"'"'),.;:]+$//')
        case "$word" in
            */*) [ "${#word}" -gt 1 ] && add "$word" ;;
            *.php|*.ts|*.tsx|*.js|*.jsx|*.vue|*.py|*.java|*.cs|*.go|*.rb|*.md|*.json|*.yaml|*.yml|*.toml|*.sql|*.css|*.scss|*.html) add "$word" ;;
        esac
    done
    printf '%s' "$paths"
}

rows='[]'
for raw in "${tasks[@]+"${tasks[@]}"}"; do
    hint="unspecified"; text="$raw"
    case "$raw" in
        *"[simple]")  hint="simple";  text="${raw%\[simple\]}" ;;
        *"[complex]") hint="complex"; text="${raw%\[complex\]}" ;;
    esac
    text=$(printf '%s' "$text" | sed -E 's/[[:space:]]+$//')
    paths=$(likely_paths "$text")
    rows=$(jq -c --arg t "$text" --arg s "$(slugify "$text")" --arg h "$hint" --arg p "$paths" \
        '. + [{task: $t, task_slug: $s, complexity_hint: $h,
               likely_paths: (if $p == "" then [] else ($p | split(" ")) end)}]' <<<"$rows")
done

JQ_PROGRAM=$(cat <<'JQ'
def r2: (. * 100 | round) / 100;
def factor: if . == "simple" then 0.5 elif . == "complex" then 2 else 1 end;
def intersect($a; $b): [ $a[] | select(. as $x | $b | index($x)) ];
def dedupe: reduce .[] as $x ([]; if index($x) then . else . + [$x] end);

. as $tasks
| ($tasks | length) as $n
| (reduce range(0; $n) as $i ([];
    . as $groups
    | [ $groups[] | select(any(.[]; . as $j | (intersect($tasks[$j].likely_paths; $tasks[$i].likely_paths) | length) > 0)) ] as $hit
    | [ $groups[] | select(any(.[]; . as $j | (intersect($tasks[$j].likely_paths; $tasks[$i].likely_paths) | length) > 0) | not) ] as $rest
    | $rest + [ (($hit | add // []) + [$i]) | unique ])) as $components
| ([ $components[] | select(length == 1) | .[0] ] | sort) as $singles
| ([ $components[] | select(length > 1) ]) as $chains
| ($tasks | map(. + {estimated_cost_usd: (($baseline * (.complexity_hint | factor)) | r2)})) as $priced
| ([ $priced[] | .estimated_cost_usd ] | add // 0 | r2) as $total
| ( (if ($singles | length) > 0 then [{kind: "parallel", members: $singles}] else [] end)
    + [ $chains[] | . as $c
        | {kind: "sequential", members: $c,
           overlap: ([ range(0; $c | length - 1) as $k
                       | intersect($tasks[$c[$k]].likely_paths; $tasks[$c[$k + 1]].likely_paths)[] ] | dedupe)} ] ) as $groups
| ($groups | to_entries | map(.value + {index: (.key + 1)})) as $numbered
| ($priced | to_entries | map(.key as $k | .value + {index: ($k + 1),
      group: ([ $numbered[] | select(.members | index($k)) ] | first | .index)})) as $final
| ($final | map("   \(.index). \(.task_slug) [\(.complexity_hint)] — likely: \(if (.likely_paths | length) == 0 then "unknown" else (.likely_paths | join(", ")) end)") | join("\n")) as $scope_lines
| ($numbered | map(
      if .kind == "parallel"
      then "   Group \(.index) (parallel):\n" + ([ .members[] | "     - " + $tasks[.].task_slug ] | join("\n"))
      else "   Group \(.index) (sequential chain, overlap: \(.overlap | join(", "))):\n     - " + ([ .members[] | $tasks[.].task_slug ] | join(" → ")) end)
   | join("\n")) as $plan_lines
| ($singles | length) as $parallel_count
| {
    schema_version: 1,
    stack: $stack,
    baseline_usd: $baseline,
    tasks: ($final | map({index, task, task_slug, complexity_hint, likely_paths, group, estimated_cost_usd})),
    groups: ($numbered | map({index, kind, members: (.members | map(. + 1)), overlap: (.overlap // [])})),
    total_estimated_cost_usd: $total,
    group_count: ($numbered | length),
    parallel_task_count: $parallel_count,
    print_blocks: {
      scope: "📋 Batch scope (\($n) tasks):\n\($scope_lines)",
      plan: ("🧩 Execution plan:\n\($plan_lines)"
             + (if $stack != "auto-detect" then "\n   stack: \($stack) (forced for all tasks)" else "" end)
             + (if ($chains | length) > 0 then "\n   Note: chains are scheduling only — each worktree branches from the current base, so a chained task does not see the previous task's unmerged changes. Overlap is only resolved once a human merges each PR." else "" end)),
      cost: "💰 Estimated cost: $\($total) across \($n) tasks (\($numbered | length) groups, \($parallel_count) run in parallel)\n   Note: batch-dispatched pipelines auto-approve their own development plan\n   (no human-in-the-loop gate — tasks run unattended). Review each PR's diff\n   before merging.\n   Proceed? (yes / adjust / abort)"
    }
  }
JQ
)

printf '%s' "$rows" | jq --arg stack "$stack" --argjson baseline "$baseline" "$JQ_PROGRAM"
exit 0
