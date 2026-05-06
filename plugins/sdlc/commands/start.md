---
description: Run the full SDLC pipeline (BA → Dev → QA → Security → Docs) for a feature, with auto-detection of the framework stack.
argument-hint: "<feature description> [--stack=NAME]"
---

# /sdlc:start

Single entry point for the SDLC pipeline.

## Mandatory execution protocol

You MUST follow these steps **in order**, **printing each announcement verbatim** (do not summarize, skip, or collapse them):

### Step 1 — Validate input

If `$ARGUMENTS` is empty: ask the user for a feature description and stop. Do NOT proceed.

If `$ARGUMENTS` contains `--stack=NAME`: extract the value and remember it as `forced_stack`. Strip it from the description.

Print verbatim:
```
▶ /sdlc:start
   Description: <the cleaned-up description>
   Forced stack: <forced_stack or "auto-detect">
```

### Step 2 — Invoke the pipeline-orchestrator skill

Use the Skill tool to load and execute the `pipeline-orchestrator` skill. Pass the cleaned-up description and `forced_stack` flag as inputs. **Do not improvise or inline the orchestration logic — delegate to the skill.**

The skill enforces its own MUST-print protocol for stack detection (`🎯 Detected stack: ...`), phase boundaries (`▶ Phase N/M: ...`), and the final summary. If you find yourself not printing these — stop, re-read the skill, and start over.

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

1. **Step 0a** — dependency preflight (reads `runtime-dependencies.json`, checks superpowers etc.).
2. **Step 0b** — stack detection via Glob `~/.claude/plugins/cache/**/stack.md`. Picks highest-priority match. Prints `🎯 Detected stack: ...` (MANDATORY).
3. **Step 0c** — skip-rules for trivial changes.
4. **Step 1-2** — parse profile, generate `task_slug`, create `docs/plans/{task_slug}/`.
5. **Step 3** — execute each phase (BA → Dev → [extras] → QA → Sec → Docs) via specialist agents. Compact handoffs.
6. **Step 4** — post-pipeline checks (lint, tests, route:list).
7. **Step 5** — telemetry + final summary (MANDATORY printed).

---

## Examples

```
/sdlc:start "Add subscription billing with Stripe"
/sdlc:start "Add /healthz endpoint" --stack=vanilla
/sdlc:start "Fix typo in README"
```

## Headless mode

Set `SDLC_NONINTERACTIVE=true` in the environment to run without interactive prompts (intended for CI / automation):

- `policy=block` dependency failures emit machine-readable JSON to stdout and exit 1 (no install prompts).
- `policy=warn` failures write a single line to stderr and continue.
- `policy=graceful-degrade` is silent in both modes.

The skill picks up the env var directly (Step 0a-1 in `pipeline-orchestrator/SKILL.md`); no flag is needed on the command line.
