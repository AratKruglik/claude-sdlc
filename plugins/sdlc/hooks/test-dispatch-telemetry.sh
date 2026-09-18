#!/usr/bin/env bash
# Test suite for the dispatch-telemetry chain:
#   dispatch-log.sh (PreToolUse Agent + SubagentStart) → subagent-usage.sh (SubagentStop)
#   → scripts/usage-report.sh (pairing + attribution).
#
# Every case builds a throwaway project + fake $HOME under a temp root and never touches
# the real ~/.claude. Requires jq and python3 (the python3-only path is exercised via
# SDLC_HOOK_JSON_TOOL=python3).
#
# Run: bash plugins/sdlc/hooks/test-dispatch-telemetry.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DISPATCH="${SCRIPT_DIR}/dispatch-log.sh"
USAGE="${SCRIPT_DIR}/subagent-usage.sh"
REPORT="${SCRIPT_DIR}/../scripts/usage-report.sh"

for dep in jq python3; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        echo "SKIP: $dep not installed — cannot run test-dispatch-telemetry.sh"
        exit 0
    fi
done

pass_count=0
fail_count=0

assert_eq() {
    local case_name="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        pass_count=$((pass_count + 1)); printf 'PASS  %-72s = %s\n' "$case_name" "$actual"
    else
        fail_count=$((fail_count + 1)); printf 'FAIL  %-72s expected %q, got %q\n' "$case_name" "$expected" "$actual"
    fi
}

assert_field() {
    # $1 = case name, $2 = jq filter, $3 = expected, $4 = JSON
    local actual
    actual=$(printf '%s' "$4" | jq -r "$2" 2>/dev/null)
    assert_eq "$1 [$2]" "$3" "$actual"
}

iso_offset() {
    local off="$1" gnu_expr=""
    case "$off" in
        -*M) gnu_expr="${off#-}"; gnu_expr="${gnu_expr%M} minutes ago" ;;
        -*H) gnu_expr="${off#-}"; gnu_expr="${gnu_expr%H} hours ago" ;;
    esac
    if [ -n "$gnu_expr" ] && date -u -d "$gnu_expr" +"%Y-%m-%dT%H:%M:%S+00:00" 2>/dev/null; then
        return 0
    fi
    date -u -v"$off" +"%Y-%m-%dT%H:%M:%S+00:00"
}

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/sdlc-telemetry-test.XXXXXX")
trap 'rm -rf "$TMP_ROOT"' EXIT

SESSION="sess-0001"

fresh_project() {
    # $1 = name → sets globals PROJ (project dir) and FAKE_HOME (per-project fake ~).
    # Called directly, not in $(...): the globals must reach the caller's shell.
    PROJ="${TMP_ROOT}/$1"
    rm -rf "$PROJ"
    mkdir -p "$PROJ/.claude"
    FAKE_HOME="${TMP_ROOT}/home-$1"
    rm -rf "$FAKE_HOME"
    mkdir -p "$FAKE_HOME/.claude/projects/-tmp-$1/${SESSION}/subagents"
}

write_marker() {
    # $1 = project, $2 = started_at, $3 = optional updated_at
    local upd=""
    [ -n "${3:-}" ] && upd=",\"updated_at\":\"$3\""
    printf '{"task_slug":"demo-slug","started_at":"%s"%s,"roster":["sdlc:qa-engineer"],"phase_agents":{"qa":"sdlc:qa-engineer"}}\n' "$2" "$upd" \
        > "$1/.claude/.sdlc-run-active.json"
}

parent_transcript() {
    printf '%s/.claude/projects/-tmp-%s/%s.jsonl' "$FAKE_HOME" "$1" "$SESSION"
}

write_transcript() {
    # $1 = project name, $2 = agent_id, $3 = model, $4.. = lines "id:in:out:cw:cr" (same id repeats allowed)
    local proj="$1" id="$2" model="$3"; shift 3
    local f="${FAKE_HOME}/.claude/projects/-tmp-${proj}/${SESSION}/subagents/agent-${id}.jsonl"
    : > "$f"
    printf '{"type":"user","message":{"role":"user","content":"hi"}}\n' >> "$f"
    for spec in "$@"; do
        IFS=: read -r mid in out cw cr <<< "$spec"
        printf '{"type":"assistant","message":{"id":"%s","model":"%s","usage":{"input_tokens":%s,"output_tokens":%s,"cache_creation_input_tokens":%s,"cache_read_input_tokens":%s}}}\n' \
            "$mid" "$model" "$in" "$out" "$cw" "$cr" >> "$f"
    done
    printf 'this line is not json\n' >> "$f"
}

