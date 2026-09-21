---
description: Run the full SDLC pipeline (BA → Dev → QA → Security → Docs) for a feature, with auto-detection of the framework stack and git branching model.
argument-hint: "<feature description> [--stack=NAME] [--type=NAME] [--workflow=NAME] [--redetect-git-flow] [--redetect-stack] [--force-preflight] | --resume"
---

# /sdlc:start

Single entry point for the SDLC pipeline.

## Execution model

This pipeline runs **synchronously in the current Claude Code session** — it is not a detached or autonomous background process. You stay engaged through:

- Steps 0-2 (dependency preflight, stack detection, git-flow detection, skip-rule analysis): a series of read-only `Glob`/`Read`/`git` calls, each of which may prompt for tool-use permission depending on your settings.
- The **branch gate** (Step 0b-git): the pipeline reports the detected branching model, the classified task type and a proposed branch name, then asks you to create / continue / rename / change type / abort before anything is written.
- Phase boundaries: each phase prints an announcement banner and the orchestrator waits for its result before continuing.
- The **development phase's plan/approval gate**: the architect writes an implementation plan, then the orchestrator stops and asks you to approve / request changes / abort before any code is written.

Setting `SDLC_NONINTERACTIVE=true` (see [Headless mode](#headless-mode)) removes interactive prompts, but the pipeline still executes in-session — it does not become a background job.

The final `documentation` phase **autonomously opens a Pull Request** via `gh pr create` (or the GitHub MCP equivalent) once all prior phases complete.

A run survives a lost session: the orchestrator checkpoints its state at every phase boundary in `.claude/.sdlc-run-active.json`, and `/sdlc:start --resume` continues from the first unfinished phase without re-running (or re-paying for) the completed ones. See `pipeline-orchestrator/SKILL.md` Step R.

## Mandatory execution protocol

You MUST follow these steps **in order**, **printing each announcement verbatim** (do not summarize, skip, or collapse them):

### Step 1 — Validate input

If `$ARGUMENTS` is empty **and does not contain `--resume`**: ask the user for a feature description and stop. Do NOT proceed. With `--resume` the description is optional — the orchestrator takes it from the state file.

Extract and strip these flags from the description, remembering each value:

| Flag | Remembered as | Effect |
|---|---|---|
| `--stack=NAME` | `forced_stack` | skips stack auto-detection |
| `--type=NAME` | `forced_task_type` | skips task-type classification (`feature`, `fix`, `bugfix`, `hotfix`, `release`, `refactor`, `docs`, `chore`) |
| `--workflow=NAME` | `forced_workflow` | skips workflow auto-selection |
| `--redetect-git-flow` | `redetect_git_flow` | ignores the cached branching-model detection |
| `--redetect-stack` | `redetect_stack` | ignores the `SessionStart`-hook-written stack-detection cache |
| `--force-preflight` | `force_preflight` | ignores the cached dependency preflight |
| `--resume` | `resume` | continues the in-progress run recorded in `.claude/.sdlc-run-active.json` from its first unfinished phase (orchestrator Step R); mutually exclusive with a new description |

Print verbatim:

```text
▶ /sdlc:start
   Description: <the cleaned-up description>
   Forced stack: <forced_stack or "auto-detect">
   Forced task type: <forced_task_type or "auto-classify">
```

### Step 2 — Invoke the pipeline-orchestrator skill

Use the Skill tool to load and execute the `pipeline-orchestrator` skill. Pass the cleaned-up description and `forced_stack` flag as inputs. **Do not improvise or inline the orchestration logic — delegate to the skill.**

The skill enforces its own MUST-print protocol for stack detection (`🎯 Active stack profiles: ...`), phase boundaries (`▶ Phase N/M: ...`), and the final summary. If you find yourself not printing these — stop, re-read the skill, and start over.

### Step 3 — Hard rules during orchestration

- Do NOT edit project source files directly. The skill dispatches specialist agents for that.
- Do NOT skip the announcement prints. Each phase boundary is a contract with the user.
- Do NOT exit early after BA without running through all phases (unless an earlier phase explicitly aborted with a documented reason).

### Step 4 — On unrecoverable failure

If any phase fails fatally (e.g. agent crashes, post-validation impossible to satisfy):
- Print: `⛔ Pipeline halted at phase: <name>. Reason: <one-line>`
- Write partial telemetry to `docs/plans/{task_slug}/_telemetry.json` with `aborted_at_phase: <name>`.
- Stop. Do not continue.

---

## What the orchestrator skill does

(For your reference — the skill itself contains the authoritative algorithm.)

1. **Step R** — resume check. A fresh state file from an earlier run is never silently overwritten: with `--resume` the run continues at its first unfinished phase; without it you are asked resume / start fresh / abort.
2. **Step 0a** — dependency preflight (reads `runtime-dependencies.json`, checks superpowers etc.).
3. **Step 0b** — stack detection. Reads the `SessionStart`-hook-written cache (`${CLAUDE_PLUGIN_DATA}/stack-cache/`) when fresh; otherwise falls back to a full scan via Glob `~/.claude/plugins/cache/**/stack.md`. Picks highest-priority match per aspect. Prints `🎯 Active stack profiles: ...` (MANDATORY).
4. **Step 0b-git** — branching-model detection, task-type classification, and the branch gate. Prints `🌿 Git flow: ...` (MANDATORY). See `references/GIT-FLOW.md`.
5. **Step 0c** — skip-rules for trivial changes, measured against the detected base branch.
6. **Step 1-2** — parse profile, select the workflow recipe, generate `task_slug`, create `docs/plans/{task_slug}/` and the run state file (`.claude/.sdlc-run-active.json`, updated at every phase boundary).
7. **Step 3** — execute each phase (BA → Dev → [extras] → QA → Sec → Docs) via specialist agents. Compact handoffs.
8. **Step 4** — post-pipeline checks (lint, tests, route:list).
9. **Step 5** — telemetry + final summary (MANDATORY printed).

---

## Examples

```text
/sdlc:start "Add subscription billing with Stripe"
/sdlc:start "Add /healthz endpoint" --stack=vanilla
/sdlc:start "Fix typo in README"
/sdlc:start "Null pointer in payment handler" --type=hotfix
/sdlc:start "Rework the invoice exporter" --redetect-git-flow
/sdlc:start --resume
```

## Headless mode

Set `SDLC_NONINTERACTIVE=true` in the environment — or enable the plugin option `noninteractive` when installing `sdlc` (the environment variable wins when both are set) — to run without interactive prompts (intended for CI / automation):

- `policy=block` dependency failures emit machine-readable JSON to stdout and exit 1 (no install prompts).
- `policy=warn` failures write a single line to stderr and continue.
- `policy=graceful-degrade` is silent in both modes.
- The **branch gate does not ask**: the detected model and task type are used as-is, the branch is created when the current branch is a base branch, and one summary line goes to stderr. Low-confidence detection falls back to github-flow off the default branch. Set `git.auto_create_branch: false` in `.claude/sdlc.local.yaml` to keep CI on whatever branch it checked out.
- The **development plan approval gate** still applies — see `pipeline-orchestrator/SKILL.md` Step 3b-special.

The skill picks up the env var directly (Step 0a-1 in `pipeline-orchestrator/SKILL.md`); no flag is needed on the command line.
