# Claude SDLC Marketplace — Architecture

> A Claude Code plugin marketplace for a complete AI-assisted SDLC that works on any technology stack (Laravel, Django, NestJS, .NET, …).
>
> **Principle:** The core owns the pipeline and does not change. Framework plugins **register themselves** as stack providers via a declarative profile and provide specialized agents. The core reads the profiles and composes the execution.

---

## 1. Key Concept: Stack Provider Pattern

```
┌─────────────────────────────────────────────────────────────┐
│                    sdlc                                     │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  pipeline-orchestrator (skill) — DOES NOT CHANGE     │  │
│  │                                                      │  │
│  │  Phase 1: BA          → core's business-analyst      │  │
│  │  Phase 2: Dev         → ⚡ DISPATCH to stack provider│  │
│  │  Phase 3: QA          → core's qa-engineer           │  │
│  │  Phase 4: Security    → core's security-analyst      │  │
│  │  Phase 5: Docs/PR     → core's document-writer       │  │
│  └──────────────────────────────────────────────────────┘  │
│                            ▲                                │
│                            │ reads stack profiles           │
└────────────────────────────┼────────────────────────────────┘
                             │
              ┌──────────────┼──────────────┐
              │              │              │
       ┌──────▼─────┐ ┌──────▼─────┐ ┌─────▼──────┐
       │  laravel-  │ │  django-   │ │  nestjs-   │
       │   plugin   │ │   plugin   │ │   plugin   │
       │            │ │            │ │            │
       │ stack.md   │ │ stack.md   │ │ stack.md   │
       │ + agents   │ │ + agents   │ │ + agents   │
       │ + skills   │ │ + skills   │ │ + skills   │
       │ + .mcp     │ │ + .mcp     │ │ + .mcp     │
       └────────────┘ └────────────┘ └────────────┘
```

**Contract between core and framework plugin:**

1. The framework plugin places a `stack.md` file at a known path (the root of the plugin).
2. The framework plugin provides agents with stack-specific specialization (e.g., `laravel-architect`, `artisan-specialist`).
3. The core orchestrator reads `stack.md`, selects the highest-priority profile whose `detect` check succeeds, and dispatches to the correct agents.

**What we explicitly DO NOT do** (conscious decisions, not optimizations):

- No "Slot Registry", public slot contract, or four-layer model (core/stack/capability/domain). Everything lives in `stack.md` and agent naming conventions.
- No override mechanism in framework plugins regarding the core. The framework **adds itself**; it does not edit the core.
- No capability or domain plugins in v1.0. If something cross-cutting (like postgres, github-actions) is needed, it lives within the framework plugin that uses it for now.

---

## 2. File Structure

