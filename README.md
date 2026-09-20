# SDLC Marketplace for Claude Code

Multi-stack AI-assisted SDLC pipelines built on the **Stack Provider Pattern**: a single core orchestrator runs the pipeline, framework plugins register themselves via declarative `stack.md` profiles. No core overrides, no slot registries, no copy-paste between stacks.

**v1.5.0** — 27 marketplace entries: 24 local (1 core + 5 shared libs + 7 JS/TS stacks + 4 PHP/Laravel/Symfony stacks + 3 Java/.NET stacks + 4 Python stacks) plus 3 optional external. **Git-flow aware:** the pipeline detects your branching model *and your existing naming convention*, classifies the task type, proposes a branch, and targets the PR at the right base — see [Git Flow Awareness](#git-flow-awareness). Workflow auto-selection is now implemented. Cost-optimized: model tiering + `effort` per-subagent, **two-tier development phase** (Opus plans, Sonnet implements), enforced workflow cost caps, file-scoped format hooks, shared architect conventions (~1,600 lines of boilerplate deduped), per-aspect QA fan-out on full-stack runs. See [MODEL-ROUTING.md](MODEL-ROUTING.md) for the routing audit behind the cost model.

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

# 3. Install optional plugins
/plugin marketplace add mattpocock/skills
/plugin install mattpocock-skills@skills # Enhances BA phase with interactive grilling

# 4. Verify
/sdlc:doctor
/sdlc:list-stacks

# 4. Run
/sdlc:start "Add subscription billing with Stripe"
```

> **Execution model:** `/sdlc:start` runs synchronously in your current Claude Code session, not as a detached background job. You stay engaged through dependency/stack-detection checks and phase boundaries — including an interactive approve/request-changes/abort gate before the development phase writes any code. The final phase autonomously opens a Pull Request via `gh pr create`. See [Pipeline Phases](#pipeline-phases) below.

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

Before Phase 1, the orchestrator detects the stack profile and the [git branching model](#git-flow-awareness), classifies the task type, and asks you to confirm the branch.

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
| `/sdlc:doctor` | Preflight check: dependencies, stack detection, git branching model, cost baseline |
| `/sdlc:security-init` | Materialize security-patterns.yaml for the security-guidance plugin |

### `/sdlc:start` flags

| Flag | Effect |
|---|---|
| `--stack=NAME` | Force a stack profile instead of auto-detecting |
| `--type=NAME` | Force the task type (`feature`, `fix`, `bugfix`, `hotfix`, `release`, `refactor`, `docs`, `chore`) instead of classifying it from the description |
| `--workflow=NAME` | Force a workflow recipe instead of auto-selecting |
| `--redetect-git-flow` | Ignore the cached branching-model detection and detect again |
| `--force-preflight` | Ignore the cached dependency preflight |

---

## Dynamic Workflow Recipes

A **workflow recipe** is a YAML file that declares which pipeline phases to run. Instead of always running all 5 phases, the orchestrator selects the right recipe automatically — or you can pick one explicitly.

### Built-in recipes

| Recipe | Phases | Auto-selects when |
|---|---|---|
| `default` | BA → Dev → QA → Security → Docs | any task |
| `bugfix` | Dev → QA → Security → Docs | task type is `fix` or `bugfix`; ≤500 LOC |
| `hotfix` | Dev → QA → Security → Docs | task type is `hotfix`; ≤200 LOC; $2.50 cost cap |
| `refactor` | Dev → QA → Security → Docs | task type is `refactor` |
| `docs-only` | Docs | task type is `docs`; config-only diff; $0.20 cost cap |

Cost caps are **runaway guards, not budgets** — each sits roughly 2× above what a normal run of
that recipe costs, so it fires on pathology (a QA retry storm, an oversized diff) and never on
healthy work. The authoritative values live in the recipe YAML files; this table follows them.

### Using a specific recipe

```bash
/sdlc:start --workflow=hotfix "Fix null pointer in payment handler"
/sdlc:start --workflow=docs-only "Update README for new auth flow"
```

### Auto-selection

With no `--workflow` flag, the orchestrator resolves the recipe in this order — first rule that yields an existing recipe wins:

1. **`--workflow=NAME`** — an explicit choice is never second-guessed.
2. **`active_workflow`** in `.claude/sdlc.local.yaml`.
3. **Task type** — the same classification that picks your branch prefix (see [Git Flow Awareness](#git-flow-awareness)). `fix`/`bugfix` → `bugfix`, `hotfix` → `hotfix`, `refactor` → `refactor`, `docs` → `docs-only`, everything else → `default`. The mapped recipe is used only if its own `match` constraints also hold, so a 600-LOC change described as a "fix" falls through instead of getting `bugfix`'s trimmed pipeline.
4. **`match` scan** over recipes no task type maps to, in alphabetical order by name.
5. **`default`.**

The deciding rule is printed with the resolved plan and recorded in telemetry as `workflow_selection_reason`, so a surprising phase list is always traceable to one rule.

One subtlety worth knowing: a `loc_touched_max` constraint is treated as **unsatisfied** on a branch with no commits yet. An empty diff measures 0 LOC, which would otherwise satisfy every ceiling in the recipe set and hand a brand-new feature the `hotfix` pipeline. An unmeasurable diff is unknown, not small.

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

## Git Flow Awareness

Before any phase runs, the pipeline works out how your project branches, what kind of task you asked for, and which branch the work belongs on. It then asks before touching anything.

```text
🌿 Git flow
   Model:       git-flow (confidence: high — topology:develop-branch, config:gitflow.*)
   Convention:  {prefix}/{TICKET}-{kebab-slug}  (learned from 23 branches)
   Task type:   hotfix (keyword match)
   Current:     main (base branch — a task branch is required)
   Proposed:    hotfix/PAY-412-null-pointer-in-handler
   Branch from: origin/main
   PR base:     main
   ↩️  Requires back-merge to develop after the PR merges
```

Your choices: **create** / **continue on the current branch** / **rename** / **change type** / **abort**.

### What it detects

| Model | Detected when | Where branches go |
|---|---|---|
| `git-flow` | a `develop`/`dev` branch exists, or `git flow init` left `gitflow.*` config | per the type matrix below |
| `github-flow` | no develop branch — one long-lived branch | everything branches from and targets the default branch |
| `custom` | you declared it in `sdlc.local.yaml` | per your own `type_policy` |

Detection sources, in order of authority:

1. **An explicit `git:` block** in `.claude/sdlc.local.yaml` — a decision, not a guess. Short-circuits everything below.
2. **Your documented conventions** — `CLAUDE.md`, `.claude/rules/*.md`, `CONTRIBUTING.md`, `.cursorrules`, PR templates. A written rule outranks branch history; a rule that contradicts the topology is surfaced, not silently resolved.
3. **Your branch history** — `plugins/sdlc/scripts/detect-git-flow.sh` reads the repo's own branches and learns the separator (`/` vs `-`), the word separator (`-` vs `_`), any ticket-key pattern, and the prefix vocabulary you actually use.

**It follows your conventions rather than imposing ours.** Three consequences worth knowing:

- A prefix seen only **once** is discarded as noise — a typo in branch history must never become a learned convention.
- If your repo has never used prefixes, you get a bare slug, not an invented `feature/`.
- If your repo says `fix/` where the table below says `bugfix/`, you get `fix/`.

### Task type → branch and merge target

The task type is classified from your description with a deterministic keyword table and a fixed precedence order (`hotfix > release > bugfix > fix > refactor > docs > chore > feature`); `--type=NAME` overrides it. Under `git-flow`:

| Task type | Branch | From | PR base |
|---|---|---|---|
| `feature` | `feature/…` | develop | develop |
| `fix` | `fix/…` | develop | develop |
| `bugfix` | `bugfix/…` | active `release/*` else main | same |
| `hotfix` | `hotfix/…` | active `release/*` else main | same |
| `release` | `release/…` | develop | main |
| `refactor` / `docs` / `chore` | as observed | develop | develop |

`fix` merges to `develop`; `bugfix` and `hotfix` do not. That asymmetry is the point of the model — `fix` is ordinary corrective work riding the next release, while `bugfix` and `hotfix` target something already shipped. For `hotfix` and `release`, the outstanding back-merge into `develop` is written into the PR body and repeated in the final summary; **opening that second PR is not automated.**

### Configuration

Everything is overridable in `.claude/sdlc.local.yaml`. Only `model` is required; absent keys fall through to detection.

```yaml
git:
  model: git-flow
  develop_branch: develop
  auto_create_branch: true       # false → never create a branch, only report
  naming:
    word_separator: "-"
    ticket_pattern: "^[A-Z][A-Z0-9]{1,9}-[0-9]+$"
    ticket_position: after-prefix
    max_length: 60
  type_policy:                   # partial override — unlisted types keep the defaults above
    bugfix: { prefix: bugfix, from: main, pr_base: main }
```

The detection result is cached in `.claude/.sdlc-git-flow.json` (excluded from version control automatically) and trusted for 30 days once you have confirmed it. `--redetect-git-flow` re-detects; `/sdlc:doctor` always detects fresh and flags a cache that disagrees with reality.

### In headless mode

`SDLC_NONINTERACTIVE=true` has no user to ask, so the gate does not prompt: the detected model and task type are used as-is, a branch is created when the current branch is a base branch, and one summary line goes to stderr. Low-confidence detection falls back to github-flow off the default branch. Set `auto_create_branch: false` to keep CI on whatever branch it checked out.

### Known limitations

- **`/sdlc:batch`** worktree branches are named by the `Agent` tool, so they do not follow the learned convention. Their PR base is still correct — it derives from the task type, not the branch name.
- **Back-merges** are reported, never opened.
- **Issue-tracker metadata** (a Jira issue's type) is deliberately not a classification signal, so typing stays reproducible from the description alone.

Full algorithm: [`plugins/sdlc/references/GIT-FLOW.md`](plugins/sdlc/references/GIT-FLOW.md).

---

## Model Enforcement

Every agent in the SDLC pipeline declares its `model:` tier in frontmatter. The pipeline enforces that tier on dispatch, so a session running on an expensive default model does not drag every phase up with it.

**Two enforcement layers:**

1. **Orchestrator (Layer 1)** — Step 3b-3 in the pipeline explicitly reads the agent's `.md` frontmatter and passes the tier alias in the `Agent()` dispatch call.

2. **PreToolUse hook (Layer 2)** — `plugins/sdlc/hooks/enforce-agent-model.sh` intercepts every `Agent` tool call at the harness level. It reads the agent's declared tier, compares it with the requested model, and corrects it via `updatedInput` if they differ. This fires even if the orchestrator misses the step.

The hook is registered in `plugins/sdlc/hooks/hooks.json` and activates automatically when the plugin is installed via the marketplace — no manual `settings.json` changes needed.

**Model tiers:** both layers pass the short alias (`opus` / `sonnet` / `haiku` / `fable`) as-is — the `Agent` tool's `model` parameter accepts only these aliases, and a full pinned model ID would fail validation and silently fall back to the session model. (Agent *frontmatter* is more permissive and does accept full IDs and `inherit`; the dispatch parameter does not.) Which concrete model each alias resolves to is decided by the harness, so the marketplace never goes stale on model releases.

**Two-tier development phase:** the development phase runs a planning pass and an implementation pass either side of a human approval gate, and they resolve different tiers. The planning pass reads `model_plan:` (Opus by default), the implementation pass reads `model:` (Sonnet). The orchestrator marks the pass in the `Agent()` `description` field so the hook enforces the matching one — see `MODEL-ROUTING.md` §4.1.

---

## Stack-Detection Caching

Stack-profile detection (Step 0b in `pipeline-orchestrator/SKILL.md`) matches every installed plugin's `stack.md` against the current project — a Glob-then-Read-then-parse pass over every plugin, repeated on every `/sdlc:start` and `/sdlc:doctor` invocation.

A `SessionStart` hook — `plugins/sdlc/hooks/session-start-stack-cache.sh` — precomputes this once per session, for free, and writes the result to `~/.claude/.sdlc-stack-cache/{hash-of-repo-path}.json`. It fires on `startup`, `resume`, and `clear` (not `compact`/`fork`, where the repo hasn't changed), runs `scripts/detect-stack.sh`, and exits silently — it never prints anything, since a `SessionStart` hook fires for every session on the machine, including ones with nothing to do with this plugin.

`/sdlc:start` Step 0b reads this cache when it is fresh (< 6h old, matching the repo it detected for) and skips the full scan entirely. A recorded aspect tie in the cache still halts the gate and asks for `--stack=NAME` — the cache never silently resolves a tie the inline algorithm wouldn't. `--redetect-stack` forces a full scan. `/sdlc:doctor` always computes fresh (same "a doctor that echoes a stale cache cannot diagnose a stale cache" principle as its git-flow check) but reports the cache's age and whether it agrees.

This hook is also registered in `hooks.json` and activates automatically on install — no manual `settings.json` changes needed.

> ⚠️ **Enforcement is not absolute.** Claude Code resolves a subagent's model in the order `CLAUDE_CODE_SUBAGENT_MODEL` → per-invocation parameter → frontmatter. That environment variable overrides **both** layers above, and every phase silently runs on whatever it names. An organization `availableModels` allowlist can likewise skip a value in favour of the inherited model. Run `/sdlc:doctor` to see whether either is in play — while an override is active, none of the cost figures below apply.

---

## Cost Optimization: model + effort

### Why `model` + `effort` instead of `temperature`

Claude Code subagent frontmatter supports:

- `model` — `opus` / `sonnet` / `haiku` / `fable` / full model ID / `inherit`
- `effort` — `low` / `medium` / `high` / `xhigh` / `max` — **overrides the session-level reasoning budget**

`temperature` is **not configurable per-subagent** in Claude Code. We control cost exclusively through `model` + `effort`.

Note the asymmetry between the two levers: `model` can be overridden per dispatch (the `Agent` tool takes a `model` parameter), but `effort` cannot — it is read from frontmatter only. An agent invoked twice in one phase therefore shares one `effort` value across both invocations, which is why the development phase varies `model` between its passes but not `effort`. See `MODEL-ROUTING.md` §6.

`model_plan` is this marketplace's own optional field, not a Claude Code one — the orchestrator resolves it for the development planning pass and falls back to `model` when absent.

### model+effort table for all agents

Development-phase agents carry a second tier in `model_plan` — resolved for the planning pass only, with `model` used for implementation.

| Agent | Plugin | model | model_plan | effort | Rationale |
|---|---|---|---|---|---|
| `business-analyst` | sdlc | `opus` | — | `high` | Requirement errors cascade through every later phase; small token volume, maximum leverage |
| `security-analyst` | sdlc | `opus` | — | `xhigh` | Non-obvious vulnerabilities (TOCTOU, JWT confusion, SSRF) need deep reasoning, and a miss here is silent — no error, no failing test |
| `developer` | sdlc | `sonnet` | `opus` | `medium` | Vanilla fallback — Opus plans, Sonnet executes against the approved plan |
| `qa-engineer` | sdlc | `sonnet` | — | `medium` | Tests against clear criteria; hard 3-attempt cap keeps cost in check |
| `document-writer` | sdlc | `haiku` | — | `low` | Structured output from known facts; ~5x cheaper than Opus |
| `angular-architect` | angular | `sonnet` | `opus` | `medium` | Angular standalone/NgModule, signals, NgRx |
| `aspnet-core-architect` | aspnet-core | `sonnet` | `opus` | `medium` | Minimal API / MVC, DTOs, FluentValidation, DI, authorization, HTTPS/HSTS |
| `django-architect` | django | `sonnet` | `opus` | `medium` | Django views, DRF ViewSets/serializers, URLconf, models |
| `fastapi-architect` | fastapi | `sonnet` | `opus` | `medium` | APIRouter, Pydantic v2, Depends, async SQLAlchemy, OAuth2/JWT |
| `flask-architect` | flask | `sonnet` | `opus` | `medium` | App factory, Blueprints, Flask-Login/JWT, Marshmallow/WTForms |
| `inertia-react-architect` | inertia-react | `sonnet` | `opus` | `medium` | Inertia.js + React server-driven pages, no React Router |
| `inertia-vue-architect` | inertia-vue | `sonnet` | `opus` | `medium` | Inertia.js + Vue 3 server-driven pages, no client-side router |
| `java-architect` | java | `sonnet` | `opus` | `medium` | Plain Java — records, domain objects, build tooling |
| `laravel-architect` | laravel | `sonnet` | `opus` | `medium` | Laravel idioms + Inertia props contract |
| `nest-architect` | nestjs | `sonnet` | `opus` | `medium` | Convention skills carry per-domain depth |
| `nextjs-architect` | nextjs | `sonnet` | `opus` | `medium` | RSC/Client patterns well-defined by spec and convention skills |
| `node-architect` | nodejs | `sonnet` | `opus` | `medium` | Express/Fastify — implementation driven by clear Node.js idioms |
| `python-architect` | python | `sonnet` | `opus` | `medium` | Plain Python — CLI tools, pipelines, API clients |
| `react-architect` | react | `sonnet` | `opus` | `medium` | React conventions and state/routing skills |
| `rn-architect` | react-native | `sonnet` | `opus` | `medium` | Expo/bare + iOS/Android axes |
| `spring-boot-architect` | spring-boot | `sonnet` | `opus` | `medium` | Spring Boot — controllers, JPA, migrations, Spring Security |
| `symfony-architect` | symfony | `sonnet` | `opus` | `medium` | Attribute routing, controllers-as-services, DI, Voters, Serializer, Messenger, Twig |
| `vue-architect` | vue | `sonnet` | `opus` | `medium` | Vue 3/2 detection + convention skills |
| `efcore-specialist` | aspnet-core | `sonnet` | — | `low` | EF Core Fluent API config, indexes, migration generation and verification |
| `django-migrations-specialist` | django | `sonnet` | — | `low` | Model fields/Meta indexes, makemigrations/sqlmigrate/migrate, migrate --check |
| `alembic-specialist` | fastapi | `sonnet` | — | `low` | SQLAlchemy 2.0 mapped classes, autogenerated Alembic revisions, upgrade + verify |
| `flask-migrate-specialist` | flask | `sonnet` | — | `low` | Flask-Migrate revision, upgrade, schema check |
| `artisan-specialist` | laravel | `sonnet` | — | `low` | Mechanical DB work: column types, indexes, factories |
| `doctrine-specialist` | symfony | `sonnet` | — | `low` | Doctrine entity mappings, generated migrations, fixtures, schema verification |

> High `effort` on Opus is the most expensive combination, so only the two leverage agents use it — BA and Security, where reasoning quality propagates into every later phase. Security sits one rung higher (`xhigh`) because its failures are the only ones the pipeline cannot detect on its own.

### Estimated cost for a medium feature

Assumes a medium feature, split roughly by phase workload below. Sonnet pricing includes an introductory discount through 2026-08-31 ($2/$10 per MTok in/out vs. the $3/$15 standard rate) — both are shown since most runs during the discount window will land closer to the lower figure.

| Phase | Agent | Model | Est. input / output tokens | Cost (standard) | Cost (intro, thru 2026-08-31) |
|---|---|---|---|---|---|
| BA | business-analyst | opus/high | 40K / 3K | ~$0.28 | ~$0.28 |
| Dev — plan | stack architect | opus | 80K / 4K | ~$0.50 | ~$0.50 |
| Dev — implement | stack architect | sonnet/medium | 250K / 8K | ~$0.87 | ~$0.58 |
| QA | qa-engineer | sonnet/medium (≤3 attempts) | 100K / 5K | ~$0.38 | ~$0.25 |
| Security | security-analyst | opus/xhigh | 40K / 6K | ~$0.35 | ~$0.35 |
| Docs | document-writer | haiku/low | 15K / 2K | ~$0.03 | ~$0.03 |
| **Total** | | | **525K / 28K** | **~$2.40** | **~$1.98** |

Per-MTok list prices used above: opus $5 in / $0.50 cached / $25 out; sonnet $3 / $0.30 / $15; haiku $1 / $0.10 / $5.

Two rows carry real uncertainty. The **Dev plan pass** has no measured token volume yet — 80K/4K is an assumption. **Security at `xhigh`** bills thinking tokens at the output rate, and how much `xhigh` adds has not been measured here; the row assumes output roughly doubles. Both are replaced by real numbers once `docs/cost-baseline.md` is populated.

This is roughly 30% above the previous single-tier estimate, and the trade is deliberate: the argument is cost per *completed* task, not per run. A development pass that starts from a weak plan gets redone and drags QA and security with it, which costs more than the delta. To opt out on any agent, set `model_plan: sonnet` or drop the field — that agent reverts to single-tier behaviour with no other changes.

Actual cost varies with codebase size, diff scope, and QA retry count — treat this as an order-of-magnitude estimate, not a quote. It also excludes the orchestrator's own token use; see `docs/cost-baseline.md`.

### Additional cost levers

- **Skip-rules:** typo-fix, whitespace-only, config-only, lightweight-no-db — skip unnecessary phases automatically.
- **QA hard cap:** max 3 attempts to fix failing tests, then STOP.
- **Compact handoffs:** each agent returns a ≤2–3K-token summary.
- **Prompt caching:** stable system prompts (no timestamps, slugs, or dynamic content) → ~60% cache hit rate on Sonnet.
- **Workflow cost caps:** `caps.max_total_cost_usd` in a recipe halts the run (with confirmation) once the running total crosses it. Set as a runaway guard, not a routine blocker.
- **Fewer spawns beat cheaper spawns.** The dominant cost driver is the per-phase subagent spawn, so removing an unnecessary phase saves more than re-tiering one. Skip-rules are the strongest lever here; adding a cheap agent to feed an expensive one usually loses.

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

git:
  model: git-flow
  develop_branch: develop
```

| Key | Merge semantics |
|---|---|
| `post_pipeline_checks` | **replaces** the plugin's list (`[]` disables checks) |
| `phase_command_overrides` | adds or replaces individual keys |
| `extra_phase_prompts` | **appends** to the plugin's phase guidance |
| `skip_phases` | removes phases from the resolved order |
| `convention_skills_extra` | appends to `convention_skills` |
| `agent_overrides` | replaces the agent for a phase, and adds it to the run roster |
| `active_workflow` | forces a workflow recipe |
| `git` | authoritative branching-model config — see [Git Flow Awareness](#git-flow-awareness) |

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
/plugin marketplace add mattpocock/skills
/plugin install mattpocock-skills@skills
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
# → Auto-detects stack, runs 5 phases in-session (with a dev-phase approval gate), creates PR
```

---

## Requirements

- Claude Code (latest)
- API Tier 2+ or Claude Max — a medium feature uses ~445K input tokens; Pro plan rate limits will throttle the pipeline.
- A Git repository for `document-writer` (PR creation).

## License

MIT — see [`LICENSE`](./LICENSE).
