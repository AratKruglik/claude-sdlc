# sdlc

The orchestration layer for the SDLC marketplace. It owns the pipeline; framework plugins
register themselves against it via `stack.md` profiles and never modify it.

- **`pipeline-orchestrator`** skill — the single, never-modified pipeline runner.
- **5 default agents**, cost-tiered (Opus on critical reasoning, Sonnet on execution, Haiku on
  structured output).
- **`/sdlc:start`**, **`/sdlc:doctor`**, **`/sdlc:batch`**, **`/sdlc:list-stacks`**,
  **`/sdlc:security-init`** — the command surface.
- **vanilla `stack.md`** — the `priority: 0` fallback profile that matches when no framework
  profile does.

## What gets installed

```
sdlc/
├── stack.md                                  # vanilla profile
├── security-patterns.yaml                    # 6 core_ stack-agnostic rules
├── commands/                                 # start, doctor, batch, list-stacks, security-init
├── skills/
│   ├── pipeline-orchestrator/SKILL.md        # the orchestrator
│   ├── architect-conventions/SKILL.md        # shared architect contract
│   └── batch-pipeline/SKILL.md               # parallel worktree runs
├── workflows/                                # default, bugfix, hotfix, refactor, docs-only
├── references/                               # pricing.json, task-type-patterns.json, GIT-FLOW.md
├── scripts/                                  # detect-stack.sh, usage-report.sh, detect-git-flow.sh
├── evals/                                    # 4 behavioural eval cases
├── hooks/                                    # see below
└── agents/
    ├── business-analyst.md       (opus,   maxTurns 80, read-only + Skill)
    ├── developer.md              (sonnet, maxTurns 120, vanilla implementer)
    ├── qa-engineer.md            (sonnet, maxTurns 60, hard 3-attempt cap)
    ├── security-analyst.md       (opus,   maxTurns 80, report-only — no Edit)
    └── document-writer.md        (haiku,  maxTurns 30, structured PR output)
```

## Hooks

| Hook | Event | Purpose |
|---|---|---|
| `enforce-agent-model.sh` | `PreToolUse` / `Agent` | rewrites the dispatch model to the agent's declared tier |
| `dispatch-log.sh` | `PreToolUse` / `Agent`, `SubagentStart` | records each dispatch and its assigned `agent_id` |
| `subagent-usage.sh` | `SubagentStop` | meters the finished subagent's transcript and prices it |
| `pre-commit-guard.sh` | `PreToolUse` / `Bash` | denies `--no-verify` and staged secrets during a run |
| `config-protection.sh` | `PreToolUse` / `Edit\|Write` | shared by stack plugins; denies mid-run tooling-config edits |
| `post-implement-check.sh` | `SubagentStop` | shared by stack plugins; runs their typecheck once per architect |
| `session-start-stack-cache.sh` | `SessionStart` | precomputes stack detection into `${CLAUDE_PLUGIN_DATA}/stack-cache/` |

Every one of them is a no-op outside a pipeline run, and every one fails open.

## How it works

1. User runs `/sdlc:start "Add subscription billing"`.
2. The slash command invokes the `pipeline-orchestrator` skill.
3. The orchestrator resolves the stack profile per aspect (cache first, full scan otherwise),
   detects the git branching model, classifies the task type and proposes a branch.
4. It resolves a workflow recipe into a list of **groups** — a group is one pipeline step, and
   its members are dispatched concurrently.
5. Each dispatch returns a **compact summary** (≤2–3K tokens); detailed output goes to
   `docs/plans/{slug}/0X-<phase>.md`.
6. Development runs two passes around a human approval gate: Opus plans, Sonnet implements.
7. `post_pipeline_checks` from the active profile run at the end.
8. `_telemetry.json` is written with **measured** per-dispatch tokens and cost, then the run
   state file is deleted.

Everything runs synchronously in the current session — there is no detached execution. The
`documentation` phase opens the PR via `gh pr create`.

## `/sdlc:start` flags

| Flag | Effect |
|---|---|
| `--resume` | continue a crashed or compacted run at the phase it reached |
| `--stack=NAME` | force a stack profile instead of auto-detecting |
| `--type=NAME` | force the task type instead of classifying it |
| `--workflow=NAME` | force a workflow recipe |
| `--redetect-stack` | ignore the session stack cache |
| `--redetect-git-flow` | ignore the cached branching-model detection |
| `--force-preflight` | re-run the dependency preflight instead of using its cache |

## Cost discipline

| Mechanism | Where |
|---|---|
| Model tiering + `effort` | `agents/*.md` frontmatter |
| Two-tier development phase | `model_plan:` (Opus plans) vs `model:` (Sonnet implements) |
| Turn ceilings | `maxTurns:` per agent — a stuck agent costs a bounded amount |
| QA iteration cap | `agents/qa-engineer.md`, max 3 attempts |
| Compact handoffs | phase prompts in `pipeline-orchestrator/SKILL.md` |
| Skip-rules | `SKILL.md` Step 0c — four rules, each with its own trigger |
| Workflow cost caps | `caps.max_total_cost_usd` in a recipe |
| Tool restrictions | per-agent `tools:` allowlist |

Cost per run is **measured, not assumed** — see
[Measured Telemetry](../../README.md#measured-telemetry). Read your own
`docs/cost-baseline.md` rather than any figure quoted in documentation; prices come from
[`references/pricing.json`](references/pricing.json).

## External dependencies

`runtime-dependencies.json` declares external plugins (`obra/superpowers` and others) with a
per-plugin policy. All current entries are `policy: warn`: when one is missing the pipeline
still runs, with reduced rigor in the phases that would have used it, and the orchestrator sets
a `{plugin}_unavailable` flag the phase prompts read. The preflight runs once per session and
caches its result to `${CLAUDE_PLUGIN_DATA}/deps-preflight.json`; `--force-preflight` re-runs it.