```
sdlc-marketplace/
├── .claude-plugin/
│   └── marketplace.json                 ← v0.1.0: 12 entries (2 external + 10 local)
├── schemas/
│   ├── plugin.schema.json               ← JSON schema for plugin.json
│   └── stack.schema.json                ← JSON schema for stack.md frontmatter
│
├── plugins/
│   ├── sdlc/
│   │   ├── .claude-plugin/plugin.json
│   │   ├── commands/
│   │   │   ├── start.md                 ← /sdlc:start "feature description"
│   │   │   ├── batch.md                 ← /sdlc:batch (parallel execution)
│   │   │   ├── list-stacks.md           ← /sdlc:list-stacks
│   │   │   ├── doctor.md                ← /sdlc:doctor (preflight + dep check)
│   │   │   └── security-init.md         ← /sdlc:security-init (security patterns)
│   │   ├── skills/
│   │   │   └── pipeline-orchestrator/
│   │   │       └── SKILL.md             ← SINGLE orchestrator (955 lines)
│   │   ├── agents/
│   │   │   ├── business-analyst.md      ← opus + effort:high (critical reasoning)
│   │   │   ├── developer.md             ← sonnet + model_plan:opus (vanilla fallback)
│   │   │   ├── qa-engineer.md           ← sonnet + effort:medium (with iteration cap)
│   │   │   ├── security-analyst.md      ← opus + effort:xhigh (silent-failure risk)
│   │   │   └── document-writer.md       ← haiku + effort:low (structured output)
│   │   └── stack.md                     ← vanilla profile (priority: 0)
│   │
│   ├── js-foundation/                   ← shared TS/npm skills, no stack profile
│   │   └── skills/                      ← typescript-patterns, npm-patterns
│   ├── nodejs-plugin/                   ← Node.js/Express/Fastify (priority: 100)
│   │   └── agents/node-architect.md     ← sonnet + model_plan:opus
│   ├── nestjs-plugin/                   ← NestJS backend (priority: 200)
│   │   └── agents/nest-architect.md     ← sonnet + model_plan:opus
│   ├── nextjs-plugin/                   ← Next.js full-stack (priority: 250)
│   │   └── agents/nextjs-architect.md   ← sonnet + model_plan:opus
│   ├── react-plugin/                    ← React SPA frontend (priority: 150)
│   │   └── agents/react-architect.md    ← sonnet + model_plan:opus
│   ├── vue-plugin/                      ← Vue 3 SPA frontend (priority: 150)
│   │   └── agents/vue-architect.md      ← sonnet + model_plan:opus
│   ├── angular-plugin/                  ← Angular 18-21 frontend (priority: 200)
│   │   └── agents/angular-architect.md  ← sonnet + model_plan:opus
│   ├── react-native-plugin/             ← React Native mobile (priority: 300)
│   │   └── agents/rn-architect.md       ← sonnet + model_plan:opus
│   │
│   └── laravel-plugin/
│       ├── .claude-plugin/plugin.json   ← dependencies: sdlc
│       ├── stack.md                     ← Laravel stack profile (priority: 100)
│       ├── agents/
│       │   ├── laravel-architect.md     ← Sonnet impl + Opus plan pass
│       │   └── artisan-specialist.md    ← Sonnet, for extra phase "database"
│       ├── skills/
│       │   ├── laravel-conventions/SKILL.md
│       │   └── eloquent-patterns/SKILL.md
│       ├── .mcp.json                    ← laravel-boost, etc.
│       └── hooks/hooks.json             ← pint auto-format on Stop
```

> **Key Detail:** There is no `pipeline-orchestrator/` in `laravel-plugin`. Core files remain untouched. The Laravel plugin only adds `stack.md` + specialized agents + convention skills.

---

## 3. Stack Profile — Contract between Core and Framework

`stack.md` is standard markdown with YAML frontmatter. The core orchestrator knows how to read it.

### 3.1. Vanilla profile (`sdlc/stack.md`)

```markdown
---
stack: vanilla
priority: 0
detect:
  any: ["*"]
---

# Vanilla Stack Profile

## Agents per phase
- business_analysis: business-analyst
- development: developer
- qa: qa-engineer
- security: security-analyst
- documentation: document-writer

## Convention skills to apply
- (none)

## Pre-phase commands
- (none)

## Post-phase commands
- (none)
```

`priority: 0` + `detect.any: ["*"]` means: always matches, but loses to any profile with a higher priority.

### 3.2. Laravel profile (`laravel-plugin/stack.md`)

```markdown
---
stack: laravel
priority: 100
detect:
  all:
    - file_exists: composer.json
    - file_contains:
        path: composer.json
        pattern: '"laravel/framework"'
---

# Laravel Stack Profile

## Agents per phase
- business_analysis: business-analyst        # core agent
- development: laravel-architect              # ⚡ Laravel-specific
- database: artisan-specialist                # ⚡ extra phase
- qa: qa-engineer                             # core agent
- security: security-analyst                  # core agent
- documentation: document-writer              # core agent

## Convention skills to apply
- laravel:laravel-conventions
- laravel:eloquent-patterns

## Extra phases
- name: database
- after: development
- agent: artisan-specialist
- description: "Run migrations, factories, seeders"

## Phase prompts injection

For development phase, inject:
  "Use Artisan commands for code generation: php artisan make:model -mfsc, etc.
   Follow PSR-12 and Laravel conventions.
   Apply skills: laravel:laravel-conventions, laravel:eloquent-patterns"

For qa phase, inject:
  "Use Pest/PHPUnit with Laravel testing helpers (RefreshDatabase, actingAs).
   Run: php artisan test --coverage"

For security phase, inject:
  "Check Laravel-specific issues: mass assignment, Gates/Policies coverage,
   raw query usage, .env exposure, debug mode in production."

## Post-pipeline checks
- ./vendor/bin/pint --test
- php artisan test
- php artisan route:list
```

