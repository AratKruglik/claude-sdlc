#!/usr/bin/env bash
# Test harness for agent-result-context.sh (PostToolUse(Agent) telemetry context).
#
# Fixtures write a complete pending/start/stop trio into a throwaway project's _usage.jsonl
# so usage-report.sh produces a measured record. Nothing touches the real repo.
#
# Run: bash plugins/sdlc/hooks/test-agent-result-context.sh
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${HOOK_DIR}/agent-result-context.sh"

command -v jq >/dev/null 2>&1 || { echo "SKIP: jq not available"; exit 0; }

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-agent-ctx.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

pass_count=0
fail_count=0

assert_eq() {
    local case_name="$1" expected="$2" actual="$3"
    if [ "$expected" = "$actual" ]; then
        pass_count=$((pass_count + 1)); printf 'PASS  %-68s = %s\n' "$case_name" "$actual"
    else
        fail_count=$((fail_count + 1)); printf 'FAIL  %-68s expected %q, got %q\n' "$case_name" "$expected" "$actual"
    fi
}

assert_contains() {
    local case_name="$1" needle="$2" haystack="$3"
    case "$haystack" in
        *"$needle"*) pass_count=$((pass_count + 1)); printf 'PASS  %-68s contains %q\n' "$case_name" "$needle" ;;
        *) fail_count=$((fail_count + 1)); printf 'FAIL  %-68s missing %q in %q\n' "$case_name" "$needle" "$haystack" ;;
    esac
}

context() { [ -n "$1" ] && printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null; }

now_iso() { date -u +"%Y-%m-%dT%H:%M:%S+00:00"; }

# Sets the global PROJ. $2 = max_total_cost_usd JSON literal (null or a number).
fresh_project() {
    PROJ="${TMP_ROOT}/$1"
    rm -rf "$PROJ"
    mkdir -p "$PROJ/.claude" "$PROJ/docs/plans/demo"
    jq -cn --arg ts "$(now_iso)" --argjson cap "${2:-null}" '{schema_version:2, task_slug:"demo",
        started_at:$ts, updated_at:$ts, active_workflow:"default", max_total_cost_usd:$cap,
        resolved_phases:[["business_analysis"],["development"],["qa","security"],["documentation"]],
        phase_status:{business_analysis:"completed","development/backend":"completed",qa:"pending",security:"pending",documentation:"pending"},
        git_flow:{task_type:"feature",base_branch:"main"}}' > "$PROJ/.claude/.sdlc-run-active.json"
}

# $1 = project, $2 = agent_type, $3 = description, $4 = agent_id, $5 = cost_usd, $6 = last_message_chars
write_trio() {
    local log="$1/docs/plans/demo/_usage.jsonl" ts
    ts=$(now_iso)
    jq -cn --arg ts "$ts" --arg at "$2" --arg d "$3" '{event:"pending",ts:$ts,agent_type:$at,description:$d,
        phase:(if ($d|startswith("Phase ")) then ($d|sub("^Phase [^:]*: ";"")|sub(" — .*$";"")|sub(" \\[pass:.*$";"")) else null end),
        aspect:(($d|capture(" — (?<a>[^ \\[]+)")|.a) // null),
        pass:(($d|capture("\\[pass:(?<p>[^\\]]+)\\]")|.p) // null)}' >> "$log"
    jq -cn --arg ts "$ts" --arg at "$2" --arg id "$4" '{event:"start",ts:$ts,agent_id:$id,agent_type:$at}' >> "$log"
    jq -cn --arg ts "$ts" --arg at "$2" --arg id "$4" --argjson cost "$5" --argjson lc "${6:-1200}" \
        '{event:"stop",ts:$ts,agent_id:$id,agent_type:$at,model:"claude-sonnet-5",input_tokens:30000,output_tokens:2000,
          cache_creation_input_tokens:4000,cache_read_input_tokens:20000,turns:9,cost_usd:$cost,pricing_note:null,
          last_message_chars:$lc,usage_source:"measured"}' >> "$log"
}

# $1 = project, $2 = subagent_type, $3 = description
run_hook() {
    bash "$HOOK" <<EOF
{"hook_event_name":"PostToolUse","tool_name":"Agent","cwd":"$1","session_id":"s1","tool_input":{"subagent_type":"$2","description":"$3","prompt":"…"},"tool_response":{}}
EOF
}

echo "=== agent-result-context ==="
echo

fresh_project "measured" null
write_trio "$PROJ" "qa-engineer" "Phase 3/4: qa" "a1" 0.07
OUT=$(run_hook "$PROJ" "sdlc:qa-engineer" "Phase 3/4: qa")
CTX=$(context "$OUT")
assert_contains "measured record -> telemetry line names the dispatch" "SDLC telemetry for Phase 3/4: qa" "$CTX"
assert_contains "measured record -> usage_source=measured" "usage_source=measured" "$CTX"
assert_contains "measured record -> cost is carried" "cost_usd=0.07" "$CTX"
assert_contains "measured record -> running total line" "Running total: phases=\$0.07" "$CTX"
case "$CTX" in *"💸"*) assert_eq "no cap -> no 💸 block" "absent" "present" ;; *) assert_eq "no cap -> no 💸 block" "absent" "absent" ;; esac

