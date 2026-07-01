# SDLC Marketplace for Claude Code

Multi-stack AI-assisted SDLC pipelines built on the **Stack Provider Pattern**: a single core orchestrator runs the pipeline, framework plugins register themselves via declarative `stack.md` profiles. No core overrides, no slot registries, no copy-paste between stacks.

**v1.0.3** — 26 plugins: 1 core + 5 shared libs + 7 JS/TS stacks + 5 PHP/Laravel/Symfony stacks + 3 Java/.NET stacks + **5 Python stacks (new)**. Cost-optimized: model tiering + `effort` per-subagent. Dynamic workflow recipes + guaranteed per-agent model enforcement.

---

## Quickstart

```bash
# 1. Add the marketplace
/plugin marketplace add AratKruglik/claude-sdlc

# 2. Install the stack plugin you need (sdlc core is installed automatically as a dependency)
/plugin install laravel-plugin@sdlc-marketplace
# or for JS/TS projects:
/plugin install nodejs-plugin@sdlc-marketplace   # Express/Fastify/Koa
/plugin install nestjs-plugin@sdlc-marketplace   # NestJS
/plugin install nextjs-plugin@sdlc-marketplace   # Next.js (full-stack)
/plugin install react-plugin@sdlc-marketplace    # React SPA
/plugin install vue-plugin@sdlc-marketplace      # Vue 3 SPA
/plugin install angular-plugin@sdlc-marketplace  # Angular 18-21
/plugin install react-native-plugin@sdlc-marketplace  # React Native / Expo
# or for Python projects:
/plugin install django-plugin@sdlc-marketplace   # Django + DRF
/plugin install fastapi-plugin@sdlc-marketplace  # FastAPI + SQLAlchemy 2.0
/plugin install flask-plugin@sdlc-marketplace    # Flask + Flask-Migrate
/plugin install python-plugin@sdlc-marketplace   # Plain Python (CLI/library/scripts)

# 3. Verify
/sdlc:doctor
/sdlc:list-stacks

# 4. Run
/sdlc:start "Add subscription billing with Stripe"
```

---

## How It Works: Stack Provider Pattern

```
┌─────────────────────────────────────────────────────────────┐
│                    sdlc (core)                               │
│  ┌──────────────────────────────────────────────────────┐  │
│  │  pipeline-orchestrator (skill) — NEVER CHANGES        │  │
│  │                                                       │  │
│  │  Phase 1: BA          → core's business-analyst       │  │
│  │  Phase 2: Dev         → ⚡ DISPATCH to stack provider │  │
│  │  Phase X: extra       → ⚡ stack-specific phases      │  │
│  │  Phase N-2: QA        → core's qa-engineer            │  │
│  │  Phase N-1: Security  → core's security-analyst       │  │
│  │  Phase N: Docs/PR     → core's document-writer        │  │
│  └──────────────────────────────────────────────────────┘  │
│                            ▲                                │
│                            │ reads stack.md profiles        │
└────────────────────────────┼────────────────────────────────┘
                             │
    ┌────────────────────────┼───────────────────────────┐
    │            │           │             │             │
┌───▼───┐  ┌────▼────┐ ┌────▼────┐  ┌────▼────┐  ┌────▼────┐
│laravel│  │ nodejs  │ │  nestjs │  │ nextjs  │  │  react  │
│plugin │  │ plugin  │ │  plugin │  │ plugin  │  │  plugin │
│stack.md│ │ stack.md│ │stack.md │  │stack.md │  │stack.md │
└───────┘  └─────────┘ └─────────┘  └─────────┘  └─────────┘
```

**Key principles:**

1. **Core never changes.** Pipeline logic lives exclusively in `pipeline-orchestrator/SKILL.md`.
2. **Plugins register themselves** via `stack.md` frontmatter — they declare auto-detection rules, priority, agents per phase, and convention skills.
3. **Per-aspect dispatch.** A project can have multiple aspects (backend + frontend + database). Each aspect gets its own specialist.
4. **Priority wins.** When multiple profiles match, the highest priority takes over.

### How Stack Selection Works

When `/sdlc:start` runs, the orchestrator needs to decide which agent handles development. The priority system is how it picks.