### 3.3. Frontmatter spec

| Field | Type | Required | Description |
|---|---|---|---|
| `stack` | string | ✅ | Unique stack name (`laravel`, `django`, `nestjs`, `vanilla`). |
| `priority` | int | ✅ | 0 — always-match fallback; 100+ — specific framework. Higher = winner. |
| `detect.any` / `detect.all` | array | ✅ | Auto-detection rules. `["*"]` for vanilla. |
| `detect.*.file_exists` | string | — | File that must exist in the project root. |
| `detect.*.file_contains` | object | — | `{path, pattern}` — regex check of the file content. |

---

## 4. Pipeline Orchestrator (The Only Core Skill)

`sdlc/skills/pipeline-orchestrator/SKILL.md` is the heart of the system.

### 4.1. Algorithm (8 Steps)

```
Step 0a · Load declared external plugin dependencies (DEPENDENCIES.md)
Step 0b · Detect stack profile via Glob ~/.claude/plugins/cache/**/stack.md
Step 1  · Parse selected profile
Step 2  · Determine phase order (baseline + extras)
Step 3  · Execute each phase:
            - Look up agent in profile
            - Build prompt: base + injection + previous-phase summary
            - Spawn agent with token-budget aware prompt
            - Save COMPACT summary to CONTEXT.{phase}_output
Step 4  · Run post_pipeline_checks via Bash
Step 5  · Final summary (stack used, phases executed, costs, PR link)
```

### 4.2. Base Phase Prompts

```
business_analysis:
  > Analyze: $ARGUMENTS
  > Produce: user stories (Gherkin), acceptance criteria, data model, API contract, edge cases.
  > {INJECTED_PROMPT}
  > Return COMPACT summary (≤2K tokens): scope bullets + 5 user stories + open questions.

development:
  > Implement based on: $CONTEXT.business_analysis_output
  > Follow project conventions in CLAUDE.md.
  > Apply convention skills: {convention_skills}
  > {INJECTED_PROMPT}
  > Return COMPACT summary: files changed (list) + key decisions (3–5 bullets) + blockers.

qa:
  > Write and run tests for changes referenced in $CONTEXT.development_output.
  > Aim ≥80% coverage. Max 3 attempts to fix failing tests — then STOP and report.
  > {INJECTED_PROMPT}
  > Return COMPACT summary: tests added/passed/failed + coverage % + open issues.

security:
  > Review changes referenced in $CONTEXT.development_output for OWASP Top 10.
  > Fix Critical and High severity issues. Skip Low/Info unless trivially safe.
  > {INJECTED_PROMPT}
  > Return COMPACT summary: issues found (severity, file:line) + fixes applied.

documentation:
  > Create a Pull Request.
  > Inputs: $CONTEXT.business_analysis_output, $CONTEXT.qa_output, $CONTEXT.security_output.
  > {INJECTED_PROMPT}
  > Return: PR URL + 1-paragraph release-notes blurb.
```

"COMPACT summary" is a critical cost optimization (see §6). The next phase reads the project files directly rather than receiving a dump of the previous phase's output.

### 4.3. Skip-rules for Trivial Changes

Before starting the pipeline, the orchestrator analyzes the scope (from $ARGUMENTS):

