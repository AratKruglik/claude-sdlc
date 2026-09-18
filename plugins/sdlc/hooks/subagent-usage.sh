#!/usr/bin/env bash
# SubagentStop hook: measure a finished subagent's token usage from its own transcript
# and append a "stop" row to the run's usage log.
#
# Why a hook and not the orchestrator: the Agent tool result carries no usage data, so
# every pre-2.0 telemetry number was a chars/4 estimate. The subagent's transcript
# (~/.claude/projects/{slug}/{session_id}/subagents/agent-{agent_id}.jsonl) does carry
# per-response `message.usage`, and SubagentStop is the one event that knows agent_id.
#
# Contract: same as dispatch-log.sh — silent, marker-gated, fail-open. Registered
# synchronously so the row is on disk before the orchestrator reads usage-report.py.
#
# Row: {"event":"stop","ts","agent_id","agent_type","model","input_tokens","output_tokens",
#       "cache_creation_input_tokens","cache_read_input_tokens","turns","cost_usd",
#       "pricing_note","last_message_chars","usage_source":"measured"|"transcript_missing"}
# Usage is counted once per message.id (a response spans several JSONL lines that all
# repeat the same usage; the last line wins). Unknown model ids get cost_usd null, never
# a guessed tier.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_telemetry-lib.sh
. "${HOOK_DIR}/_telemetry-lib.sh"

PRICING="${SDLC_PRICING_FILE:-${HOOK_DIR}/../references/pricing.json}"

payload=$(cat 2>/dev/null) || exit 0
[ -n "$payload" ] || exit 0
tool=$(json_tool) || exit 0
[ "$(json_get "$payload" "hook_event_name")" = "SubagentStop" ] || exit 0

root=$(resolve_project_root "$payload")
slug=$(active_task_slug "$root") || exit 0
log=$(usage_log_path "$root" "$slug") || exit 0