Each plugin has a `stack.md` file where it describes itself: *"I handle projects that have X, and my priority is Y."* The orchestrator scans all installed plugins, runs their detection rules against the current project, and picks the highest-priority match.

**Step by step:**

1. Scan `~/.claude/plugins/cache/**/stack.md` — collect all registered profiles.
2. Each profile checks its `detect` rules: is there a `package.json`? Does it contain `react`? Is there a `manage.py`? And so on.
3. From those that matched — the profile with the **highest priority number wins**.

**Example — Laravel + React (Inertia.js) project:**

| Plugin | Priority | Matched? |
|---|---|---|
| `vanilla` (sdlc) | 0 | ✅ always |
| `laravel-plugin` | 100 | ✅ `composer.json` + laravel |
| `react-plugin` | 150 | ✅ `package.json` + react |
| `inertia-react-plugin` | 175 | ✅ `package.json` + `@inertiajs/react` |

Result: **backend** → `laravel-architect`, **frontend** → `inertia-react-architect` (beats plain react at 175 vs 150).

**Why numbers, not "first match"?**

Some technologies are supersets of others. Next.js is React + a server. NestJS is Node.js + a DI framework. When multiple plugins recognize the same project, the **more specialized one should win** — not whichever was installed first. The numbers encode that specialization:

```
0   → vanilla fallback (always matches, always loses)
100 → base stacks (laravel, django, java, python...)
150 → more specific (spring-boot, react SPA, vue...)
175 → super-stacks (inertia = laravel + react combined)
200 → even more specific (nestjs, angular...)
250 → full-stack (nextjs = backend + frontend in one)
300 → mobile (react-native — its own ecosystem)
```

**Aspects** let one project run multiple specialist agents in parallel. `laravel-plugin` covers `backend` + `database` aspects; `inertia-react-plugin` covers `frontend`. So a Laravel + Inertia project gets three agents — `laravel-architect`, `artisan-specialist`, and `inertia-react-architect` — each focused on its own slice, dispatched in canonical order: `database → backend → frontend`.

### Stack Priority Table

| Priority | Plugin | Aspects | Detect |
|---|---|---|---|
| 0 | `vanilla` (sdlc) | — | `*` (always matches) |
| 100 | `nodejs-plugin` | backend | `package.json` + express/fastify/koa/... |
| 100 | `laravel-plugin` | backend, database | `composer.json` + `laravel/framework` |
| 100 | `symfony-plugin` | backend, database | `composer.json` + `symfony/framework-bundle` |
| 100 | `java-plugin` | backend | `pom.xml` or `build.gradle` or `build.gradle.kts` |
| 100 | `aspnet-core-plugin` | backend, database | `appsettings.json` |
| 100 | `python-plugin` | backend | `pyproject.toml` or `requirements.txt` or `setup.py` or `Pipfile` |
| 150 | `react-plugin` | frontend | `package.json` + `react` (without `next`, `react-native`) |
| 150 | `vue-plugin` | frontend | `package.json` + `vue` |
| 150 | `spring-boot-plugin` | backend | any build file + `spring-boot` marker |
| 150 | `django-plugin` | backend, database | `manage.py` or Django in `pyproject.toml`/`requirements.txt` |
| 150 | `fastapi-plugin` | backend, database | `fastapi` in `pyproject.toml`/`requirements.txt` |
| 150 | `flask-plugin` | backend, database | `Flask` in `pyproject.toml`/`requirements.txt` |
| 175 | `inertia-vue-plugin` | frontend | `package.json` + `@inertiajs/vue3` |
| 175 | `inertia-react-plugin` | frontend | `package.json` + `@inertiajs/react` |
| 200 | `nestjs-plugin` | backend, database | `package.json` + `@nestjs/core` |
| 200 | `angular-plugin` | frontend | `package.json` + `@angular/core` |
| 250 | `nextjs-plugin` | backend, frontend | `package.json` + `next` |
| 300 | `react-native-plugin` | frontend | `package.json` + `react-native` |

---

## Pipeline Phases

### Standard 5-phase pipeline

```
Phase 1: BA → business-analyst (opus/high)
          ↓ output: docs/plans/{slug}/01-business-analysis.md
Phase 2: Dev → [stack agent] (sonnet/medium)
          ↓ output: docs/plans/{slug}/02-development.md
Phase 3: QA → qa-engineer (sonnet/medium, max 3 attempts)
          ↓ output: docs/plans/{slug}/03-qa.md
Phase 4: Security → security-analyst (opus/high)
          ↓ output: docs/plans/{slug}/04-security.md
Phase 5: Docs → document-writer (haiku/low)
          ↓ output: PR on GitHub
```