| Signal | Action |
|---|---|
| Diff < 50 LOC, no new files, no DB migrations | Skip Security — use lightweight check in dev. |
| Description contains "typo", "rename var", "format" | Skip BA — use $ARGUMENTS directly as spec. |
| Description contains "config tweak", "env var" | Skip QA — keep only post_pipeline_checks. |

Skip-rules save 30–60% of the cost for minor tasks. Without them, running the pipeline for a typo fix would cost as much as a full feature.

---

## 5. Default Core Agents (5 Agents with Built-in Tiering)

All 5 agents live in `sdlc/agents/`. The model and `effort` are selected based on the "cost of mistakes" principle — Opus+high is used where errors would compound across the entire pipeline.

### 5.0. Model + effort assignment

The authoritative table covering all 29 agents lives in `README.md` → "Cost Optimization: model + effort", generated from agent frontmatter. It is not duplicated here. The rationale behind the assignment — including why the ratios that justified it changed, and what was deliberately left alone — is in `MODEL-ROUTING.md`.

Core agents and their least-privilege tool sets:

| Agent | model | model_plan | effort | Tools (least-privilege) |
|---|---|---|---|---|
| `business-analyst` | **opus** | — | `high` | Read, Glob, Grep, Write, WebSearch, WebFetch |
| `developer` (vanilla fallback) | **sonnet** | **opus** | `medium` | Read, Glob, Grep, Edit, Write, Bash |
| `qa-engineer` | **sonnet** | — | `medium` | Read, Glob, Grep, Edit, Write, Bash |
| `security-analyst` | **opus** | — | `xhigh` | Read, Glob, Grep, Edit, Write, WebSearch, WebFetch |
| `document-writer` | **haiku** | — | `low` | Read, Glob, Grep, Write, Bash, mcp__github__* |

Stack architects follow the same shape as `developer`: `sonnet` for implementation, `opus` for the planning pass. Database specialists are `sonnet`/`low` with no planning pass — they run in a separate phase.

> **About temperature and effort:**
> Claude Code does not support per-subagent `temperature` in frontmatter. Reasoning budget is controlled exclusively via `effort` (`low`/`medium`/`high`/`xhigh`/`max`), which overrides the session level.
>
> `model` and `effort` are not symmetric levers. `model` can be overridden per dispatch through the `Agent` tool's `model` parameter; `effort` cannot — it is read from frontmatter only. That is why the development phase varies the model between its planning and implementation passes but keeps one `effort` value across both.

### 5.1. Iteration Cap in QA (Runaway Costs Safeguard)

`qa-engineer.md`:

```markdown
## Hard limit: iteration cap

You have a maximum of **3 attempts** to fix failing tests.
After attempt #3:
  STOP. Do not iterate further.
  Return COMPACT summary including:
    - Tests still failing (file:test name)
    - Last error messages (1-2 lines each)
    - Hypothesis why they fail (1 paragraph)
  Mark phase as 'incomplete-blocked'.

This is non-negotiable. Runaway iterations have caused $50+ per pipeline.
```

Without this cap, a single flaky test can burn $5 worth of tokens in a single run.

### 5.2. Tool Restrictions = Security + Cost

`business-analyst` has **only read-only** tools — it cannot accidentally run migrations or modify code. This ensures both security and cost savings: fewer tools mean fewer accidental heavy calls.

---

## 6. Cost-Conscious Design (Built into the Architecture)

### 6.1. Run Budget

Target budget for a medium-complexity feature (e.g., "Stripe billing module"). Estimates, not measurements — `docs/cost-baseline.md` holds the measured figures once runs are aggregated.

All rows below are **standard list pricing, before prompt-cache savings** — the same basis as the per-phase table in `README.md` → "Estimated cost for a medium feature", so the two documents report the same quantity. The bottom row is that table's total.

| Scenario | Cost/run |
|---|---|
| Uniform Opus across every phase | ~$3.20 |
| Model tiering (opus / sonnet / haiku) | ~$1.84 |
| + two-tier development phase (opus plans, sonnet implements) | ~$2.34 |
| + `effort: xhigh` on security review | **~$2.40** ← current, matches README |

