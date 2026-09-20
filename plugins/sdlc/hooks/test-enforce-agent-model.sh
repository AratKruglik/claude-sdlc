#!/usr/bin/env bash
# Payload-level test harness for enforce-agent-model.sh.
#
# Feeds synthetic PreToolUse stdin payloads at the hook and asserts on its JSON
# output. Each case builds a throwaway project directory under a temp root,
# points CLAUDE_PROJECT_DIR at it, and never touches the real repo or ~/.claude.
#
# Run: bash plugins/sdlc/hooks/test-enforce-agent-model.sh
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="${SCRIPT_DIR}/enforce-agent-model.sh"

pass_count=0
fail_count=0

# $1 = case name, $2 = jq filter, $3 = expected value, $4 = actual JSON
assert_field() {
    local case_name="$1" filter="$2" expected="$3" json="$4"
    local actual
    actual=$(printf '%s' "$json" | jq -r "$filter" 2>/dev/null)
    if [ "$actual" = "$expected" ]; then
        pass_count=$((pass_count + 1))
        printf 'PASS  %-70s %s = %s\n' "$case_name" "$filter" "$actual"
    else
        fail_count=$((fail_count + 1))
        printf 'FAIL  %-70s %s: expected %q, got %q\n' "$case_name" "$filter" "$expected" "$actual"
    fi
}

# $1 = case name, $2 = jq filter, $3 = substring expected in the value, $4 = actual JSON
assert_contains() {
    local case_name="$1" filter="$2" needle="$3" json="$4"
    local actual
    actual=$(printf '%s' "$json" | jq -r "$filter" 2>/dev/null)
    if printf '%s' "$actual" | grep -qF -- "$needle"; then
        pass_count=$((pass_count + 1))
        printf 'PASS  %-70s %s contains %q\n' "$case_name" "$filter" "$needle"
    else
        fail_count=$((fail_count + 1))
        printf 'FAIL  %-70s %s: expected to contain %q, got %q\n' "$case_name" "$filter" "$needle" "$actual"
    fi
}

assert_valid_json() {
    local case_name="$1" json="$2"
    if printf '%s' "$json" | jq . >/dev/null 2>&1; then
        pass_count=$((pass_count + 1))
        printf 'PASS  %-70s valid JSON\n' "$case_name"
    else
        fail_count=$((fail_count + 1))
        printf 'FAIL  %-70s NOT valid JSON: %s\n' "$case_name" "$json"
    fi
}