run_pre() {
    # $1 = project, $2 = subagent_type, $3 = description
    HOME="$FAKE_HOME" bash "$DISPATCH" <<EOF
{"hook_event_name":"PreToolUse","tool_name":"Agent","cwd":"$1","tool_input":{"subagent_type":"$2","description":"$3"}}
EOF
}

run_start() {
    # $1 = project, $2 = agent_id, $3 = agent_type
    HOME="$FAKE_HOME" bash "$DISPATCH" <<EOF
{"hook_event_name":"SubagentStart","cwd":"$1","session_id":"$SESSION","agent_id":"$2","agent_type":"$3"}
EOF
}

run_stop() {
    # $1 = project, $2 = project name, $3 = agent_id, $4 = agent_type, $5 = last message
    HOME="$FAKE_HOME" bash "$USAGE" <<EOF
{"hook_event_name":"SubagentStop","cwd":"$1","session_id":"$SESSION","agent_id":"$3","agent_type":"$4","last_assistant_message":"$5","transcript_path":"$(parent_transcript "$2")"}
EOF
}

report() {
    bash "$REPORT" demo-slug --project-root "$1"
}

log_of() { printf '%s/docs/plans/demo-slug/_usage.jsonl' "$1"; }

echo "=== dispatch telemetry test suite ==="
echo

# ── Case 1: no marker → nothing written, no stdout ──
fresh_project "case1"
OUT=$(run_pre "$PROJ" "sdlc:qa-engineer" "Phase 3/5: qa")
assert_eq "case1 no marker: silent" "" "$OUT"
assert_eq "case1 no marker: no log" "absent" "$([ -f "$(log_of "$PROJ")" ] && echo present || echo absent)"

# ── Case 2: stale marker (8h) → nothing written ──
fresh_project "case2"
write_marker "$PROJ" "$(iso_offset -8H)"
run_pre "$PROJ" "sdlc:qa-engineer" "Phase 3/5: qa" >/dev/null
assert_eq "case2 stale marker: no log" "absent" "$([ -f "$(log_of "$PROJ")" ] && echo present || echo absent)"

# ── Case 3: stale started_at but fresh updated_at → written (resume keeps hooks alive) ──
fresh_project "case3"
write_marker "$PROJ" "$(iso_offset -8H)" "$(iso_offset -5M)"
run_pre "$PROJ" "sdlc:qa-engineer" "Phase 3/5: qa" >/dev/null
assert_eq "case3 updated_at refreshes freshness" "1" "$(wc -l < "$(log_of "$PROJ")" | tr -d ' ')"

# ── Case 4: full happy path, description with aspect + pass, dedupe by message.id ──
fresh_project "case4"
write_marker "$PROJ" "$(iso_offset -10M)"
OUT=$(run_pre "$PROJ" "laravel-plugin:laravel-architect" "Phase 2/5: development — backend [pass:plan]")
assert_eq "case4 PreToolUse silent" "" "$OUT"
run_start "$PROJ" "agent-A" "laravel-plugin:laravel-architect"
write_transcript "case4" "agent-A" "claude-opus-5" "m1:1000:50:200:300" "m1:1000:50:200:300" "m2:500:25:0:900"
run_stop "$PROJ" "case4" "agent-A" "laravel-architect" "PLAN READY"
LOG=$(cat "$(log_of "$PROJ")")
assert_eq "case4 three rows" "3" "$(printf '%s\n' "$LOG" | wc -l | tr -d ' ')"
PENDING=$(printf '%s\n' "$LOG" | sed -n 1p)
assert_field "case4 pending phase" '.phase' "development" "$PENDING"
assert_field "case4 pending aspect" '.aspect' "backend" "$PENDING"
assert_field "case4 pending pass" '.pass' "plan" "$PENDING"
assert_field "case4 pending bare agent_type" '.agent_type' "laravel-architect" "$PENDING"
STOP=$(printf '%s\n' "$LOG" | sed -n 3p)
assert_field "case4 dedupe: input tokens (1000+500)" '.input_tokens' "1500" "$STOP"
assert_field "case4 dedupe: turns" '.turns' "2" "$STOP"
assert_field "case4 cache read summed" '.cache_read_input_tokens' "1200" "$STOP"
assert_field "case4 model captured" '.model' "claude-opus-5" "$STOP"
# opus: (1500*5 + 200*5*1.25 + 1200*5*0.1 + 75*25)/1e6 = (7500+1250+600+1875)/1e6 = 0.011225
assert_field "case4 cost priced at opus tier" '.cost_usd' "0.011225" "$STOP"
assert_field "case4 measured" '.usage_source' "measured" "$STOP"
assert_field "case4 last_message_chars" '.last_message_chars' "10" "$STOP"
REP=$(report "$PROJ")
assert_field "case4 report: one dispatch" '.dispatches | length' "1" "$REP"
assert_field "case4 report: status completed" '.dispatches[0].status' "completed" "$REP"
assert_field "case4 report: phase attributed" '.dispatches[0].phase' "development" "$REP"
assert_field "case4 report: total cost" '.total_cost_usd' "0.011225" "$REP"
assert_field "case4 report: not nested" '.dispatches[0].nested' "false" "$REP"

