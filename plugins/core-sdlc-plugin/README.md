# core-sdlc-plugin

The orchestration layer for the SDLC marketplace. Provides:

- **`pipeline-orchestrator`** skill — the single, never-modified pipeline runner.
- **5 default agents** with cost-tiered model selection (Opus on critical reasoning, Sonnet on execution, Haiku on structured output).
- **`/sdlc:sdlc-start`** slash command — single entry point to run a pipeline on any project.
- **vanilla `stack.md`** — fallback profile with `priority: 0` that always matches when no framework profile applies.

## What gets installed

```
core-sdlc-plugin/
├── stack.md                                 # vanilla profile
├── commands/sdlc-start.md                   # /sdlc:sdlc-start "<feature>"
├── skills/pipeline-orchestrator/SKILL.md    # 8-step orchestrator
└── agents/
    ├── business-analyst.md       (opus,    read-only tools)
    ├── developer.md              (sonnet,  full implementer)
    ├── qa-engineer.md            (sonnet,  hard 3-attempt iteration cap)
    ├── security-analyst.md       (opus,    OWASP review)
    └── document-writer.md        (haiku,   structured PR output)
```

## How it works

1. User runs `/sdlc:sdlc-start "Add subscription billing"`.
2. The slash command invokes the `pipeline-orchestrator` skill.
3. Orchestrator scans installed plugins for `stack.md` files via `Glob ~/.claude/plugins/cache/**/stack.md`.
4. Picks the highest-priority profile whose `detect` rules match the current project (or falls back to vanilla).
5. Executes phases in order, dispatching to the agent named in `agents_per_phase[<phase>]`.
6. Each phase returns a **compact summary** (≤2-3K tokens). Detailed output is written to `docs/plans/{slug}/0X-<phase>.md`.
7. Runs `post_pipeline_checks` declared by the active stack profile.
8. Writes `_telemetry.json` with per-phase tokens, cost, and skip-rules applied.

## Cost discipline (built in)

| Mechanism | Where |
|---|---|
| Smart model tiering | `agents/*.md` frontmatter `model:` field |
| Iteration cap | `agents/qa-engineer.md` (max 3 attempts) |
| Compact handoffs | Phase prompts in `pipeline-orchestrator/SKILL.md` |
| Skip-rules for trivial changes | `pipeline-orchestrator/SKILL.md` Step 0c |
| Tool restrictions | Per-agent `tools:` allowlist (BA is read-only) |

Target cost: ~$1.40/run for medium features (with prompt caching).

## External dependencies

This plugin declares `obra/superpowers` as a `policy: warn` dependency. If superpowers is not installed, the pipeline still runs but in **degraded mode** for the BA, QA, and Security phases. The preflight check happens once at the start of `/sdlc:sdlc-start`.

In v0.0.1 the preflight is stubbed (always passes). Full implementation lands in Phase 3 per `IMPLEMENTATION_PLAN.md`.
