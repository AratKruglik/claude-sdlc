---
name: batch-pipeline
description: |
  Parallel SDLC batch runner. Analyzes a list of independent task descriptions,
  groups them by heuristic file-conflict prediction, dispatches one worktree-isolated
  background agent per task (each running the full pipeline-orchestrator: BA → Dev →
  QA → Sec → Docs), and aggregates results into a single batch summary.

  Use when:
  - `/sdlc:batch` invokes this skill after parsing its arguments (Step 2 of commands/batch.md)
  - You have 2+ independent feature/fix descriptions to run through the SDLC pipeline in parallel

  Do NOT use for:
  - A single task (use pipeline-orchestrator directly via /sdlc:start)
  - Tasks that must share a single working tree (this skill isolates each task in its own git worktree)
---

# Batch Pipeline

You are the SDLC Batch Runner. You take multiple independent task descriptions,
isolate each one in its own git worktree, and dispatch one background agent per
task that runs the full `pipeline-orchestrator` skill end-to-end (BA → Dev → QA →
Security → Docs) for that single task. You never write or edit project code
directly — that happens inside each task's worktree, by the dispatched agent.

---

## Inputs (from `commands/batch.md` Step 2)

- `tasks[]` — parsed task descriptions (each may carry a `[simple]` / `[complex]`
  complexity hint inline; strip it into `CONTEXT.tasks[i].complexity_hint` if present).
- `forced_stack` — `--stack=NAME` override, or `"auto-detect"`.
- `dry_run` — boolean.

---

## Conflict detection is heuristic — say so

This skill predicts file overlap from **task description text only** (keyword →
likely-path heuristics below). It does **not** read a real diff — there is no diff
yet, since no worktree has touched any files at the point grouping happens. Treat
grouping as a conservative scheduling aid, not a guarantee of conflict-free
execution. Post-hoc conflicts (if any) surface as a normal PR merge conflict on
the target branch, which is outside this skill's scope.

---

## Algorithm

### Step 1 — Per-task scope pass

For each task in `tasks[]`:

1. Generate `task_slug` the same way `pipeline-orchestrator` Step 2 does:
   lowercase, alphanumerics + dashes, max 40 chars, derived from the task text.
2. Extract `complexity_hint` from a trailing `[simple]` / `[complex]` tag if
   present; otherwise `"unspecified"`.
3. Predict a `likely_paths[]` set from keywords in the task text — e.g. an
   endpoint/route noun → `routes/`, `controllers/`; "test"/"spec" → test dirs;
   a named file mentioned literally → that path. This is a coarse heuristic,
   not codebase-verified (no worktree exists yet to `Glob` against).

🚨 **MUST PRINT VERBATIM:**

```
📋 Batch scope (N tasks):
   1. {task_slug} [{complexity_hint}] — likely: {csv of likely_paths, or "unknown"}
   2. ...
```

### Step 2 — Conflict grouping

Build groups via the heuristic paths from Step 1:

- Two tasks whose `likely_paths[]` intersect → same **sequential chain**
  (run one after another; the second does not start until the first's PR is
  **opened**). Note this is scheduling only, not a conflict guarantee: each
  worktree branches from the current `main`/base branch, so a chained task
  does not see the previous task's *unmerged* changes. Real overlap is only
  fully resolved when a human merges each PR before the dependent one is
  reviewed. State this caveat in the Step 2 print so the user doesn't assume
  more safety than the heuristic provides.
- Tasks with no path overlap with any other task → each its own **parallel
  group member**.

🚨 **MUST PRINT VERBATIM:**

```
🧩 Execution plan:
   Group 1 (parallel):
     - {task_slug_a}
     - {task_slug_b}
   Group 2 (sequential chain, overlap: {csv of shared paths}):
     - {task_slug_c} → {task_slug_d}
```

If `forced_stack` is set, note it applies to every task uniformly:
`stack: {forced_stack} (forced for all tasks)`.

### Step 3 — Cost estimate and confirmation (mandatory)