fresh_project "capped" 0.05
write_trio "$PROJ" "qa-engineer" "Phase 3/4: qa" "a2" 0.07
OUT=$(run_hook "$PROJ" "sdlc:qa-engineer" "Phase 3/4: qa")
CTX=$(context "$OUT")
assert_contains "cap exceeded -> 💸 block" "💸 Cost cap exceeded for workflow 'default'" "$CTX"
assert_contains "cap exceeded -> cap and spend" "Cap: \$0.05   Spent so far: \$0.07" "$CTX"
assert_contains "cap exceeded -> remaining phases from state" "Remaining phases: qa, security, documentation" "$CTX"

fresh_project "oversized" null
write_trio "$PROJ" "qa-engineer" "Phase 3/4: qa" "a3" 0.07 13000
OUT=$(run_hook "$PROJ" "sdlc:qa-engineer" "Phase 3/4: qa")
assert_contains "oversized handoff -> violation flag" "compact_handoff_violation: true" "$(context "$OUT")"

fresh_project "freeform" null
write_trio "$PROJ" "Explore" "Look for similar features" "a4" 0.01
OUT=$(run_hook "$PROJ" "Explore" "Look for similar features")
assert_eq "free-form description -> quiet" "" "$OUT"

fresh_project "no-state" null
rm -f "$PROJ/.claude/.sdlc-run-active.json"
write_trio "$PROJ" "qa-engineer" "Phase 3/4: qa" "a5" 0.07
OUT=$(run_hook "$PROJ" "sdlc:qa-engineer" "Phase 3/4: qa")
assert_eq "no run state -> quiet" "" "$OUT"

fresh_project "latest-wins" null
write_trio "$PROJ" "qa-engineer" "Phase 3/4: qa" "a6" 0.03
sleep 1
write_trio "$PROJ" "qa-engineer" "Phase 3/4: qa" "a7" 0.09
OUT=$(run_hook "$PROJ" "sdlc:qa-engineer" "Phase 3/4: qa")
assert_contains "two dispatches of one phase -> latest record reported" "cost_usd=0.09" "$(context "$OUT")"

fresh_project "post-check" null
write_trio "$PROJ" "laravel-architect" "Phase 2/5: development — backend [pass:implement]" "pc1" 0.30
jq -cn '{event:"post_check",agent_id:"pc0",ts:"t",message:"stale finding of another agent"}' >> "$PROJ/docs/plans/demo/_usage.jsonl"
jq -cn '{event:"post_check",agent_id:"pc1",ts:"t",message:"Post-implement check after laravel-architect reported problems: app/Foo.php:12"}' >> "$PROJ/docs/plans/demo/_usage.jsonl"
CTX=$(context "$(run_hook "$PROJ" "laravel-plugin:laravel-architect" "Phase 2/5: development — backend [pass:implement]")")
assert_contains "post_check row of this agent -> relayed to the orchestrator" "app/Foo.php:12" "$CTX"
case "$CTX" in *"stale finding"*) assert_eq "post_check of another agent -> not relayed" "absent" "present" ;; *) assert_eq "post_check of another agent -> not relayed" "absent" "absent" ;; esac

jq -cn --arg m "$(printf 'x%.0s' $(seq 1 12000))" '{event:"post_check",agent_id:"pc1",ts:"t",message:$m}' >> "$PROJ/docs/plans/demo/_usage.jsonl"
CTX=$(context "$(run_hook "$PROJ" "laravel-plugin:laravel-architect" "Phase 2/5: development — backend [pass:implement]")")
assert_eq "long post_check -> context stays under the 10K cap" "true" "$(jq -Rsn --arg c "$CTX" '$c | length < 10000')"
assert_contains "long post_check -> truncation is stated" "truncated" "$CTX"

echo
printf '%d passed, %d failed\n' "$pass_count" "$fail_count"
[ "$fail_count" -eq 0 ]