iso_offset() {
    # $1 = BSD -v style offset relative to now (UTC), e.g. "-10M" or "-8H".
    # Try GNU `date -d` first (portable to Linux CI), fall back to BSD `date -v`
    # (this hook's own timestamp math uses the same GNU-then-BSD order).
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

run_hook() {
    # $1 = CLAUDE_PROJECT_DIR, $2 = payload JSON, $3 = optional CLAUDE_PLUGIN_ROOT
    if [ -n "${3:-}" ]; then
        CLAUDE_PROJECT_DIR="$1" CLAUDE_PLUGIN_ROOT="$3" bash "$HOOK" <<< "$2"
    else
        CLAUDE_PROJECT_DIR="$1" bash "$HOOK" <<< "$2"
    fi
}

TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT

fresh_project() {
    # $1 = project dir name (relative to TMP_ROOT)
    local proj="${TMP_ROOT}/$1"
    rm -rf "$proj"
    mkdir -p "$proj/.claude/agents" "$proj/plugins/sdlc/agents"
    cp "${SCRIPT_DIR}/../agents/qa-engineer.md" "$proj/plugins/sdlc/agents/qa-engineer.md"
    cp "${SCRIPT_DIR}/../agents/developer.md" "$proj/plugins/sdlc/agents/developer.md"
    printf '%s' "$proj"
}

write_marker() {
    # $1 = project dir, $2 = started_at ISO, $3 = roster JSON array, $4 = phase_agents JSON object
    cat > "$1/.claude/.sdlc-run-active.json" <<EOF
{"task_slug":"test-slug","started_at":"$2","roster":$3,"phase_agents":$4}
EOF
}

echo "=== enforce-agent-model.sh test suite ==="
echo

# ── Case 1: off-roster local agent, marker active → deny + both channels ──
PROJ=$(fresh_project "case1")
cat > "$PROJ/.claude/agents/tester.md" <<'EOF'
---
name: tester
---
Local tester agent.
EOF
write_marker "$PROJ" "$(iso_offset -10M)" '["sdlc:qa-engineer","sdlc:security-analyst"]' '{"qa":"sdlc:qa-engineer","security":"sdlc:security-analyst"}'
OUT=$(run_hook "$PROJ" '{"tool_name":"Agent","tool_input":{"subagent_type":"tester","description":"Regression test verification for timezone fix"}}')
assert_valid_json "case1 valid JSON" "$OUT"
assert_field "case1 off-roster local agent denied" '.hookSpecificOutput.permissionDecision' "deny" "$OUT"
assert_contains "case1 reason names roster agent" '.hookSpecificOutput.permissionDecisionReason' "sdlc:qa-engineer" "$OUT"
assert_field "case1 systemMessage present" '.systemMessage | length > 0' "true" "$OUT"

# ── Case 2: same local agent, no marker → allow + not-found warning ──
PROJ=$(fresh_project "case2")
cat > "$PROJ/.claude/agents/tester.md" <<'EOF'
---
name: tester
---
Local tester agent.
EOF
OUT=$(run_hook "$PROJ" '{"tool_name":"Agent","tool_input":{"subagent_type":"tester","description":"whatever"}}')
assert_valid_json "case2 valid JSON" "$OUT"
assert_field "case2 no marker allows" '.hookSpecificOutput.permissionDecision' "allow" "$OUT"
assert_contains "case2 not-found warning present" '.systemMessage' "not found" "$OUT"

# ── Case 3: tester listed in roster via agent_overrides → allow ──
PROJ=$(fresh_project "case3")
cat > "$PROJ/.claude/agents/tester.md" <<'EOF'
---
name: tester
---
Local tester agent.
EOF
write_marker "$PROJ" "$(iso_offset -10M)" '["sdlc:qa-engineer","tester"]' '{"qa":"tester"}'
OUT=$(run_hook "$PROJ" '{"tool_name":"Agent","tool_input":{"subagent_type":"tester","description":"Phase 3/6: qa"}}')
assert_valid_json "case3 valid JSON" "$OUT"
assert_field "case3 overridden agent allowed" '.hookSpecificOutput.permissionDecision' "allow" "$OUT"

# ── Case 4: general-purpose (built-in), marker active → allow ──
PROJ=$(fresh_project "case4")
write_marker "$PROJ" "$(iso_offset -10M)" '["sdlc:qa-engineer"]' '{"qa":"sdlc:qa-engineer"}'
OUT=$(run_hook "$PROJ" '{"tool_name":"Agent","tool_input":{"subagent_type":"general-purpose","description":"whatever"}}')
assert_valid_json "case4 valid JSON" "$OUT"
assert_field "case4 built-in allowed" '.hookSpecificOutput.permissionDecision' "allow" "$OUT"

# ── Case 5: off-roster PLUGIN agent (sdlc:developer during qa), marker active → allow ──
# Realistic fixture: the project ALSO ships a same-named local agent (.claude/agents/
# developer.md), matching the reporting user's actual project. Without the qualified-
# dispatch guard in the hook, this bare-name collision would have caused a false-positive
# deny of a perfectly legitimate plugin agent.
PROJ=$(fresh_project "case5")
cat > "$PROJ/.claude/agents/developer.md" <<'EOF'
---
name: developer
---
Local developer agent (name collides with the sdlc:developer plugin agent).
EOF
write_marker "$PROJ" "$(iso_offset -10M)" '["sdlc:qa-engineer"]' '{"qa":"sdlc:qa-engineer"}'
OUT=$(run_hook "$PROJ" '{"tool_name":"Agent","tool_input":{"subagent_type":"sdlc:developer","description":"Phase 3/6: qa"}}')
assert_valid_json "case5 valid JSON" "$OUT"
assert_field "case5 off-roster plugin agent allowed despite same-named local file" '.hookSpecificOutput.permissionDecision' "allow" "$OUT"

# ── Case 10: UNQUALIFIED dispatch of a bare name that collides with a local agent,
# marker active, off-roster → deny. This is the retry-fallback scenario the fix closes:
# if the orchestrator ever fell back to a bare "developer" after a qualified-dispatch
# error, it must NOT be silently allowed just because "sdlc:developer" is in the roster.
PROJ=$(fresh_project "case10")
cat > "$PROJ/.claude/agents/developer.md" <<'EOF'
---
name: developer
---
Local developer agent.
EOF
write_marker "$PROJ" "$(iso_offset -10M)" '["sdlc:qa-engineer","sdlc:developer"]' '{"qa":"sdlc:qa-engineer"}'
OUT=$(run_hook "$PROJ" '{"tool_name":"Agent","tool_input":{"subagent_type":"developer","description":"Phase 3/6: qa"}}')
assert_valid_json "case10 valid JSON" "$OUT"
assert_field "case10 bare-name collision still denied despite qualified roster entry" '.hookSpecificOutput.permissionDecision' "deny" "$OUT"

# ── Case 6: sdlc:qa-engineer, marker active, model absent → allow + updatedInput sonnet ──
PROJ=$(fresh_project "case6")
write_marker "$PROJ" "$(iso_offset -10M)" '["sdlc:qa-engineer"]' '{"qa":"sdlc:qa-engineer"}'
OUT=$(run_hook "$PROJ" '{"tool_name":"Agent","tool_input":{"subagent_type":"sdlc:qa-engineer","description":"Phase 3/6: qa"}}')
assert_valid_json "case6 valid JSON" "$OUT"
assert_field "case6 model corrected to sonnet" '.hookSpecificOutput.updatedInput.model' "sonnet" "$OUT"

# ── Case 7: laravel-architect with [pass:plan] → model_plan tier ──
PROJ=$(fresh_project "case7")
mkdir -p "$PROJ/plugins/laravel-plugin/agents"
cat > "$PROJ/plugins/laravel-plugin/agents/laravel-architect.md" <<'EOF'
---
name: laravel-architect
model: sonnet
model_plan: opus
---
Test agent.
EOF
OUT=$(run_hook "$PROJ" '{"tool_name":"Agent","tool_input":{"subagent_type":"laravel-plugin:laravel-architect","description":"Phase 2/6: development [pass:plan]"}}')
assert_valid_json "case7 valid JSON" "$OUT"
assert_field "case7 planning pass resolves model_plan" '.hookSpecificOutput.updatedInput.model' "opus" "$OUT"

# ── Case 8: agent .md present in both 1.2.1 and 1.3.0 → resolves 1.3.0 deterministically ──
PROJ=$(fresh_project "case8")
mkdir -p "$PROJ/plugins2/sdlc-marketplace/sdlc/1.2.1/agents" "$PROJ/plugins2/sdlc-marketplace/sdlc/1.3.0/agents"
cat > "$PROJ/plugins2/sdlc-marketplace/sdlc/1.2.1/agents/qa-engineer.md" <<'EOF'
---
name: qa-engineer
model: haiku
---
old version
EOF
cat > "$PROJ/plugins2/sdlc-marketplace/sdlc/1.3.0/agents/qa-engineer.md" <<'EOF'
---
name: qa-engineer
model: sonnet
---
new version
EOF
OUT=$(run_hook "$PROJ" '{"tool_name":"Agent","tool_input":{"subagent_type":"qa-engineer","description":"Phase 3/6: qa"}}' "$PROJ/plugins2/sdlc-marketplace/sdlc/1.3.0")
assert_valid_json "case8 valid JSON" "$OUT"
assert_field "case8 resolves newest installed version" '.hookSpecificOutput.updatedInput.model' "sonnet" "$OUT"

# ── Case 9: marker started_at 8h old → treated as absent, allow ──
PROJ=$(fresh_project "case9")
cat > "$PROJ/.claude/agents/tester.md" <<'EOF'
---
name: tester
---
Local tester agent.
EOF
write_marker "$PROJ" "$(iso_offset -8H)" '["sdlc:qa-engineer"]' '{}'
OUT=$(run_hook "$PROJ" '{"tool_name":"Agent","tool_input":{"subagent_type":"tester","description":"whatever"}}')
assert_valid_json "case9 valid JSON" "$OUT"
assert_field "case9 stale marker treated as absent" '.hookSpecificOutput.permissionDecision' "allow" "$OUT"
assert_contains "case9 falls through to not-found warning" '.systemMessage' "not found" "$OUT"

# ── Case 11: v2 description contract — aspect suffix keeps the phase name parseable ──
# "Phase 3/4: qa — frontend" must still resolve phase "qa" for the deny message, and the
# aspect must not leak into the suggested agent lookup.
PROJ=$(fresh_project "case11")
cat > "$PROJ/.claude/agents/tester.md" <<'EOF'
---
name: tester
---
Local tester agent.
EOF
write_marker "$PROJ" "$(iso_offset -10M)" '["sdlc:qa-engineer"]' '{"qa":"sdlc:qa-engineer"}'
OUT=$(run_hook "$PROJ" '{"tool_name":"Agent","tool_input":{"subagent_type":"tester","description":"Phase 3/4: qa — frontend"}}')
assert_valid_json "case11 valid JSON" "$OUT"
assert_field "case11 aspect-suffixed description still denied" '.hookSpecificOutput.permissionDecision' "deny" "$OUT"
assert_contains "case11 phase resolved despite aspect suffix" '.hookSpecificOutput.permissionDecisionReason' "using 'sdlc:qa-engineer'" "$OUT"

# ── Case 12: [pass:fix] and [pass:verify] resolve `model:` (only [pass:plan] is special) ──
PROJ=$(fresh_project "case12")
mkdir -p "$PROJ/plugins/laravel-plugin/agents"
cat > "$PROJ/plugins/laravel-plugin/agents/laravel-architect.md" <<'EOF'
---
name: laravel-architect
model: sonnet
model_plan: opus
---
Test agent.
EOF
OUT=$(run_hook "$PROJ" '{"tool_name":"Agent","tool_input":{"subagent_type":"laravel-plugin:laravel-architect","description":"Phase 3/4: security [pass:fix]"}}')
assert_field "case12 fix pass resolves model (not model_plan)" '.hookSpecificOutput.updatedInput.model' "sonnet" "$OUT"
OUT=$(run_hook "$PROJ" '{"tool_name":"Agent","tool_input":{"subagent_type":"laravel-plugin:laravel-architect","description":"Phase 2/4: development — backend [pass:plan]"}}')
assert_field "case12 plan pass with aspect still resolves model_plan" '.hookSpecificOutput.updatedInput.model' "opus" "$OUT"

# ── Case 13: v2 state file — stale started_at but fresh updated_at keeps the marker active ──
PROJ=$(fresh_project "case13")
cat > "$PROJ/.claude/agents/tester.md" <<'EOF'
---
name: tester
---
Local tester agent.
EOF
cat > "$PROJ/.claude/.sdlc-run-active.json" <<EOF
{"task_slug":"test-slug","schema_version":2,"started_at":"$(iso_offset -8H)","updated_at":"$(iso_offset -5M)","roster":["sdlc:qa-engineer"],"phase_agents":{"qa":"sdlc:qa-engineer"}}
EOF
OUT=$(run_hook "$PROJ" '{"tool_name":"Agent","tool_input":{"subagent_type":"tester","description":"Phase 3/4: qa"}}')
assert_field "case13 updated_at keeps a long/resumed run enforced" '.hookSpecificOutput.permissionDecision' "deny" "$OUT"

echo
echo "=== ${pass_count} passed, ${fail_count} failed ==="
[ "$fail_count" -eq 0 ]