# ── Case 5: two qa-engineer dispatches, stops out of order → paired by agent_id ──
fresh_project "case5"
write_marker "$PROJ" "$(iso_offset -10M)"
run_pre "$PROJ" "sdlc:qa-engineer" "Phase 3/4: qa — backend"
run_pre "$PROJ" "sdlc:qa-engineer" "Phase 3/4: qa — frontend"
run_start "$PROJ" "agent-B1" "qa-engineer"
run_start "$PROJ" "agent-B2" "qa-engineer"
write_transcript "case5" "agent-B1" "claude-sonnet-5" "x1:100:10:0:0"
write_transcript "case5" "agent-B2" "claude-sonnet-5" "y1:200:20:0:0"
run_stop "$PROJ" "case5" "agent-B2" "qa-engineer" "frontend done"
run_stop "$PROJ" "case5" "agent-B1" "qa-engineer" "backend done"
REP=$(report "$PROJ")
assert_field "case5 two dispatches" '.dispatches | length' "2" "$REP"
assert_field "case5 B1 is backend" '[.dispatches[] | select(.agent_id=="agent-B1")][0].aspect' "backend" "$REP"
assert_field "case5 B2 is frontend" '[.dispatches[] | select(.agent_id=="agent-B2")][0].aspect' "frontend" "$REP"
assert_field "case5 B1 tokens" '[.dispatches[] | select(.agent_id=="agent-B1")][0].input_tokens' "100" "$REP"
assert_field "case5 B2 tokens" '[.dispatches[] | select(.agent_id=="agent-B2")][0].input_tokens' "200" "$REP"

# ── Case 6: pending without start → not_started ──
fresh_project "case6"
write_marker "$PROJ" "$(iso_offset -10M)"
run_pre "$PROJ" "tester" "Phase 3/4: qa"
REP=$(report "$PROJ")
assert_field "case6 not_started" '.dispatches[0].status' "not_started" "$REP"
assert_field "case6 summary counts not_started" '.usage_source_summary.not_started' "1" "$REP"

# ── Case 7: nested dispatch inside a single phase agent → attributed; ambiguous → unattributed ──
fresh_project "case7"
write_marker "$PROJ" "$(iso_offset -10M)"
run_pre "$PROJ" "sdlc:security-analyst" "Phase 3/4: security"
run_start "$PROJ" "agent-S" "security-analyst"
sleep 1
run_pre "$PROJ" "general-purpose" "Trace callers of PaymentService"
run_start "$PROJ" "agent-N1" "general-purpose"
write_transcript "case7" "agent-N1" "claude-haiku-4-5-20251001" "n1:1000:100:0:0"
run_stop "$PROJ" "case7" "agent-N1" "general-purpose" "found 3 callers"
write_transcript "case7" "agent-S" "claude-opus-5" "s1:100:10:0:0"
run_stop "$PROJ" "case7" "agent-S" "security-analyst" "ISSUES_FOUND: critical=0"
REP=$(report "$PROJ")
assert_field "case7 nested flagged" '[.dispatches[] | select(.agent_id=="agent-N1")][0].nested' "true" "$REP"
assert_field "case7 nested attributed to security" '[.dispatches[] | select(.agent_id=="agent-N1")][0].phase' "security" "$REP"
assert_field "case7 nested attributed_to agent id" '[.dispatches[] | select(.agent_id=="agent-N1")][0].attributed_to' "agent-S" "$REP"
# haiku: (1000*1 + 100*5)/1e6 = 0.0015 ; opus: (100*5 + 10*25)/1e6 = 0.00075
assert_field "case7 nested cost separate" '.nested_cost_usd' "0.0015" "$REP"
assert_field "case7 phase cost excludes nested" '.total_cost_usd' "0.00075" "$REP"
assert_field "case7 including nested" '.total_cost_usd_including_nested' "0.00225" "$REP"

