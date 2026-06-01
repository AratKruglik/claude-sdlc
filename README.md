# SDLC Marketplace for Claude Code

Multi-stack AI-assisted SDLC pipelines built on the **Stack Provider Pattern**: a single core orchestrator runs the pipeline, framework plugins register themselves via declarative `stack.md` profiles. No core overrides, no slot registries, no copy-paste between stacks.

**v0.1.0** — 10 plugins: 1 core + 1 shared lib + 7 JS/TS stacks + Laravel. Cost-optimized: model tiering + `effort` per-subagent.

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

### Stack Priority Table

| Priority | Plugin | Aspects | Detect |
|---|---|---|---|
| 0 | `vanilla` (sdlc) | — | `*` (always matches) |
| 100 | `nodejs-plugin` | backend | `package.json` + express/fastify/koa/... |
| 100 | `laravel-plugin` | backend, database | `composer.json` + `laravel/framework` |
| 150 | `react-plugin` | frontend | `package.json` + `react` (without `next`, `react-native`) |
| 150 | `vue-plugin` | frontend | `package.json` + `vue` |
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
| `node-architect` | nodejs | `sonnet` | `medium` | Express/Fastify — implementation driven by clear Node.js idioms |
| `nest-architect` | nestjs | `sonnet` | `medium` | Convention skills carry per-domain depth |
| `nextjs-architect` | nextjs | `sonnet` | `medium` | RSC/Client patterns well-defined by spec and convention skills |
| `react-architect` | react | `sonnet` | `medium` | React conventions and state/routing skills |
| `vue-architect` | vue | `sonnet` | `medium` | Vue 3/2 detection + convention skills |
| `angular-architect` | angular | `sonnet` | `medium` | Angular standalone/NgModule, signals, NgRx |
| `rn-architect` | react-native | `sonnet` | `medium` | Expo/bare + iOS/Android axes |

> `effort: high` on Opus is the most expensive combination. That's why only 2 leverage agents use it (BA and Security) — where reasoning quality directly impacts every downstream phase.

### Estimated cost for a medium feature

| Phase | Agent | Cost |
|---|---|---|
| BA | opus/high | ~$0.25 |
| Dev | sonnet/medium | ~$0.60 |
| QA | sonnet/medium (≤3 attempts) | ~$0.30 |
| Security | opus/high | ~$0.25 |
| Docs | haiku/low | ~$0.07 |
| **Total** | | **~$1.47** |

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
| `nodejs-plugin` | Stack provider | Express / Fastify / Koa / plain Node.js |
| `nestjs-plugin` | Stack provider | NestJS + TypeORM/Prisma/Mongoose |
| `nextjs-plugin` | Stack provider | Next.js App Router (full-stack) |
| `react-plugin` | Stack provider | React SPA (Vite/Webpack) |
| `vue-plugin` | Stack provider | Vue 3 SPA |
| `angular-plugin` | Stack provider | Angular 18-21 |
| `react-native-plugin` | Stack provider | React Native / Expo |
| `laravel-plugin` | Stack provider | Laravel + Inertia + Vue |

### Optional external dependencies

| Plugin | Source | Role |
|---|---|---|
| `superpowers` | `obra/superpowers` | Adds brainstorming to BA, TDD to QA, verification-before-completion to architects. Pipeline degrades gracefully without it. |
| `security-guidance` | `anthropics/claude-plugins-official` | Hooks-based in-session security review: per-edit pattern match, end-of-turn diff review. The OWASP security phase runs fully without it. |

---

## Stack Composition Examples

| Project | Profile | Development dispatch |
|---|---|---|
| Laravel + Vue SPA (Inertia) | laravel (100) | laravel-architect (backend) + artisan-specialist (db) |
| Express + React | nodejs (100) + react (150) | node-architect (backend) + react-architect (frontend) |
| NestJS + Angular | nestjs (200) + angular (200) | nest-architect (backend) + angular-architect (frontend) |
| Next.js (full-stack) | nextjs (250) | nextjs-architect (owns backend + frontend) |
| Expo mobile | react-native (300) | rn-architect (frontend) |
| Vanilla Node.js | nodejs (100) | node-architect |
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
  all:
    - file_exists: manage.py
    - file_contains:
        path: requirements.txt
        pattern: "django"
---

## Agents per phase
- business_analysis: business-analyst
- development:
    backend: django-architect
- qa: qa-engineer
- security: security-analyst
- documentation: document-writer

## Convention skills
- django-plugin:django-conventions
- django-plugin:orm-patterns
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
