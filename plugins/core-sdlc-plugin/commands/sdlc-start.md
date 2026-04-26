---
description: Run the full SDLC pipeline (BA → Dev → QA → Security → Docs) for a feature, with auto-detection of the framework stack.
argument-hint: "<feature description> [--stack=NAME]"
---

# /sdlc:sdlc-start

Single entry point for the SDLC pipeline.

## Input

`$ARGUMENTS` — feature description, optionally followed by `--stack=NAME` to override auto-detection.

Examples:
- `/sdlc:sdlc-start "Add subscription billing with Stripe"`
- `/sdlc:sdlc-start "Add /healthz endpoint" --stack=vanilla`

## What this command does

Invoke the `pipeline-orchestrator` skill (defined in `core-sdlc-plugin/skills/pipeline-orchestrator/SKILL.md`) with `$ARGUMENTS` as input.

The orchestrator will:

1. Run dependency preflight (Step 0a — checks superpowers etc.).
2. Auto-detect the stack from installed `stack.md` profiles (Step 0b), unless `--stack=` is specified.
3. Apply skip-rules for trivial changes (Step 0c).
4. Generate a `task_slug` and create `docs/plans/{task_slug}/` for inter-phase communication.
5. Execute the pipeline phases sequentially:
   - business_analysis
   - development (+ any stack-defined extra phases like Laravel's `database`)
   - qa
   - security
   - documentation
6. Run `post_pipeline_checks` from the active stack profile.
7. Write `_telemetry.json` and print a final summary.

## Behavior

- **Cost-conscious:** Each agent uses a tier-appropriate model. QA has a hard 3-attempt iteration cap. Phase handoffs are compact summaries (≤2-3K tokens), not full outputs.
- **Stack-agnostic:** Works on any project. Auto-detects frameworks via `stack.md` profiles. Falls back to vanilla.
- **Recoverable:** If the pipeline aborts mid-way, telemetry and partial artifacts remain in `docs/plans/{task_slug}/`. You can resume by running `/sdlc:sdlc-start` again with the same description.

## Instructions

Read and follow `pipeline-orchestrator/SKILL.md` exactly. Do not improvise. Do not edit project source files directly — that's the agents' job.

If `$ARGUMENTS` is empty, ask the user for a feature description before proceeding.