Two further reductions apply on top and are not stacked into the ladder, because they vary per run rather than per configuration: the Sonnet introductory rate through 2026-08-31 brings the same configuration to **~$1.98**, and prompt caching reduces repeated input further (~60% hit rate on stable prefixes).

The two-tier development phase and the security `effort` bump both move the number *up*. That is intentional and argued in `MODEL-ROUTING.md` §7: the target is cost per completed task, and a rework cycle on a medium feature costs more than the delta. The levers that move it down — skip-rules, the QA iteration cap, compact handoffs, prompt caching — are unchanged and still carry most of the savings.

Note also that the ratio driving all of this shifted: Opus is now ~1.67× Sonnet per input token rather than 5×, which is why uniform-Opus is no longer the catastrophe the original table implied, and why tiering alone is no longer the dominant lever.

### 6.2. Four Hotspots Addressed by Design

| Hotspot | Architectural Answer |
|---|---|
| **Context duplication between subagents** (~30–50K duplicate tokens per pipeline) | Subagents read project files themselves via the filesystem instead of receiving them in the prompt. Compact summaries are used between phases. |
| **Tool call results bloating the input of the next agent** (test logs 5–20K, file reads 3–8K) | Each agent returns a COMPACT summary (≤2-3K). Details remain in the agent's own context window and are not forwarded. |
| **Infinite QA iteration loops** (3–5 cycles × 10K) | Iteration cap = 3 attempts in `qa-engineer.md`. Beyond that — STOP + report. |
| **Context accumulation from phase to phase** (60–100K additional input tokens) | The orchestrator passes only the latest summary, not the entire history. Older summaries are available via files (`docs/plans/{slug}/0X-*.md`) instead of the prompt. |

### 6.3. Prompt Caching as a Design Principle

Claude Code performs prompt caching automatically, but **only for stable system prompts**. This means:

- Agent frontmatter is stable (not dynamically generated).
- Phase prompt injection goes at the very end of the prompt (to cache the prefix).
- Skill content is NOT dynamically generated — it remains static markdown.

Expected cache hit rate with stable prompts: 60% on Sonnet, 40% on Opus → ~30% input discount.

### 6.4. Skip-rules and Phase Parallelism

- **Skip-rules** (§4.3) reduce the cost of trivial tasks by 2–3×.
- **Security ∥ QA parallelism** (V2) — they have no interdependencies. Cuts wall-clock time in half. Implementation scheduled for Phase 6+.

### 6.5. Telemetry for Cost Discipline

The orchestrator writes to `docs/plans/{slug}/_telemetry.json` after each pipeline run:

```json
{
  "stack": "laravel",
  "phases": [
    { "phase": "ba", "model": "opus", "input_tokens": 35000, "output_tokens": 3000, "cost_usd": 0.16 },
    { "phase": "dev", "model": "sonnet", "input_tokens": 42000, "output_tokens": 8500, "cost_usd": 0.25 }
  ],
  "total_cost_usd": 1.42,
  "cost_scope": "subagent_phases_only",
  "total_wall_clock_s": 187,
  "skip_rules_applied": ["security:diff<50loc"]
}
```

This tracks the cost-per-feature trend and answers "where are tokens being burned." If costs exceed the budget, telemetry isolates the specific phase.

`cost_scope` is a warning label, not decoration: only subagent spawns are metered. The orchestrator's own consumption — this skill's body, profile globbing and parsing, workflow resolution, approval-gate exchanges — runs on the session model and cannot be measured from inside the skill. `total_cost_usd` is a floor, and the gap against an actual invoice is the orchestrator, not a metering bug.

---

## 7. External Plugin Dependencies (Superpowers)

Plugins in our marketplace can depend on external Claude Code plugins (like `obra/superpowers`) to reuse their skills — without copying third-party code into our repository.