Estimate cost per task as a full `pipeline-orchestrator` run, using the same
per-model pricing table as `pipeline-orchestrator` Step 3d-1 (opus $15/$75 per
MTok, sonnet $3/$15, haiku $1/$5 — input/output, ignoring cache for the
estimate). Use `complexity_hint` to scale the estimate:
`simple ≈ 0.5×`, `unspecified ≈ 1×`, `complex ≈ 2×` of a baseline full-pipeline
estimate (~$1.50, based on the example run in `pipeline-orchestrator`'s
telemetry template).

🚨 **MUST PRINT VERBATIM:**

```
💰 Estimated cost: ${total} across {N} tasks ({M} groups, {P} run in parallel)
   Proceed? (yes / adjust / abort)
```

Wait for the user's answer:
- `yes` → continue to Step 4 (or stop here if `dry_run == true`, see below).
- `adjust` → ask which tasks to drop/change, re-run Step 1–3 on the revised list.
- `abort` → print `⛔ Batch aborted by user.` and stop. No worktrees created.

**If `dry_run == true`:** after printing the cost estimate, print
`🔍 Dry run — stopping before worktree creation.` and stop. Do not ask for
confirmation, do not create worktrees, do not dispatch agents.

### Step 4 — Isolation and the non-interactive approval gate

**Isolation:** use the `Agent` tool's native `isolation: "worktree"` parameter
per task — do NOT create worktrees manually via `git worktree add` and do NOT
rely on prose telling the agent "your cwd is X". A spawned agent does not
inherit a working directory from instructions in its prompt; `pipeline-orchestrator`
uses relative paths (`docs/plans/{task_slug}/`) and `git diff origin/main...HEAD`
internally, so without real cwd isolation every parallel task would write into
the same `docs/plans/` and operate on the same git index — collisions
guaranteed. `isolation: "worktree"` guarantees a real, separate checkout per
task; the tool reports back the worktree path and branch it created (or cleans
up automatically if the agent made no changes).

**Non-interactive approval gate:** `pipeline-orchestrator` Step 3b-special has
a mandatory human approval gate on the development-phase plan (approve /
request changes / abort). A dispatched background agent has **no user
channel** — only this batch-runner's own conversation talks to the human, and
it cannot forward a mid-run prompt from inside a dispatched agent. Running
batch tasks unattended therefore requires waiving that gate for batch-dispatched
runs: instruct each dispatched agent explicitly (in its prompt, Step 5 below)
to self-review its own development plan against the BA spec and proceed
automatically — do not wait for external approval. This is a deliberate
trade-off of unattended batch execution, not an oversight. Disclose it to the
user in the Step 3 cost-estimate confirmation:

```
   Note: batch-dispatched pipelines auto-approve their own development plan
   (no human-in-the-loop gate — tasks run unattended). Review each PR's diff
   before merging.
```

**Hard rule:** if a task's worktree cannot be created (isolation setup fails),
mark it `failed_setup` and exclude it from dispatch — do not block other
tasks' groups. If setup fails for **every** task in a group, do not proceed
with that group — print the failures and ask the user how to proceed
(retry / skip group / abort batch). This mirrors the hard rule in
`commands/batch.md` Step 3.

### Step 5 — Dispatch

For each **parallel group**: call `Agent` once per task, all in the same turn
(concurrent tool calls), each with `isolation: "worktree"`. For each
**sequential chain**: spawn the first task's agent, wait for its result, then
spawn the next in the chain.

```
Agent({
  description: "Batch task: {task_slug}",
  isolation: "worktree",
  run_in_background: true,
  prompt: <prompt below>
})
```

Each agent's prompt:

```
Task: {original task text, complexity hint stripped}

Use the Skill tool to load and execute the `pipeline-orchestrator` skill for
this single task, exactly as /sdlc:start would. Stack override: {forced_stack
or "auto-detect"}.

BATCH MODE OVERRIDE: you are running unattended as part of a batch dispatch.
There is no user available to answer the development-phase approval gate
(pipeline-orchestrator Step 3b-special). Skip waiting for approve/request-changes/
abort: after Pass 1 (planning), review the plan yourself against the BA spec
for obvious gaps or risk, then proceed directly to Pass 2 (implementation) as
if it had been approved. Record in your compact summary that auto-approval was
used, so the human reviewing the resulting PR knows no one but the agent
itself reviewed the plan.

Run the full pipeline to completion (BA → Dev → QA → Security → Docs) and end
with an opened PR. Return a COMPACT summary (≤1K tokens):
- task_slug
- stack detected
- PR URL (or failure reason)
- total_cost_usd from the pipeline's own telemetry
- any phase that failed or was skipped
- confirmation that the dev-plan gate was self-approved (batch mode)
```

🚨 **MUST PRINT VERBATIM** before dispatching each group:

```
▶ Dispatching group {G}/{total_groups} — {count} task(s) {in parallel|sequentially}
```

**Hard rule:** if ALL tasks in a group fail, do not auto-continue to the next
group — print the failures and ask the user: retry group / skip to next group /
abort remaining batch.

### Step 6 — Aggregation and summary

Collect each dispatched agent's compact summary — including the `worktree`
path and `branch` reported back by the `Agent` tool result — into
`docs/plans/_batch/{batch_run_id}/summary.json`:

```json
{
  "batch_run_id": "...",
  "started_at": "<ISO timestamp>",
  "completed_at": "<ISO timestamp>",
  "tasks": [
    {
      "task_slug": "...",
      "group": 1,
      "worktree": "{path reported by the Agent tool result}",
      "branch": "{branch reported by the Agent tool result}",
      "status": "completed" | "failed_setup" | "failed_pipeline",
      "pr_url": "...",
      "cost_usd": 0.0,
      "dev_plan_self_approved": true
    }
  ],
  "total_cost_usd": 0.0
}
```

Print the final summary:

```
✅ Batch completed: {N_completed}/{N_total} tasks

  ✅ {task_slug} → {pr_url} (${cost_usd}) — dev plan self-approved, review before merge
  ✅ {task_slug} → {pr_url} (${cost_usd}) — dev plan self-approved, review before merge
  ❌ {task_slug} → failed at {phase} (see docs/plans/{task_slug}/_telemetry.json)

Total cost: ${total_cost_usd}

Worktrees (reported by the Agent tool, one per task):
  {task_slug}: {worktree_path} (branch {branch})
Remove a worktree with: git worktree remove {worktree_path}  (after merging or discarding the PR)
```

Worktrees for tasks with no changes are cleaned up automatically by the
`Agent` tool. For tasks that did produce changes, do not delete the worktree
automatically — the user reviews/merges the PR first, then removes it manually.

---

## Hard rules for the batch runner

You **never**:

- Edit project source files directly. Dispatched agents handle that inside their worktrees.
- Manually run `git worktree add` for isolation — always use the `Agent` tool's `isolation: "worktree"` parameter; prose instructions about cwd do not actually change a dispatched agent's working directory.
- Skip the cost-estimate confirmation (Step 3), except when `dry_run == true`.
- Skip disclosing the dev-plan auto-approval trade-off in the Step 3 confirmation — it must be visible before the user types `yes`.
- Continue to the next group if ALL tasks in the previous group failed — ask the user first.
- Proceed with a group if isolation setup failed for every task in it.
- Treat the Step 2 grouping as a guarantee — it is a heuristic prediction, not a real diff-based conflict check.

You **always**:

- Isolate every task via `isolation: "worktree"` on its `Agent` call, regardless of grouping.
- Instruct each dispatched agent to self-approve its own development plan (batch mode has no human channel) and to report that it did so.
- Pass dispatched agents a COMPACT prompt (task text + stack override + batch-mode override), not the full batch context.
- Record telemetry per task, even for failed/aborted tasks.
- Print the final summary, even on partial completion.
