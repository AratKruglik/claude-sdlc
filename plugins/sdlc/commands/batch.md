---
description: Run SDLC pipelines in parallel for multiple tasks — decomposes scope, detects file conflicts, dispatches worktree-isolated pipelines.
argument-hint: '"Task 1" "Task 2" ... [--file=path] [--stack=NAME] [--dry-run]'
disable-model-invocation: true
---

# /sdlc:batch

Parallel SDLC pipeline runner. Analyzes scope, decomposes into independent tasks, dispatches worktree-isolated pipelines in parallel (or sequentially for dependent tasks).

## Mandatory execution protocol

### Step 1 — Validate and parse input

If `$ARGUMENTS` is empty: print usage and stop:

```
Usage: /sdlc:batch "Task description 1" "Task description 2" ...
       /sdlc:batch --file=sprint-tasks.md
       /sdlc:batch --dry-run "Task 1" "Task 2"
```

Parse flags from `$ARGUMENTS`:
- `--file=PATH`: read task list from that file. Strip the flag.
- `--stack=NAME`: remember as `forced_stack`. Strip the flag.
- `--dry-run`: set `dry_run = true`. Strip the flag.

If `--file=PATH` provided: read the file. Extract tasks — one per non-blank line; strip leading `- ` if present; skip markdown headers.

Otherwise: tasks are quoted strings in `$ARGUMENTS`. If no quoted strings, treat the entire remaining argument as a single task.

Print verbatim:
```
▶ /sdlc:batch
   Tasks:        <N tasks parsed>
   Forced stack: <forced_stack or "auto-detect">
   Dry run:      <yes|no>
```

### Step 2 — Invoke the batch-pipeline skill

Use the Skill tool to load and execute the `batch-pipeline` skill. Pass:
- Parsed task list
- `forced_stack` flag
- `dry_run` flag

**Do not improvise or inline the batch logic — delegate to the skill.**

### Step 3 — Hard rules during batch

- Do NOT edit project source files directly. Worker agents handle that inside their worktrees.
- Do NOT skip the cost-estimate confirmation (Step 3 in the skill). Always wait for user `yes` / `adjust` / `abort`.
- Do NOT continue to the next group if ALL tasks in the previous group failed — ask the user first.
- Do NOT proceed if worktree creation fails for all tasks in a group.

### Step 4 — On unrecoverable failure before dispatch

If batch setup fails before any worktrees are created:
- Print: `⛔ Batch halted: <reason>`
- Stop. No partial telemetry needed.

---

## Examples

```
/sdlc:batch "Add /healthz endpoint" "Fix typo in README" "Rename /api to /v1"
/sdlc:batch --file=sprint-tasks.md
/sdlc:batch "Add billing [complex]" "Fix login redirect [simple]"
/sdlc:batch "Implement subscription billing" --dry-run
/sdlc:batch --stack=nodejs "Add auth middleware" "Add rate limiting"
```