### 7.1. Realistic Boundaries

Claude Code lacks native dependency resolution. Silent auto-install is **technically impossible**: slash commands (`/plugin install`) can only be executed by the user. Therefore, our strategy is **guided install**:

1. Declare the dependency in `plugin.json`.
2. At pipeline startup, the orchestrator performs a single preflight check.
3. If missing, we act according to the policy (`block` / `warn` / `graceful-degrade`) and, if `mcp__plugins__suggest_plugin_install` is available, offer a one-click install.

This is the **only** checkpoint in the new architecture. No 4-layer checks, project-level configurations, or runtime verifications inside individual agents.

### 7.2. Dependency Manifest in `plugin.json`

```jsonc
{
  "name": "sdlc",
  "version": "1.0.0",
  "dependencies": {
    "plugins": [
      {
        "name": "superpowers",
        "marketplace": "obra/superpowers",
        "version": ">=1.0.0",
        "policy": "warn",
        "skills_used": [
          "thinking-deeply",
          "test-driven-development",
          "verification-before-completion"
        ],
        "fallback_note": "Pipeline runs without these but with reduced rigor in BA and QA phases."
      }
    ]
  }
}
```

### 7.3. Three Policies for Missing Dependencies

| Policy | Behavior | When to Use |
|---|---|---|
| `block` | Pipeline halts. Suggest install. User runs `/sdlc:start` again after installation. | Without the skill, the output will be incorrect (rare case). |
| `warn` | Pipeline continues with a message: "running in degraded mode for X". | **Default.** Most external skills are enhancements, not blockers. |
| `graceful-degrade` | Silent fallback injection. Telemetry entry only. | The skill is a nice bonus; the user won't notice the difference. |

### 7.4. Preflight Check — A Single Check

In `pipeline-orchestrator/SKILL.md` Step 0a:

```
Step 0a — Verify external plugin dependencies

For each entry in plugin.json's dependencies.plugins:
  1. Call mcp__skills__list_skills.
  2. Check if every skill in skills_used is present (as `{name}:{skill}`).
  3. If all present: continue silently.
  4. If missing AND policy=block:
       Print install command and abort with exit=1.
       Suggest mcp__plugins__suggest_plugin_install if available.
  5. If missing AND policy=warn:
       Print warning. Set context flag {dep}_unavailable=true.
       Continue. Each agent that uses these skills falls back gracefully.
  6. If missing AND policy=graceful-degrade:
       Silently set context flag. Continue.

In headless mode (env SDLC_NONINTERACTIVE=true):
  - block → exit 1 with machine-readable JSON
  - warn → stderr message, continue
  - graceful-degrade → silent
```

Implementation details + JSON Schema are in `DEPENDENCIES.md`. The short version is in v1.0.

### 7.5. What We Do NOT Do Regarding Dependencies

- We do **not** check in every agent — only in the orchestrator at startup.
- We do **not** implement project-level `.claude-sdlc.json` overrides in v1.0 — the manifest is sufficient.
- We do **not** remember a declined installation between sessions — the user might have installed the plugin in the meantime.
- We do **not** poll in a loop after `suggest_plugin_install` — asynchronous installation is unverifiable; aborting and repeating the command is more honest.

---

## 8. Practical Usage

```bash
# Installation (one-time)
/plugin marketplace add your-org/sdlc-marketplace
/plugin install laravel-plugin@sdlc-marketplace
# sdlc will be pulled in as a dependency

# Status check
/sdlc:doctor
# → ✅ sdlc@1.0.0
# → ✅ laravel-plugin@1.0.0
# → ⚠️  superpowers: missing (policy=warn) — pipeline runs in degraded mode

# View detected profiles
/sdlc:list-stacks
# 🎯 vanilla   priority=0   (always matches)
# 🎯 laravel   priority=100 (matches: composer.json + laravel/framework)

# Pipeline run (one command for all stacks)
/sdlc:start "Add subscription billing with Stripe"
# → Detected stack: laravel (from laravel-plugin/stack.md)
# → Phase 1/6: business_analysis (Opus)
# → Phase 2/6: development → laravel-architect (Sonnet)
# → Phase 3/6: database → artisan-specialist (Sonnet) [extra phase]
# → Phase 4/6: qa (Sonnet)
# → Phase 5/6: security (Opus)
# → Phase 6/6: documentation (Haiku)
# → Post-pipeline: pint --test, php artisan test, route:list
# → ✅ Completed in 187s, $1.42 spent, PR #142

# Explicit stack override
/sdlc:start --stack=vanilla "Add a /healthz endpoint"
# → Ignores Laravel, uses default core agents
```

