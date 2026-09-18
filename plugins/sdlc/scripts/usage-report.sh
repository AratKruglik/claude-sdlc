#!/usr/bin/env bash
# Pair the dispatch events in docs/plans/{task_slug}/_usage.jsonl into per-dispatch usage
# records. Read-only; prints one JSON object on stdout.
#
# The hooks (dispatch-log.sh, subagent-usage.sh) write three row kinds:
#   pending — PreToolUse(Agent): what the orchestrator asked for (agent_type, description →
#             phase/aspect/pass)
#   start   — SubagentStart: agent_id assigned to a dispatch of agent_type
#   stop    — SubagentStop: measured usage for agent_id
#
# Pairing:
#   * each `start` takes the EARLIEST unmatched `pending` with the same bare agent_type (FIFO);
#   * `stop` joins by agent_id;
#   * a `pending` with no `start` is `not_started` (denied or errored before start);
#   * a `start` whose pending has phase null (description outside the `Phase N/M:` contract)
#     is `nested` — a dispatch made by a phase agent, not by the orchestrator. It is
#     attributed to the unique phase dispatch whose [start, stop] interval contains its start;
#     when several are in flight (parallel group) it stays unattributed and only counts
#     towards nested_cost_usd.
#
# Known caveat: two concurrent dispatches of the same bare agent_type (QA fan-out) may swap
# aspect labels if SubagentStart order differs from PreToolUse order. Totals are unaffected.
#
# Exit codes: 0 always for a readable-or-absent log (partial data is reported, not raised);
#             2 usage error; 3 jq missing (telemetry cannot be read without it).
#
# Usage: usage-report.sh TASK_SLUG [--project-root DIR] [--log PATH]
set -uo pipefail

usage() {
    echo "usage: usage-report.sh TASK_SLUG [--project-root DIR] [--log PATH]"
}

slug=""; root="."; log=""
while [ $# -gt 0 ]; do
    case "$1" in
        --project-root) root="${2:-}"; shift 2 ;;
        --log)          log="${2:-}"; shift 2 ;;
        -h|--help)      usage; exit 0 ;;
        -*)             usage >&2; exit 2 ;;
        *)              slug="$1"; shift ;;
    esac
done
[ -n "$slug" ] || { usage >&2; exit 2; }
[ -n "$log" ] || log="${root}/docs/plans/${slug}/_usage.jsonl"

if ! command -v jq >/dev/null 2>&1; then
    printf '{"error":"jq is required to read dispatch telemetry","task_slug":"%s"}\n' "$slug"
    exit 3
fi

generated_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
present=false
rows='[]'
if [ -f "$log" ]; then
    present=true
    # fromjson? drops malformed lines instead of aborting the whole read.
    rows=$(jq -c -R 'fromjson? // empty' "$log" 2>/dev/null | jq -sc 'map(select(type == "object" and has("event")))' 2>/dev/null || echo '[]')
fi