### Example: Laravel (6 phases)

```
Phase 1: BA → business-analyst
Phase 2: Dev/backend  → laravel-architect    (aspect=backend)
Phase 3: Dev/database → artisan-specialist   (extra phase after backend)
Phase 4: QA → qa-engineer
Phase 5: Security → security-analyst
Phase 6: Docs → document-writer
```

### Per-aspect dispatch (multi-framework projects)

For a project with a Node.js backend and a React frontend:

- Phase 2/backend → `node-architect`
- Phase 2/frontend → `react-architect` (separate run)

Aspects are dispatched in canonical order: `database → backend → frontend → testing`.

---

## Commands

| Command | Purpose |
|---|---|
| `/sdlc:start "feature"` | Run the full 5-phase pipeline |
| `/sdlc:batch "task1" "task2"` | Run pipelines in parallel for multiple tasks (isolated worktrees) |
| `/sdlc:list-stacks` | Show detected stack profiles and their priorities |
| `/sdlc:doctor` | Preflight check: dependency check, stack detection, cost baseline |
| `/sdlc:security-init` | Materialize security-patterns.yaml for the security-guidance plugin |

---

## Dynamic Workflow Recipes

A **workflow recipe** is a YAML file that declares which pipeline phases to run. Instead of always running all 5 phases, the orchestrator selects the right recipe automatically — or you can pick one explicitly.

### Built-in recipes

| Recipe | Phases | Auto-selects when |
|---|---|---|
| `default` | BA → Dev → QA → Security → Docs | any task |
| `bugfix` | Dev → QA → Security → Docs | arguments contain `fix`, `bug`, `issue`; ≤500 LOC |
| `hotfix` | Dev → QA → Security → Docs | arguments contain `hotfix`, `urgent`, `emergency`; ≤200 LOC; $0.60 cost cap |
| `refactor` | Dev → QA → Security → Docs | arguments contain `refactor`, `cleanup`, `extract` |
| `docs-only` | Docs | arguments contain `docs`, `readme`, `changelog`; $0.10 cost cap |

### Using a specific recipe

```bash
/sdlc:start --workflow=hotfix "Fix null pointer in payment handler"
/sdlc:start --workflow=docs-only "Update README for new auth flow"
```

### Auto-selection

If no `--workflow` flag is given, the orchestrator checks each recipe's `match` rules against your `$ARGUMENTS` in priority order. First match wins; `default` always matches as the fallback.

### Custom recipes

Place a YAML file at `~/.claude/plugins/cache/sdlc/workflows/my-recipe.yaml`:

```yaml
name: my-recipe
description: Internal audit workflow — skip BA, security required.
phases:
  - development
  - qa
  - security
caps:
  max_total_cost_usd: 1.00
```

```bash
/sdlc:start --workflow=my-recipe "Audit user permissions module"
```

Recipe files are validated against `schemas/workflow.schema.json` on load. Invalid recipes halt with an error listing each violation.

---

## Model Enforcement

Every agent in the SDLC pipeline declares its `model:` tier in frontmatter. The pipeline guarantees that tier is actually used — regardless of the session-level default model.

**Two enforcement layers:**

1. **Orchestrator (Layer 1)** — Step 3b-3 in the pipeline explicitly reads the agent's `.md` frontmatter, resolves the tier to a full model ID, and passes it in the `Agent()` dispatch call.

2. **PreToolUse hook (Layer 2)** — `plugins/sdlc/hooks/enforce-agent-model.sh` intercepts every `Agent` tool call at the harness level. It reads the agent's declared `model:`, compares it with the requested model, and corrects it via `updatedInput` if they differ. This fires even if the orchestrator misses the step.

The hook is registered in `plugins/sdlc/hooks/hooks.json` and activates automatically when the plugin is installed via the marketplace — no manual `settings.json` changes needed.

**Tier → model ID mapping:**

| Tier | Model ID |
|---|---|
| `opus` | `claude-opus-4-8` |
| `sonnet` | `claude-sonnet-5` |
| `haiku` | `claude-haiku-4-5-20251001` |

