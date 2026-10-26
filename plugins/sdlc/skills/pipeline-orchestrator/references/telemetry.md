# Pipeline orchestrator — telemetry shape (manual fallback)

`scripts/finalize-telemetry.sh` builds `_telemetry.json` and prints the final summary. Read this
only when `jq` is missing and the file has to be built by hand.

## 3d-1. Per-dispatch `phases[]` entry

Fill one `phases[]` entry per dispatch:

- `usage_source` — `"measured"` when the record's `status` is `completed`. When the record is missing, `unmeasured` (transcript not found), or `jq` is unavailable, fall back to the estimate `chars / 4` over prompt + summary and set `usage_source: "estimated"`. Never silently mix the two: the field says which one this row is.
- Token fields, measured case — `input_tokens = input_tokens + cache_creation_input_tokens + cache_read_input_tokens` (the total input the API saw), `cached_input_tokens = cache_read_input_tokens`, plus the two raw fields `cache_creation_input_tokens` and `cache_read_input_tokens` verbatim. This mapping keeps `cache_hit_ratio` (Step 5) meaning "share of input served from cache", as before.
- `model` — the model **tier** declared in the agent's frontmatter (`opus` / `sonnet` / `haiku` / `fable`), authoritative because the PreToolUse hook enforces it. `model_id` — the concrete id from the record (e.g. `claude-opus-5`), measured case only. A mismatch between the two is worth a one-line stderr warning: it means an override (`CLAUDE_CODE_SUBAGENT_MODEL_FORCE`, an org allowlist) is in play.
- `cost_usd` — from the record. When it is `null` (`pricing_note: "unknown model"`), price the measured tokens yourself from the frontmatter tier's row in `references/pricing.json` and copy `pricing_note` into the entry. Estimated rows are priced the same way from the tier. `pricing.json` is the single source of truth for prices — README and this skill reference it, never restate it.
- `agent_id`, `started_at`, `completed_at`, `turns`, `pass` — copied from the record (`null` when estimated).
- `compact_summary_chars` — `last_message_chars` from the record when measured, else `len(CONTEXT.{phase}_output)`. Convert to tokens (`chars / 4`) before comparing: the handoff budget is stated in **tokens** by every agent contract (≤2K for BA/QA/security, ≤3K for development). If `chars / 4 > 3000` (i.e. > 12000 chars), record `compact_handoff_violation: true` and emit a one-line stderr warning: `WARN: {phase} compact summary exceeded budget (~{chars/4} tokens > 3000)`. Do not abort. This counter is the pipeline's only sensor for model verbosity drift; a threshold ~4× too tight fires on every compliant run and destroys that signal.
- For aspect-aware fan-out, push one entry **per dispatch** into `phases[]` with `phase` and `aspect` set; aspect-agnostic phases omit `aspect`. Development pushes one entry per pass (`pass: "plan"` / `"implement"`).
- Every entry carries `group_index` — the index of the group it belongs to in
  `resolved_phases`. Members of a parallel group share a `group_index` and a
  `Phase {N}`, and that is how a reader tells "ran concurrently" from "ran one after
  the other" once the run is over.
- The security fix pass and the QA verify rerun (3d-security) push their own entries,
  with `pass: "fix"` / `pass: "verify"` and the `group_index` of the security group,
  plus the trailer counters `security_fix_pass` and `qa_verify_rerun`.

Nested dispatches (a phase agent spawning `general-purpose` / `Explore` via a skill) are recorded by the hooks too, with `nested: true`; they are **not** `phases[]` entries. Their cost is summed by `usage-report.sh` into `nested_cost_usd` and surfaces in Step 5.

## Step 5 — `_telemetry.json`

The file it writes, `docs/plans/{task_slug}/_telemetry.json`:

```json
{
  "task_slug": "...",
  "stack": "laravel",
  "primary_profile": "laravel",
  "active_profiles": {
    "backend": "laravel",
    "frontend": "inertia-vue",
    "database": "laravel"
  },
  "profile_source": "laravel-plugin/stack.md",
  "narrative_language": "uk",
  "headless_mode": false,
  "git_flow": {
    "model": "git-flow",
    "confidence": "high",
    "source": "cache",
    "sources": ["topology:develop-branch", "config:gitflow.*"],
    "task_type": "hotfix",
    "task_type_confidence": "high",
    "branch_name": "hotfix/null-pointer-in-payment-handler",
    "branch_action": "created",
    "branch_creation_method": "git-flow-cli",
    "base_branch": "main",
    "pr_base_branch": "main",
    "requires_back_merge": "develop",
    "topology_conflict": null,
    "diff_scope": "prospective"
  },
  "active_workflow": "hotfix",
  "workflow_selection_reason": "task_type=hotfix",
  "started_at": "<ISO timestamp>",
  "completed_at": "<ISO timestamp>",
  "wall_clock_seconds": 187,
  "model_enforcement_corrections": 0,
  "phases": [
    {
      "phase": "business_analysis",
      "aspect": null,
      "pass": null,
      "agent": "business-analyst",
      "agent_id": "agent_3f9c…",
      "model": "opus",
      "model_id": "claude-opus-5",
      "status": "completed",
      "usage_source": "measured",
      "started_at": "<ISO timestamp>",
      "completed_at": "<ISO timestamp>",
      "turns": 14,
      "input_tokens": 35000,
      "output_tokens": 3000,
      "cached_input_tokens": 21000,
      "cache_creation_input_tokens": 4000,
      "cache_read_input_tokens": 21000,
      "cost_usd": 0.16,
      "pricing_note": null,
      "compact_summary_chars": 1840,
      "compact_handoff_violation": false
    },
    {
      "phase": "qa",
      "aspect": null,
      "pass": null,
      "agent": "qa-engineer",
      "agent_id": null,
      "model": "sonnet",
      "model_id": null,
      "status": "completed",
      "usage_source": "estimated",
      "started_at": null,
      "completed_at": null,
      "turns": null,
      "qa_iterations_used": 2,
      "qa_status": "completed",
      "input_tokens": 28000,
      "output_tokens": 2100,
      "cached_input_tokens": 0,
      "cache_creation_input_tokens": null,
      "cache_read_input_tokens": null,
      "cost_usd": 0.07,
      "pricing_note": null,
      "compact_summary_chars": 1450,
      "compact_handoff_violation": false
    }
  ],
  "usage_source_summary": { "measured": 5, "estimated": 1, "unmeasured": 0 },
  "nested_cost_usd": 0.04,
  "total_cost_usd_including_nested": 1.46,
  "skip_rules_applied": [
    { "rule": "typo-fix", "phase_skipped": "business_analysis", "reason": "$ARGUMENTS matched /^typo/ AND diff < 30 LOC" }
  ],
  "post_pipeline_checks": [
    { "command": "...", "exit_code": 0 }
  ],
  "total_input_tokens": 152000,
  "total_output_tokens": 9800,
  "total_cached_input_tokens": 88000,
  "total_cost_usd": 1.42,
  "cost_scope": "subagent_phases_only",
  "max_total_cost_usd": null,
  "cost_cap_overridden": false,
  "cache_hit_ratio": 0.58,
  "deps_preflight": {
    "superpowers": { "status": "available", "missing_skills": [] }
  }
}
```

Compute aggregates from `phases[]`:

- `total_input_tokens` = sum of phase `input_tokens`.
- `total_output_tokens` = sum of phase `output_tokens`.
- `total_cached_input_tokens` = sum of phase `cached_input_tokens`.
- `total_cost_usd` = sum of phase `cost_usd`.
- `cache_hit_ratio` = `total_cached_input_tokens / max(total_input_tokens, 1)` rounded to 2 decimals.
- `cost_scope` = always the literal `"subagent_phases_only"`.
- `usage_source_summary` = counts of `phases[].usage_source` values (`measured` / `estimated` / `unmeasured`). A run with any `estimated` row is not baseline-grade; `docs/cost-baseline.md` aggregates only fully measured runs.
- `nested_cost_usd` and `total_cost_usd_including_nested` — copied from the final `usage-report.sh` output (run it once more here, after the last phase). `nested_cost_usd` is the measured cost of subagents that phase agents spawned themselves (superpowers skills, `Explore`); it is real pipeline spend that no earlier version could see. `total_cost_usd` keeps its historical meaning (phase dispatches only) so `cost_scope` stays truthful.

> Token counts are **measured** by the `SubagentStop` hook from each subagent's own transcript (3d-1); the Agent tool result never carried them. A row is `estimated` (char-length / 4) only when the hooks could not measure it — jq missing, transcript not found, or the run marker not fresh.

> **What `total_cost_usd` does not include.** Only subagent spawns are metered. The orchestrator's own consumption — this skill's body, stack-profile globbing and parsing, workflow resolution and schema validation, and the approval-gate exchanges — runs on the session model and is invisible here. Treat `total_cost_usd` as a floor for the run, not the full bill. The `cost_scope` field exists so downstream consumers (`docs/cost-baseline.md`, `/sdlc:doctor`) cannot silently misread it as a total.

Print the final summary to the user (`finalize-telemetry.sh` renders exactly this block):

```
✅ SDLC pipeline completed for "{task_slug}"

Stack:           {stack} (priority {priority})
Branch:          {branch_name} ({branch_action}, from {base_branch}) → PR base {pr_base_branch}
Task type:       {task_type} · workflow {active_workflow}
Phases run:      {N} ({skip_rules_applied summary})
Wall clock:      {wall_clock_seconds}s
Cost:            ${total_cost_usd}

Phase results:
  ✅ business_analysis     ({agent}, {tokens}, ${cost})
  ✅ development           ({agent}, {tokens}, ${cost})
  ✅ qa                    ({agent}, {tokens}, ${cost})
  ✅ security              ({agent}, {tokens}, ${cost})
  ✅ documentation         ({agent}, {tokens}, ${cost})

Artifacts:
  docs/plans/{task_slug}/01-business-analysis.md
  docs/plans/{task_slug}/02-development.md
  ...
  docs/plans/{task_slug}/_telemetry.json

Post-pipeline checks:
  ✅ vendor/bin/pint --test
  ✅ php artisan test (47 passed)
  ✅ php artisan route:list

PR: {pr_url_if_created}
```


`_telemetry.json` is assembled from three sources: the final `usage-report.sh` output
(per-dispatch tokens and cost), the state file (`phase_status`, `git_flow`, workflow, skips,
`resume_count`) and CONTEXT. Add `"resumed": true|false` and `"resume_count": N` at the top
level; a resumed run's `wall_clock_seconds` counts from the original `started_at`.