agent_id=$(json_get "$payload" "agent_id")
[ -n "$agent_id" ] || exit 0
agent_type=$(bare_agent "$(json_get "$payload" "agent_type")")
session_id=$(json_get "$payload" "session_id")
transcript_path=$(json_get "$payload" "transcript_path")
last_message=$(json_get "$payload" "last_assistant_message")
last_chars=${#last_message}
ts=$(now_iso)

# ── locate the subagent's own transcript ────────────────────────────────────
subagent_file=""
if [ -n "$transcript_path" ] && [ -n "$session_id" ]; then
    candidate="$(dirname "$transcript_path")/${session_id}/subagents/agent-${agent_id}.jsonl"
    [ -f "$candidate" ] && subagent_file="$candidate"
fi
if [ -z "$subagent_file" ] && [ -n "$session_id" ] && [ -d "${HOME}/.claude/projects" ]; then
    subagent_file=$(find "${HOME}/.claude/projects" -path "*/${session_id}/*" -name "agent-${agent_id}.jsonl" 2>/dev/null | head -1)
fi

if [ -z "$subagent_file" ]; then
    if [ "$tool" = jq ]; then
        row=$(jq -cn --arg ts "$ts" --arg id "$agent_id" --arg at "$agent_type" --argjson lc "$last_chars" \
            '{event:"stop", ts:$ts, agent_id:$id, agent_type:$at, model:null,
              input_tokens:null, output_tokens:null, cache_creation_input_tokens:null,
              cache_read_input_tokens:null, turns:null, cost_usd:null, pricing_note:null,
              last_message_chars:$lc, usage_source:"transcript_missing"}')
    else
        row=$(python3 -c '
import json, sys
print(json.dumps({"event":"stop","ts":sys.argv[1],"agent_id":sys.argv[2],"agent_type":sys.argv[3],
  "model":None,"input_tokens":None,"output_tokens":None,"cache_creation_input_tokens":None,
  "cache_read_input_tokens":None,"turns":None,"cost_usd":None,"pricing_note":None,
  "last_message_chars":int(sys.argv[4]),"usage_source":"transcript_missing"}, separators=(",",":")))
' "$ts" "$agent_id" "$agent_type" "$last_chars")
    fi
    append_row "$log" "$row"
    exit 0
fi

# ── sum usage, dedupe by message.id, price it ───────────────────────────────
if [ "$tool" = jq ]; then
    pricing_json=$(cat "$PRICING" 2>/dev/null || echo '{}')
    row=$(jq -c -R 'fromjson? // empty' "$subagent_file" 2>/dev/null \
        | jq -sc --arg ts "$ts" --arg id "$agent_id" --arg at "$agent_type" \
                 --argjson lc "$last_chars" --argjson pricing "$pricing_json" '
        [ .[] | select(.type == "assistant" and (.message.usage? // null) != null) ]
        | to_entries
        | map({key: (.value.message.id // ("__line_" + (.key|tostring))), value: .value})
        | reduce .[] as $e ({}; .[$e.key] = $e.value)
        | [ .[] ] as $msgs
        | {
            input:  ([$msgs[] | .message.usage.input_tokens // 0] | add // 0),
            output: ([$msgs[] | .message.usage.output_tokens // 0] | add // 0),
            cw:     ([$msgs[] | .message.usage.cache_creation_input_tokens // 0] | add // 0),
            cr:     ([$msgs[] | .message.usage.cache_read_input_tokens // 0] | add // 0),
            turns:  ($msgs | length),
            model:  ([$msgs[] | .message.model // empty | select(. != "unknown")] | last // "unknown")
          } as $u
        | ($u.model | ascii_downcase) as $m
        | ([ ($pricing.match // [])[] | . as $rule | select($m | test($rule.pattern; "i")) | .tier ] | first // null) as $tier
        | (if $tier != null then $pricing.tiers[$tier] else null end) as $p
        | {
            event: "stop", ts: $ts, agent_id: $id, agent_type: $at, model: $u.model,
            input_tokens: $u.input, output_tokens: $u.output,
            cache_creation_input_tokens: $u.cw, cache_read_input_tokens: $u.cr,
            turns: $u.turns,
            cost_usd: (if $p == null then null else
                (($u.input * $p.input + $u.cw * $p.input * $p.cache_write_multiplier
                  + $u.cr * $p.input * $p.cache_read_multiplier + $u.output * $p.output) / 1000000
                 * 1000000 | round / 1000000) end),
            pricing_note: (if $p == null then "unknown model" else null end),
            last_message_chars: $lc, usage_source: "measured"
          }' 2>/dev/null)
else
    row=$(python3 - "$subagent_file" "$PRICING" "$ts" "$agent_id" "$agent_type" "$last_chars" <<'PY' 2>/dev/null
import json, re, sys
path, pricing_path, ts, agent_id, agent_type, last_chars = sys.argv[1:7]
msgs, line_no = {}, 0
with open(path, encoding="utf-8", errors="replace") as fh:
    for line in fh:
        line_no += 1
        try:
            e = json.loads(line)
        except Exception:
            continue
        if e.get("type") != "assistant":
            continue
        m = e.get("message") or {}
        if not m.get("usage"):
            continue
        msgs[m.get("id") or f"__line_{line_no}"] = m
def n(v):
    try: return int(v or 0)
    except Exception: return 0
u = {"input": 0, "output": 0, "cw": 0, "cr": 0}
model = "unknown"
for m in msgs.values():
    us = m["usage"]
    u["input"] += n(us.get("input_tokens")); u["output"] += n(us.get("output_tokens"))
    u["cw"] += n(us.get("cache_creation_input_tokens")); u["cr"] += n(us.get("cache_read_input_tokens"))
    if m.get("model") and m["model"] != "unknown":
        model = m["model"]
try:
    pricing = json.load(open(pricing_path))
except Exception:
    pricing = {}
tier = None
for rule in pricing.get("match", []):
    if re.search(rule["pattern"], model.lower(), re.I):
        tier = rule["tier"]; break
p = pricing.get("tiers", {}).get(tier) if tier else None
cost = None
if p:
    cost = round((u["input"] * p["input"] + u["cw"] * p["input"] * p["cache_write_multiplier"]
                  + u["cr"] * p["input"] * p["cache_read_multiplier"] + u["output"] * p["output"]) / 1e6, 6)
print(json.dumps({"event": "stop", "ts": ts, "agent_id": agent_id, "agent_type": agent_type,
    "model": model, "input_tokens": u["input"], "output_tokens": u["output"],
    "cache_creation_input_tokens": u["cw"], "cache_read_input_tokens": u["cr"],
    "turns": len(msgs), "cost_usd": cost, "pricing_note": None if p else "unknown model",
    "last_message_chars": int(last_chars), "usage_source": "measured"}, separators=(",", ":")))
PY
)
fi

[ -n "${row:-}" ] && append_row "$log" "$row"
exit 0