---

## Cost Optimization: model + effort

### Why `model` + `effort` instead of `temperature`

Claude Code subagent frontmatter supports:

- `model` — `opus` / `sonnet` / `haiku` / full model ID / `inherit`
- `effort` — `low` / `medium` / `high` / `xhigh` / `max` — **overrides the session-level reasoning budget**

`temperature` is **not configurable per-subagent** in Claude Code. We control cost exclusively through `model` + `effort`.

### model+effort table for all agents

| Agent | Plugin | model | effort | Rationale |
|---|---|---|---|---|
| `business-analyst` | sdlc | `opus` | `high` | Requirement errors cascade through 5 phases; small token volume, maximum leverage |
| `security-analyst` | sdlc | `opus` | `high` | Non-obvious vulnerabilities (TOCTOU, JWT confusion, SSRF) require deep reasoning |
| `developer` | sdlc | `sonnet` | `medium` | Vanilla fallback — execution against a clear spec |
| `qa-engineer` | sdlc | `sonnet` | `medium` | Tests against clear criteria; hard 3-attempt cap keeps cost in check |
| `document-writer` | sdlc | `haiku` | `low` | Structured output from known facts; ~10× cheaper than Opus |
| `laravel-architect` | laravel | `sonnet` | `medium` | Laravel idioms + Inertia/Vue |
| `artisan-specialist` | laravel | `sonnet` | `low` | Mechanical DB work: column types, indexes, factories |
| `symfony-architect` | symfony | `sonnet` | `medium` | Attribute routing, controllers-as-services, DI, Voters, Serializer, Messenger, Twig |
| `doctrine-specialist` | symfony | `sonnet` | `low` | Doctrine entity mappings, generated migrations, fixtures, schema verification |
| `node-architect` | nodejs | `sonnet` | `medium` | Express/Fastify — implementation driven by clear Node.js idioms |
| `nest-architect` | nestjs | `sonnet` | `medium` | Convention skills carry per-domain depth |
| `nextjs-architect` | nextjs | `sonnet` | `medium` | RSC/Client patterns well-defined by spec and convention skills |
| `react-architect` | react | `sonnet` | `medium` | React conventions and state/routing skills |
| `vue-architect` | vue | `sonnet` | `medium` | Vue 3/2 detection + convention skills |
| `angular-architect` | angular | `sonnet` | `medium` | Angular standalone/NgModule, signals, NgRx |
| `inertia-vue-architect` | inertia-vue | `sonnet` | `medium` | Inertia.js + Vue 3 server-driven pages, no client-side router |
| `inertia-react-architect` | inertia-react | `sonnet` | `medium` | Inertia.js + React server-driven pages, no React Router |
| `rn-architect` | react-native | `sonnet` | `medium` | Expo/bare + iOS/Android axes |
| `java-architect` | java | `sonnet` | `medium` | Plain Java — records, domain objects, build tooling |
| `spring-boot-architect` | spring-boot | `sonnet` | `medium` | Spring Boot — controllers, JPA, migrations, Spring Security |
| `aspnet-core-architect` | aspnet-core | `sonnet` | `medium` | Minimal API / MVC, DTOs, FluentValidation, DI, authorization, HTTPS/HSTS |
| `efcore-specialist` | aspnet-core | `sonnet` | `low` | EF Core Fluent API config, column types, indexes, migration generation and verification |

> `effort: high` on Opus is the most expensive combination. That's why only 2 leverage agents use it (BA and Security) — where reasoning quality directly impacts every downstream phase.

### Estimated cost for a medium feature