---

## 9. How to Add a New Framework

Without any core changes. Example for Django:

```
django-plugin/
├── .claude-plugin/plugin.json     ← dependencies: sdlc
├── stack.md                        ← detect: manage.py + django in requirements.txt
├── agents/
│   ├── django-architect.md        ← Sonnet
│   └── drf-specialist.md          ← Sonnet (extra phase: api-layer)
├── skills/
│   ├── django-conventions/SKILL.md
│   └── orm-patterns/SKILL.md
├── .mcp.json                       ← postgres MCP, django docs
└── hooks/hooks.json                ← black/ruff on Stop
```

`django-plugin/stack.md`:

```markdown
---
stack: django
priority: 100
detect:
  all:
    - file_exists: manage.py
    - file_contains: { path: requirements.txt, pattern: "django" }
---

## Agents per phase
- development: django-architect
- (others use core)

## Convention skills
- django:django-conventions
- django:orm-patterns

## Phase prompts injection
For development phase, inject:
  "Use Django management commands: manage.py startapp, makemigrations.
   Follow PEP 8, Django coding style. Apply skills: django-conventions, orm-patterns."
```

That's it. On the next `/sdlc:start` run, the core orchestrator will find the new profile via Glob, evaluate the detection rules, and use `django-architect` instead of the vanilla `developer`.

---

## 10. What We Gain

| Property | How it Works |
|---|---|
| **Core remains unchanged** | `pipeline-orchestrator` lives strictly in core. No framework plugin touches it. |
| **DRY** | Pipeline logic is written once. Core bug fixes are automatically inherited by all frameworks. |
| **Extensibility** | New framework = new plugin with its own `stack.md` + specialized agents. No orchestrator rewrite required. |
| **Auto-detection** | Core reads project files and identifies the stack automatically. Overrides available via `--stack=name`. |
| **Composition without override** | Laravel leverages core's BA/QA/Security/Docs, substituting only its own agent for development. |
| **Extra phases** | Laravel adds the `database` phase. The vanilla pipeline simply skips it. |
| **Convention enforcement via skills** | Laravel skills (`laravel-conventions`, `eloquent-patterns`) are automatically applied via the profile. |
| **Cost-conscious by design** | Smart model tiering, compact handoffs, iteration cap, and skip-rules are built-in defaults. |

---

## 10.5. Profile Composition for Multi-Aspect Projects (Phase 4-5 Evolution)

> **Current Limitation:** The orchestrator on Step 0b selects a **single** profile (the one with the highest priority among matches). This works for single-stack projects but **breaks on a typical Laravel project** that has both a backend (`composer.json`) and a frontend (`package.json` with Vue/React/Livewire). Currently, the `laravel-plugin` conceals this limitation via a monolithic `laravel-architect` ("Full-stack Laravel + Inertia + Vue"). This is a silent issue for other frontend options.

**Planned Solution (Phase 4-5):** **aspect-tagged profiles + phase fan-out.** Each profile declares `aspects:` (`backend`, `frontend`, `database`, `infra`, `testing`). The orchestrator selects a **winner for EACH aspect separately**, rather than for the project as a whole. Aspect-aware phases (`development`, `qa`) sequentially execute the agent associated with each relevant aspect.

Examples (post-Phase 5):

