# Pipeline orchestrator — Step R: resuming a run

Read this when Step R in `SKILL.md` resolves to *resume*.

**R-1. Branch guard.** `git rev-parse --abbrev-ref HEAD` must equal `state.git_flow.branch_name`.
Otherwise HALT — resuming on the wrong branch is the one way `--resume` can damage work:

```
❌ Cannot resume "{task_slug}": the run lives on branch {branch_name}, current branch is {current}.
   git checkout {branch_name}   — then /sdlc:start --resume
   or /sdlc:start "<description>" to start a fresh run.
```

**R-2. Load CONTEXT from the state file** — every key Step 2 persisted (`task_slug`, `arguments`,
`flags`, `stack`, `git_flow.*` → `CONTEXT.base_branch` / `branch_name` / `pr_base_branch` /
`task_type` / `requires_back_merge` / `diff_scope`, `narrative_language`, `headless_mode`,
`active_workflow`, `workflow_selection_reason`, `max_total_cost_usd`, `resolved_phases`,
`skip_rules_applied`, `phase_status`, `cost_cap_overridden`). **Skip Steps 0a, 0b, 0b-git, 0c,
1c and 2 entirely** — their decisions are what the file holds. Re-run only Step 1a/1b (parse the
profiles named in `state.stack.active_profiles` + `sdlc.local.yaml`) to rebuild
`EFFECTIVE_PROFILE`; it is deterministic from disk and too large to persist.

For every phase step whose status is `completed`, set `CONTEXT.{phase}_output` to the literal
`(resumed — read docs/plans/{task_slug}/0X-{phase}.md)`. Agents already read prior outputs from
the file system, never from the orchestrator's context (compact-handoff contract), so nothing
downstream needs the lost summaries.

**R-3. Refresh the state file:** `updated_at = now`, `resume_count += 1`, `resumed_at = now`.
This is also what re-arms the hooks — `enforce-agent-model.sh` and the telemetry hooks judge
freshness by `updated_at`.

**R-4. MUST PRINT VERBATIM:**

```
↩️  Resuming "{task_slug}" — {N completed}/{M} phase steps done, resume #{resume_count}
   workflow: {active_workflow} · branch: {branch_name} → PR base {pr_base_branch}
   {phase[/aspect]}: {status}
   ...one line per entry in phase_status...
```

**R-5. Enter Step 3** at the first group in `resolved_phases` that has a member whose status is
not `completed` / `skipped` / `skipped-cost-cap`, and dispatch **only those members**. Per status:

| `phase_status` value | What Step 3 does with it |
|---|---|
| `pending` | run normally |
| `planned` (development aspect) | `Glob` the plan file `02-development-plan{-aspect}.md`; if present → go straight to the approval gate (3b-special); if absent (crashed between agent start and file write) → re-run the plan pass |
| `approved` (development aspect) | run the implementation pass only |
| `failed` | ask the user: retry / skip / abort, exactly as a fresh failure would |
| `completed`, `skipped`, `skipped-cost-cap` | do not dispatch |

Phase numbering (`Phase N/total`) is unchanged — it comes from `resolved_phases`, not from what
is left to run. Steps 4 and 5 run as usual at the end; Step 5 records `resumed: true`.