Assumes a medium feature (~445K total input tokens across the pipeline, per [Requirements](#requirements)), split roughly by phase workload below. Sonnet 5 pricing includes an introductory discount through 2026-08-31 ($2/$10 per MTok in/out vs. the $3/$15 standard rate) — both are shown since most runs during the discount window will land closer to the lower figure.

| Phase | Agent | Model | Est. input / output tokens | Cost (standard) | Cost (intro, thru 2026-08-31) |
|---|---|---|---|---|---|
| BA | business-analyst | opus/high | 40K / 3K | ~$0.28 | ~$0.28 |
| Dev | stack architect | sonnet/medium | 250K / 8K | ~$0.87 | ~$0.58 |
| QA | qa-engineer | sonnet/medium (≤3 attempts) | 100K / 5K | ~$0.38 | ~$0.25 |
| Security | security-analyst | opus/high | 40K / 3K | ~$0.28 | ~$0.28 |
| Docs | document-writer | haiku/low | 15K / 2K | ~$0.03 | ~$0.03 |
| **Total** | | | **445K / 21K** | **~$1.84** | **~$1.42** |

Opus and Haiku pricing is unchanged from prior model generations, so only the Sonnet-tier phases (Dev, QA) shift with the Sonnet 5 introductory rate. Actual cost varies with codebase size, diff scope, and QA retry count — treat this as an order-of-magnitude estimate, not a quote.

### Additional cost levers

- **Skip-rules:** typo-fix, whitespace-only, config-only, lightweight-no-db — skip unnecessary phases automatically.
- **QA hard cap:** max 3 attempts to fix failing tests, then STOP.
- **Compact handoffs:** each agent returns a ≤2–3K-token summary.
- **Prompt caching:** stable system prompts (no timestamps, slugs, or dynamic content) → ~60% cache hit rate on Sonnet.

---

## Available Plugins

| Plugin | Type | Stack / Technology |
|---|---|---|
| `sdlc` | Core | Pipeline orchestrator + 5 default agents |
| `js-foundation` | Shared lib | TypeScript + npm patterns (no stack profile) |
| `php-foundation` | Shared lib | PHP 8 conventions + Composer + PHPUnit/Pest (no stack profile) |
| `java-foundation` | Shared lib | Java conventions + Maven/Gradle + JVM testing (no stack profile) |
| `csharp-foundation` | Shared lib | C# conventions + dotnet CLI/NuGet + xUnit/Moq/FluentAssertions (no stack profile) |
| `nodejs-plugin` | Stack provider | Express / Fastify / Koa / plain Node.js |
| `nestjs-plugin` | Stack provider | NestJS + TypeORM/Prisma/Mongoose |
| `nextjs-plugin` | Stack provider | Next.js App Router (full-stack) |
| `react-plugin` | Stack provider | React SPA (Vite/Webpack) |
| `vue-plugin` | Stack provider | Vue 3 SPA |
| `angular-plugin` | Stack provider | Angular 18-21 |
| `react-native-plugin` | Stack provider | React Native / Expo |
| `inertia-vue-plugin` | Stack provider | Inertia.js + Vue 3 (Laravel backend) |
| `inertia-react-plugin` | Stack provider | Inertia.js + React (Laravel backend) |
| `laravel-plugin` | Stack provider | Laravel + Eloquent + Artisan + Inertia |
| `symfony-plugin` | Stack provider | Symfony + Doctrine ORM + Twig / API Platform |
| `java-plugin` | Stack provider | Plain Java (Maven/Gradle, no web framework) |
| `spring-boot-plugin` | Stack provider | Spring Boot REST + Spring Data JPA + Flyway/Liquibase |
| `aspnet-core-plugin` | Stack provider | ASP.NET Core Web API + EF Core (.NET 6+) |

### Optional external dependencies

| Plugin | Source | Role |
|---|---|---|
| `superpowers` | `obra/superpowers` | Adds brainstorming to BA, TDD to QA, verification-before-completion to architects. Pipeline degrades gracefully without it. |
| `security-guidance` | `anthropics/claude-plugins-official` | Hooks-based in-session security review: per-edit pattern match, end-of-turn diff review. The OWASP security phase runs fully without it. |

---

## Stack Composition Examples

| Project | Profile | Development dispatch |
|---|---|---|
| Laravel + Vue SPA (Inertia) | laravel (100) + inertia-vue (175) | laravel-architect (backend) + artisan-specialist (db) + inertia-vue-architect (frontend) |
| Laravel + React SPA (Inertia) | laravel (100) + inertia-react (175) | laravel-architect (backend) + artisan-specialist (db) + inertia-react-architect (frontend) |
| Symfony + Doctrine | symfony (100) | symfony-architect (backend) + doctrine-specialist (db) |
| Express + React | nodejs (100) + react (150) | node-architect (backend) + react-architect (frontend) |
| NestJS + Angular | nestjs (200) + angular (200) | nest-architect (backend) + angular-architect (frontend) |
| Next.js (full-stack) | nextjs (250) | nextjs-architect (owns backend + frontend) |
| Expo mobile | react-native (300) | rn-architect (frontend) |
| Vanilla Node.js | nodejs (100) | node-architect |
| Plain Java (no framework) | java (100) | java-architect |
| Spring Boot REST API | spring-boot (150) | spring-boot-architect |
| ASP.NET Core Web API + EF Core | aspnet-core (100) | aspnet-core-architect (backend) + efcore-specialist (db) |
| ASP.NET Core + React SPA | aspnet-core (100) + react (150) | aspnet-core-architect (backend) + efcore-specialist (db) + react-architect (frontend) |
| Unknown stack | vanilla (0) | developer (fallback) |

---

## Local Overrides

A `.claude/sdlc.local.yaml` file at the project root (not inside the plugin) lets you adapt the pipeline without modifying any plugin:

```yaml
post_pipeline_checks:
  - "composer test"
  - "php artisan route:list --json"

phase_command_overrides:
  qa: "php artisan test --coverage --min=80"

convention_skills_extra:
  - "local:custom-coding-standards"

skip_phases:
  - security  # for internal hotfix branches

extra_phase_prompts:
  development: "Follow our internal-styleguide.md"
```

---

## Adding a New Stack Plugin

Contract for a new framework provider:

```
plugins/your-framework-plugin/
├── .claude-plugin/
│   └── plugin.json          # { "name": "...", "dependencies": ["sdlc"] }
├── stack.md                 # YAML frontmatter: stack, priority, aspects, detect
├── agents/
│   └── your-architect.md    # frontmatter: name, model, effort, color, tools
├── skills/
│   └── your-conventions/
│       └── SKILL.md
└── README.md
```

### `stack.md` example

```yaml
---
stack: django
priority: 150
aspects: [backend, database]
detect:
  any:
    - file_exists: manage.py
    - file_contains:
        path: pyproject.toml
        pattern: "[Dd]jango"
    - file_contains:
        path: requirements.txt
        pattern: "[Dd]jango"
---
# Django Stack Profile

## Agents per phase
# business_analysis: business-analyst
# development.backend: django-architect
# database: django-migrations-specialist
# qa: qa-engineer / security: security-analyst / documentation: document-writer

## Convention skills to apply
# python-foundation:python-conventions
# python-foundation:python-tooling
# python-foundation:pytest-testing
# django-plugin:django-conventions
# django-plugin:django-orm-patterns
```

### Schema validation

```bash
# Validate plugin.json
npx check-jsonschema --schemafile schemas/plugin.schema.json .claude-plugin/plugin.json

# Validate stack.md frontmatter
npx check-jsonschema --schemafile schemas/stack.schema.json <(yq '.frontmatter' stack.md)
```

---

## Installation (step-by-step)

### 1. Add the marketplace

```bash
/plugin marketplace add AratKruglik/claude-sdlc
# or for local development:
/plugin marketplace add /path/to/claude-sdlc
```

### 2. Install core + required plugins

```bash
# Core is installed automatically as a dependency
/plugin install nodejs-plugin@sdlc-marketplace     # Node.js backend
/plugin install js-foundation@sdlc-marketplace     # required for JS/TS plugins
```

### 3. Optional external dependencies

```bash
/plugin marketplace add obra/superpowers
/plugin install superpowers@superpowers-marketplace

/plugin marketplace add anthropics/claude-plugins-official
/plugin install security-guidance@claude-plugins-official
```

### 4. Verify

```bash
/sdlc:doctor
# → Stack profiles detected: vanilla(0), nodejs(100), react(150), ...
# → superpowers: ✅ installed
# → security-guidance: ⚠️ not found (pipeline will run in degraded mode)

/sdlc:list-stacks
# → Shows all matched stack profiles for current project
```

### 5. Run

```bash
/sdlc:start "Add user authentication with JWT"
# → Auto-detects stack, runs 5 phases, creates PR
```

---

## Requirements

- Claude Code (latest)
- API Tier 2+ or Claude Max — a medium feature uses ~445K input tokens; Pro plan rate limits will throttle the pipeline.
- A Git repository for `document-writer` (PR creation).

## License

MIT — see [`LICENSE`](./LICENSE).