JQ_PROGRAM=$(cat <<'JQ'
def tsnum:
  if . == null then null
  else . as $s
    | ($s | sub("\\.[0-9]+"; "") | sub("\\+00:00$"; "Z") | try fromdateiso8601 catch null) as $sec
    | if $sec == null then null
      else $sec + ((($s | capture("\\.(?<f>[0-9]+)") | ("0." + .f) | tonumber) // 0))
      end
  end;

def usage_fields:
  {model, input_tokens, output_tokens, cache_creation_input_tokens, cache_read_input_tokens,
   turns, cost_usd, pricing_note, last_message_chars, usage_source};

def blank_usage:
  {model: null, input_tokens: null, output_tokens: null, cache_creation_input_tokens: null,
   cache_read_input_tokens: null, turns: null, cost_usd: null, pricing_note: null,
   last_message_chars: null, usage_source: null};

def stop_status: if .usage_source == "measured" then "completed" else "unmeasured" end;

def cost_of: if (.cost_usd | type) == "number" then .cost_usd else 0 end;

def r6: (. * 1000000 | round) / 1000000;

def tok($d; $k; $nested):
  [ $d[] | select(.nested == $nested and .[$k] != null) | .[$k] ] | add // 0;

# ── order rows by timestamp, then by append order ─────────────────────────
to_entries
| map(.value + {_idx: .key, _ts: ((.value.ts | tsnum) // 0)})
| sort_by(._ts, ._idx)

# ── pair pending → start → stop ───────────────────────────────────────────
| reduce .[] as $r (
    {p: {}, d: [], idx: {}};
    if $r.event == "pending" then
      .p[$r.agent_type // ""] += [$r]
    elif $r.event == "start" then
      ($r.agent_type // "") as $at
      | (.p[$at] // []) as $q
      | ($q[0] // null) as $pend
      | .p[$at] = $q[1:]
      | .d += [ ({agent_type: $at, agent_id: $r.agent_id, description: $pend.description,
                  phase: $pend.phase, aspect: $pend.aspect, pass: $pend.pass,
                  pending_at: $pend.ts, started_at: $r.ts, completed_at: null,
                  status: "running", nested: (($pend == null) or ($pend.phase == null)),
                  attributed_to: null}
                 + blank_usage + {_start: $r._ts, _stop: null}) ]
      | if $r.agent_id != null then .idx[$r.agent_id] = ((.d | length) - 1) else . end
    elif $r.event == "stop" then
      if ($r.agent_id != null) and (.idx[$r.agent_id] != null) then
        (.idx[$r.agent_id]) as $i
        | .d[$i] |= (. + ($r | usage_fields)
                     + {completed_at: $r.ts, _stop: $r._ts, status: ($r | stop_status)})
      else
        .d += [ ({agent_type: ($r.agent_type // ""), agent_id: $r.agent_id, description: null,
                  phase: null, aspect: null, pass: null, pending_at: null, started_at: null,
                  completed_at: $r.ts, status: ($r | stop_status), nested: true,
                  attributed_to: null}
                 + ($r | usage_fields) + {_start: null, _stop: $r._ts}) ]
      end
    else . end)

# ── pendings that never started ───────────────────────────────────────────
| .d += [ .p | to_entries[] | .value[]
          | ({agent_type: .agent_type, agent_id: null, description: .description,
              phase: .phase, aspect: .aspect, pass: .pass, pending_at: .ts,
              started_at: null, completed_at: null, status: "not_started",
              nested: (.phase == null), attributed_to: null}
             + blank_usage + {_start: null, _stop: null}) ]
| .d as $all

# ── attribute nested dispatches to the unique in-flight phase dispatch ────
| ($all | map(select((.nested | not) and ._start != null))) as $phases
| ($all | map(
    if .nested and ._start != null then
      . as $n
      | ($phases | map(select(._start <= $n._start and (._stop == null or $n._start <= ._stop)))) as $c
      | if ($c | length) == 1
        then . + {attributed_to: $c[0].agent_id, phase: $c[0].phase, aspect: $c[0].aspect, pass: $c[0].pass}
        else . end
    else . end)) as $disp

# ── totals ────────────────────────────────────────────────────────────────
| ([ $disp[] | select(.nested | not) | cost_of ] | add // 0 | r6) as $phase_cost
| ([ $disp[] | select(.nested) | cost_of ] | add // 0 | r6) as $nested_cost
| {
    schema_version: 1,
    task_slug: $slug,
    generated_at: $generated_at,
    log_path: $log,
    log_present: $present,
    dispatches: ($disp | map(with_entries(select(.key | startswith("_") | not)))),
    totals: {
      input_tokens: tok($disp; "input_tokens"; false),
      output_tokens: tok($disp; "output_tokens"; false),
      cache_creation_input_tokens: tok($disp; "cache_creation_input_tokens"; false),
      cache_read_input_tokens: tok($disp; "cache_read_input_tokens"; false)
    },
    usage_source_summary: {
      measured:    ([ $disp[] | select(.status == "completed") ] | length),
      unmeasured:  ([ $disp[] | select(.status == "unmeasured") ] | length),
      not_started: ([ $disp[] | select(.status == "not_started") ] | length),
      running:     ([ $disp[] | select(.status == "running") ] | length)
    },
    total_cost_usd: $phase_cost,
    nested_cost_usd: $nested_cost,
    total_cost_usd_including_nested: (($phase_cost + $nested_cost) | r6),
    cost_scope: "subagent_phases_only"
  }
JQ
)

printf '%s' "$rows" | jq --arg slug "$slug" --arg log "$log" --argjson present "$present" \
    --arg generated_at "$generated_at" "$JQ_PROGRAM"
exit 0
