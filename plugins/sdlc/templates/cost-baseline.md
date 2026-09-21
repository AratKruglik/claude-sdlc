# Cost Baseline

Measured cost of SDLC pipeline runs. Read by `/sdlc:doctor` (step 4) and used to detect
cost regressions after a model, prompt, or routing change.

**Status: not yet baselined.** Every cost figure elsewhere in this repo — `README.md`
("Cost Optimization"), `ARCHITECTURE.md` §6.1 — is an *estimate* derived from the list prices
in `plugins/sdlc/references/pricing.json` and assumed token volumes. Nothing below is measured
yet. Treat the estimates accordingly until this file carries real numbers.

## How to populate

Each `/sdlc:start` run writes two files under `docs/plans/{task_slug}/`:

- `_usage.jsonl` — raw dispatch events appended by the plugin's hooks (`pending` / `start` /
  `stop`), with token counts **measured** from each subagent's transcript.
- `_telemetry.json` — the orchestrator's per-phase view, built from the same events via
  `scripts/usage-report.sh`. `usage_source_summary` tells you whether every row was measured.

Aggregate only runs whose `usage_source_summary.estimated == 0`, across runs of comparable size,
and update the `summary` block below. One way to list candidate runs:

```bash
for f in docs/plans/*/_usage.jsonl; do
  slug=$(basename "$(dirname "$f")")
  bash "${CLAUDE_PLUGIN_ROOT:-plugins/sdlc}/scripts/usage-report.sh" "$slug" --project-root . \
    | jq -r '[.task_slug,
              (if .usage_source_summary.unmeasured == 0 and .usage_source_summary.not_started == 0
               then "measured" else "partial" end),
              .total_cost_usd, "nested", .nested_cost_usd] | @tsv'
done
```

`nested_cost_usd` (subagents spawned by phase agents themselves) is reported separately and is
**not** part of `total_cost_usd`; add it when comparing against an invoice.

Classify runs by size before averaging — a typo-fix and a billing module do not belong in the
same mean:

| Class | Rough shape |
|---|---|
| `small` | < 50 LOC touched, skip-rules usually trim phases |
| `medium` | one feature, a few files per aspect, full 5-phase pipeline |
| `large` | multi-aspect fan-out, migrations, > 500 LOC touched |

## What is and isn't counted

`total_cost_usd` in telemetry carries `cost_scope: "subagent_phases_only"`. It sums the
per-phase subagent spawns and **excludes the orchestrator's own consumption** — the
pipeline-orchestrator skill body, stack-profile globbing and parsing, workflow resolution and
schema validation, and the development-phase approval-gate exchanges, all of which run on the
session model.

So the numbers here are a floor, not a bill. When comparing against an Anthropic Console
invoice, expect the invoice to be higher; that gap is the orchestrator, not a metering bug.

## Summary

Replace the block below once at least 20 runs have been aggregated. `/sdlc:doctor` parses this
exact fenced block, tagged `json summary`.

```json summary
{
  "runs_aggregated": 0,
  "avg_cost_per_medium_run_usd": null,
  "p90_cost_per_medium_run_usd": null,
  "cache_hit_ratio": null,
  "cost_scope": "subagent_phases_only",
  "last_updated": null
}
```

## Run log

One row per aggregated batch. Keep the newest at the top.

| Date | Runs | Class | Stack | Avg $ | p90 $ | Cache hit | Notes |
|---|---|---|---|---|---|---|---|
| — | 0 | — | — | — | — | — | No runs aggregated yet |