| Project Type | Auto-activated Plugins (via aspect resolution) |
|---|---|
| Laravel + Inertia + Vue | `laravel-plugin` (backend, database) + `inertia-vue-plugin` (frontend) |
| Laravel + Inertia + React | `laravel-plugin` + `inertia-react-plugin` |
| Laravel + Livewire | `laravel-plugin` + `laravel-livewire-plugin` |
| Laravel API-only | `laravel-plugin` only (frontend slot empty) |
| Pure Next.js (no PHP) | `nextjs-plugin` only |

**`laravel-plugin` will be split** in Phase 5: backend and database aspects will remain, while frontend (Inertia+Vue) will move to a dedicated `inertia-vue-plugin`. The current `laravel-architect` will become backend-only; Inertia/Vue domain knowledge will live in the new `inertia-vue-architect`.

**Current Workaround (v0.0.1) for non-Vue Laravel projects:** via `<project>/.claude/sdlc.local.yaml` `extra_phase_prompts` or `CLAUDE.md` — see details in `PROJECT_INTEGRATION.md` §8.

**Full architecture, alternatives considered, and migration path:** [`docs/decisions/ADR-014-aspect-tagged-profiles.md`](./docs/decisions/ADR-014-aspect-tagged-profiles.md).

---

## 11. Conscious Limitations of v1.0

| What We Avoid | Why |
|---|---|
| Slot Registry, 4 layers (core/stack/capability/domain) | Unjustified complexity — `stack.md` is sufficient. |
| Capability plugins (postgres, github-actions separately) | If a framework requires it, we bundle it with the framework plugin. Will extract in V2 if real-world need arises. |
| Domain plugins (fintech, saas) | Same as above. |
| Override mechanisms in framework plugins | Profile composition covers all use cases. Overrides lead to a cascade of pain. |
| Project-level config for dep-policy | Manifest is sufficient. |
| Custom CLI installer | Native `/plugin install` provides necessary leverage. |
| Security ∥ QA Parallelism | V2 — complex orchestration. In v1.0, sequential execution is more reliable. |
| 4-layer dep check (lint/doctor/preflight/runtime) | One-shot preflight check in the orchestrator. The rest is overengineering. |

---

## 12. Referenced Patterns

This approach is not invented by us — it is the exact same pattern used by:

| System | Analogy |
|---|---|
| **Webpack** | Loaders/plugins are registered; bundler remains unchanged. |
| **Symfony Bundles** | Bundles register services; the core is untouched. |
| **VS Code Extensions** | Extensions add contributions without rewriting the editor. |
| **Maven Lifecycle** | Plugins bind to lifecycle phases. |

All of these systems have scaled for decades because the contract of "registration via declaration + conventional extension points" is far simpler than overrides.

---

## 13. Open Questions (To Be Resolved During Implementation)

1. **Exact plugin cache path.** `~/.claude/plugins/cache/**/stack.md` is an assumption. Verify in Phase 0 on the live system and pin it down in the orchestrator skill.
2. **How the core orchestrator calculates `diff < 50 LOC`** for skip-rules — `git diff` against `main`, or another method? To be finalized in Phase 3.
3. **Should `--stack` override in `/sdlc:start` persist across runs** within a session? For now, no — each run is treated independently.
4. **Version compatibility between core@X and framework-plugin@Y.** For now, the `dependencies` block in `plugin.json` uses semver. Standard versioning rules apply.
5. **Telemetry aggregation across multiple runs** — whether to build a dashboard or keep it as per-run JSON. Scheduled for Phase 6+ as real-world needs emerge.

---

## 14. Reference Summary

> **Framework plugins do not override the core. They register themselves via a declarative profile (`stack.md`) and provide specialized agents/skills. The core pipeline reads the profiles and composes execution. Cost discipline is built into the design, not optimized post-factum.**

Step-by-step implementation details — `IMPLEMENTATION_PLAN.md`.  
External dependencies (superpowers, etc.) — `DEPENDENCIES.md` (requires simplification for this architecture).