fresh_project "case7b"
write_marker "$PROJ" "$(iso_offset -10M)"
run_pre "$PROJ" "sdlc:qa-engineer" "Phase 3/4: qa"
run_pre "$PROJ" "sdlc:security-analyst" "Phase 3/4: security"
run_start "$PROJ" "agent-Q" "qa-engineer"
run_start "$PROJ" "agent-S" "security-analyst"
sleep 1
run_pre "$PROJ" "Explore" "look around"
run_start "$PROJ" "agent-N2" "Explore"
write_transcript "case7b" "agent-N2" "claude-haiku-4-5-20251001" "n2:1000:0:0:0"
run_stop "$PROJ" "case7b" "agent-N2" "Explore" "ok"
REP=$(report "$PROJ")
assert_field "case7b ambiguous nested stays unattributed" '[.dispatches[] | select(.agent_id=="agent-N2")][0].phase' "null" "$REP"
assert_field "case7b ambiguous nested still costed" '.nested_cost_usd' "0.001" "$REP"

# ── Case 8: transcript missing → stop row with transcript_missing ──
fresh_project "case8"
write_marker "$PROJ" "$(iso_offset -10M)"
run_pre "$PROJ" "sdlc:document-writer" "Phase 4/4: documentation"
run_start "$PROJ" "agent-D" "document-writer"
run_stop "$PROJ" "case8" "agent-D" "document-writer" "PR_URL: x"
STOP=$(tail -n1 "$(log_of "$PROJ")")
assert_field "case8 transcript_missing" '.usage_source' "transcript_missing" "$STOP"
assert_field "case8 null tokens" '.input_tokens' "null" "$STOP"
REP=$(report "$PROJ")
assert_field "case8 report status unmeasured" '.dispatches[0].status' "unmeasured" "$REP"

# ── Case 9: unknown model → cost null + pricing_note ──
fresh_project "case9"
write_marker "$PROJ" "$(iso_offset -10M)"
run_pre "$PROJ" "sdlc:qa-engineer" "Phase 3/4: qa"
run_start "$PROJ" "agent-U" "qa-engineer"
write_transcript "case9" "agent-U" "some-future-model" "u1:100:10:0:0"
run_stop "$PROJ" "case9" "agent-U" "qa-engineer" "done"
STOP=$(tail -n1 "$(log_of "$PROJ")")
assert_field "case9 unknown model cost null" '.cost_usd' "null" "$STOP"
assert_field "case9 pricing_note" '.pricing_note' "unknown model" "$STOP"
assert_field "case9 tokens still measured" '.input_tokens' "100" "$STOP"

# ── Case 10: python3-only path produces identical rows ──
fresh_project "case10"
write_marker "$PROJ" "$(iso_offset -10M)"
export SDLC_HOOK_JSON_TOOL=python3
run_pre "$PROJ" "sdlc:qa-engineer" "Phase 3/4: qa — frontend [pass:verify]"
run_start "$PROJ" "agent-P" "qa-engineer"
write_transcript "case10" "agent-P" "claude-sonnet-5" "p1:1000:50:200:300" "p1:1000:50:200:300"
run_stop "$PROJ" "case10" "agent-P" "qa-engineer" "verified"
unset SDLC_HOOK_JSON_TOOL
LOG=$(cat "$(log_of "$PROJ")")
PENDING=$(printf '%s\n' "$LOG" | sed -n 1p)
STOP=$(printf '%s\n' "$LOG" | sed -n 3p)
assert_field "case10 py pending aspect" '.aspect' "frontend" "$PENDING"
assert_field "case10 py pending pass" '.pass' "verify" "$PENDING"
assert_field "case10 py dedupe input" '.input_tokens' "1000" "$STOP"
# sonnet: (1000*3 + 200*3*1.25 + 300*3*0.1 + 50*15)/1e6 = (3000+750+90+750)/1e6 = 0.00459
assert_field "case10 py cost sonnet" '.cost_usd' "0.00459" "$STOP"

# ── Case 11: non-Agent PreToolUse and non-contract description ──
fresh_project "case11"
write_marker "$PROJ" "$(iso_offset -10M)"
HOME="$FAKE_HOME" bash "$DISPATCH" <<EOF
{"hook_event_name":"PreToolUse","tool_name":"Bash","cwd":"$PROJ","tool_input":{"command":"ls"}}
EOF
assert_eq "case11 Bash PreToolUse ignored" "absent" "$([ -f "$(log_of "$PROJ")" ] && echo present || echo absent)"
run_pre "$PROJ" "general-purpose" "Regression test verification for X"
PENDING=$(tail -n1 "$(log_of "$PROJ")")
assert_field "case11 free-form description → phase null" '.phase' "null" "$PENDING"

echo
echo "=== ${pass_count} passed, ${fail_count} failed ==="
[ "$fail_count" -eq 0 ]
