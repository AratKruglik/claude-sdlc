# SDLC Marketplace for Claude Code

Multi-stack AI-assisted SDLC pipelines built on the **Stack Provider Pattern**: a single core orchestrator runs the pipeline, framework plugins register themselves via declarative `stack.md` profiles. No core overrides, no slot registries, no copy-paste between stacks.

**v2.0.0** — 27 marketplace entries: 24 local (1 core + 5 shared libs + 7 JS/TS stacks + 4 PHP/Laravel/Symfony stacks + 3 Java/.NET stacks + 4 Python stacks) plus 3 optional external.

What is new in 2.0.0, and why each one is a breaking change:

- **[Measured telemetry](#measured-telemetry)** — per-phase cost and tokens are now read from each subagent's own transcript by hooks, not estimated at `chars / 4`. `_telemetry.json` changes shape, and `docs/cost-baseline.md` becomes populatable for the first time.
- **[Resuming a run](#resuming-a-run)** — the run marker becomes a state file, and `/sdlc:start --resume` continues a crashed or compacted run at the phase it reached instead of paying for it twice.
- **[Parallel phases](#pipeline-phases)** — QA and security run as one step. `Phase N/total` now counts pipeline *steps*, so both members share an `N`, and workflow recipes gain a `parallel` construct.
- **Security is report-only** — `security-analyst` has no `Edit` tool. Critical and High findings are applied by the development architect in a fix pass, then re-verified by QA.
- **[Run-scoped guards](#run-scoped-guards)** — three hooks that deny staged secrets, `--no-verify`, and mid-run edits to tooling config, all inert outside a pipeline run.
- **Agent frontmatter** — `skills:`, `maxTurns:` and `memory: project` across every agent, and the `Skill` tool is now actually in their allowlists, which it never was.

**Git-flow aware:** the pipeline detects your branching model *and your existing naming convention*, classifies the task type, proposes a branch, and targets the PR at the right base — see [Git Flow Awareness](#git-flow-awareness). Cost-optimized: model tiering + `effort` per-subagent, **two-tier development phase** (Opus plans, Sonnet implements), enforced workflow cost caps, file-scoped format hooks, shared architect conventions, per-aspect QA fan-out on full-stack runs. See [MODEL-ROUTING.md](MODEL-ROUTING.md) for the routing audit behind the cost model, and [CHANGELOG.md](CHANGELOG.md) for the full upgrade notes.

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

### The default pipeline — 5 phases in 4 steps

Before Phase 1, the orchestrator detects the stack profile and the [git branching model](#git-flow-awareness), classifies the task type, and asks you to confirm the branch.

```
Phase 1: BA → business-analyst (opus/high)
          ↓ output: docs/plans/{slug}/01-business-analysis.md
Phase 2: Dev → [stack agent] (opus plan → approval gate → sonnet implement)
          ↓ output: docs/plans/{slug}/02-development-plan.md, 02-development.md
Phase 3: QA ∥ Security → qa-engineer (sonnet/medium, max 3 attempts)
                       ∥ security-analyst (opus/xhigh, report-only)
          ↓ output: docs/plans/{slug}/03-qa.md, 04-security.md
          ↓ then, only if Critical/High were found:
            security [pass:fix]  → the development architect applies the fixes
            qa [pass:verify]     → the existing suite is re-run
Phase 4: Docs → document-writer (haiku/low)
          ↓ output: PR on GitHub
```

QA and security read the same finished diff and never write to the same files, so they run as
one step. **`Phase N/total` counts steps, not phases** — both members of a parallel group share
one `N` and are told apart by their own phase name (`Phase 3/4: qa`, `Phase 3/4: security`).

### Security is report-only

`security-analyst` has no `Edit` tool. It classifies findings and prescribes the exact change
for each Critical and High one; the **development-phase architect** then applies them in a
`[pass:fix]` dispatch with a minimal-diff contract, and QA re-runs the existing suite in a
`[pass:verify]` dispatch if anything was actually fixed.

The reviewer and the author of a fix are deliberately different agents: an agent that fixes
what it just found reviews its own work, and a fix that breaks a test is exactly what the
verify rerun exists to catch.

Nothing runs on an unreliable basis — if the security review itself failed, no fix pass runs,
because there is no trustworthy finding list to apply. If QA failed, the fix pass still runs
but the verify rerun does not: there is no passing baseline to compare against.

### Example: Laravel (6 phases in 5 steps)

```
Phase 1: BA → business-analyst
Phase 2: Dev/backend  → laravel-architect    (aspect=backend)
Phase 3: Dev/database → artisan-specialist   (extra phase after backend)
Phase 4: QA ∥ Security → qa-engineer ∥ security-analyst
Phase 5: Docs → document-writer
```

A stack profile's `extra_phases` is always inserted as its **own** step, never as a member of
an existing parallel group: declaring "after development" states a dependency, not that the
phase is safe to run alongside that group's members.

### Per-aspect dispatch (multi-framework projects)

For a project with a Node.js backend and a React frontend:

- Phase 2/backend → `node-architect`
- Phase 2/frontend → `react-architect`

Aspects are dispatched in canonical order: `database → backend → frontend → testing`.

Development aspects run **sequentially** by default: the frontend plan is built against the
"Contract for frontend" section of the backend plan, which the backend architect fixes at plan
time. Setting `aspect_execution: parallel-implement` in `sdlc.local.yaml` keeps the plan passes
sequential and behind one approval gate but dispatches the backend and frontend
*implementation* passes concurrently — and only when the orchestrator can verify, from the two
approved plans, that their file sets are disjoint and neither touches a shared-fate file
(`package.json`, `composer.json`, lockfiles, `Dockerfile*`, CI YAML, `.env*`, shared routes).
Otherwise it falls back to sequential and prints which invariant failed.

That mode is **experimental**: the file-set invariants constrain what the plans declare, not
what an agent can reach, and tool-level interference (a repo-wide formatter, generated build
output) is guarded by prompt text rather than enforced. It is off by default.

---

## Commands

| Command | Purpose |
|---|---|
| `/sdlc:start "feature"` | Run the full pipeline (5 phases, QA and security in parallel) |
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
| `default` | BA → Dev → (QA ∥ Security) → Docs | any task |
| `bugfix` | Dev → (QA ∥ Security) → Docs | task type is `fix` or `bugfix`; ≤500 LOC |
| `hotfix` | Dev → (QA ∥ Security) → Docs | task type is `hotfix`; ≤200 LOC; $2.50 cost cap |
| `refactor` | Dev → (QA ∥ Security) → Docs | task type is `refactor` |
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

**Resolution order.** Claude Code resolves a subagent's model in this order:

1. the per-invocation `model` parameter (what Layer 1 passes),
2. the agent's `model:` frontmatter (`inherit` = the session model),
3. `CLAUDE_CODE_SUBAGENT_MODEL`,
4. the session model.

Both enforcement layers write the first two, so `CLAUDE_CODE_SUBAGENT_MODEL` on its own does
**not** override them — it only fills in where neither is set, which for this pipeline is never.
Setting it to `inherit` is the same as leaving it unset.

> ⚠️ **The override that does defeat both layers is `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`**
> (Claude Code v2.1.257+). With it set, Claude Code ignores every agent's `model:` frontmatter
> *and* the dispatch parameter, and every phase runs on `CLAUDE_CODE_SUBAGENT_MODEL` — or on the
> session model when that variable is unset. An organization `availableModels` allowlist can
> likewise skip a value in favour of the inherited model. Run `/sdlc:doctor` to see whether
> either is in play: while `_FORCE` is active, none of the cost figures in this README apply.
>
> Before Claude Code v2.1.251 `CLAUDE_CODE_SUBAGENT_MODEL` came *first* in the order and did
> override both layers by itself. Documentation written against that behaviour — including
> earlier versions of this file — is stale, not wrong about a different build.

**Two-tier development phase:** the development phase runs a planning pass and an implementation pass either side of a human approval gate, and they resolve different tiers. The planning pass reads `model_plan:` (Opus by default), the implementation pass reads `model:` (Sonnet). The orchestrator marks the pass in the `Agent()` `description` field so the hook enforces the matching one — see `MODEL-ROUTING.md` §4.1.

---

## Agent Capability Frontmatter

Beyond `model` / `model_plan` / `effort`, every agent declares three capability fields that
Claude Code reads natively.

**`skills:`** — the 24 stack architects and database specialists carry
`skills: [sdlc:architect-conventions]`, which injects the shared conventions skill (hard
rules, code quality bar, workflow steps, report contract) into the agent's context before
it starts. Until v2.0.0 those agents were merely *instructed* to load it via the Skill tool,
which they could not do: `tools:` is an allowlist and `Skill` was not in it. Every agent that
the orchestrator tells to invoke a skill — all of them except `document-writer` — now lists
`Skill` in `tools:`, so the stack's convention skills (`Apply skills: …` in the dispatch
prompt) and the optional `superpowers` skills are reachable as well.

**`maxTurns:`** — a hard ceiling on agent turns, so a stuck agent costs a bounded amount
instead of an open-ended one: architects 120, database specialists and `qa-engineer` 60,
`business-analyst` and `security-analyst` 80, `document-writer` 30. These are starting
values chosen from phase shape, not measurements; Block A telemetry (`_usage.jsonl`) now
records real turn counts, so they should be recalibrated from data. Hitting the cap
truncates the agent's output, which the orchestrator treats as a validation failure
(SKILL Step 3e), never as a pass.

**`memory: project`** — architects, database specialists and `security-analyst` keep
per-project notes under `.claude/agent-memory/{agent-name}/`, so a second run on the same
repo starts with what the first one learned about its layout and conventions.
`business-analyst` is deliberately excluded: its job is to read the request and the product
context afresh, and carrying over a previous feature's framing is a bias, not a saving.
`qa-engineer` and `document-writer` derive everything from the current run's artefacts.

> ⚠️ Agent memory is injected into the agent's context, so anything written there is
> attacker-reachable if a previous run processed untrusted input. Treat
> `.claude/agent-memory/` as project state you review, not as a cache you ignore.

---

## Measured Telemetry

Until v2.0.0 every per-phase cost figure in this repo was an estimate: the `Agent` tool result
carries no usage data, so the orchestrator divided the returned characters by four and called
it tokens. That made `docs/cost-baseline.md` unpopulatable and the workflow cost caps a
comparison against a guess.

Three hooks now measure it instead, while a run's state file is fresh:

- `dispatch-log.sh` records every `Agent` dispatch (`PreToolUse`) and the `agent_id` Claude Code
  assigns it (`SubagentStart`)
- `subagent-usage.sh` (`SubagentStop`) reads the finished subagent's own transcript, sums its
  usage **deduplicated by `message.id`**, and prices it from [`references/pricing.json`](plugins/sdlc/references/pricing.json)

All three append to `docs/plans/{slug}/_usage.jsonl`. The orchestrator only reads it, via
`scripts/usage-report.sh`, which pairs dispatches with their results and attributes them to a
phase, aspect and pass.

The dedupe matters: one API response spans several transcript lines carrying the same
`message.id`, and summing them naively inflates the total roughly 2.5–3×. A cost report that is
wrong by 3× is worse than no report, because it looks authoritative.

Nested dispatches — a phase agent spawning `Explore` or a superpowers skill — are measured too
and land in `nested_cost_usd`. That is real pipeline spend no earlier version could see.
`total_cost_usd` keeps its old meaning (phase dispatches only) so `cost_scope` stays truthful,
and `total_cost_usd_including_nested` carries the full figure.

Where a transcript cannot be found, the row is written anyway with
`usage_source: transcript_missing` and null tokens. A run with any estimated row is not
baseline-grade, and `usage_source_summary` in `_telemetry.json` says so.

> `total_cost_usd` is a **floor**, not the bill. Only subagent spawns are metered — the
> orchestrator's own consumption (this skill's body, stack detection, workflow resolution, the
> approval-gate exchanges) runs on the session model and is invisible to any hook.

---

## Resuming a Run

A pipeline run costs real money in its first phases. Before v2.0.0 a crash, a disconnect or a
context compaction mid-Dev lost all of it: the run's state lived only in the session.

`.claude/.sdlc-run-active.json` is now a state file (schema v2) holding the decisions a rerun
cannot re-derive — resolved phases, stack profiles, git-flow choices, the workflow and why it
was chosen, the cost cap, and a `phase_status` map updated at every phase boundary. It stays
under ~2 KB: anything deterministic from disk is recomputed rather than stored.

```bash
claude                      # after a crash, in the same repo
/sdlc:start --resume
```

The orchestrator prints what it found, re-enters at the first group with unfinished members,
and dispatches only those. A development aspect that was `planned` goes straight to the
approval gate; one that was `approved` goes straight to the implementation pass. Nothing
already completed is paid for twice.

Two guards make this safe rather than merely convenient:

- **Branch check.** Resume halts if `HEAD` is not the branch the run recorded. Resuming a
  half-finished feature onto the wrong branch would interleave two changes with no warning.
- **Plan-file check.** `planned` means the plan pass returned — but if the file it should have
  written is missing, the run crashed between those two moments, and the plan pass re-runs
  rather than presenting an approval gate for a plan that does not exist.

Starting a fresh run while a state file is still fresh prompts three ways — *resume*, *start
fresh* (which archives any colliding `docs/plans/{slug}/`), or *abort* — so a second run never
silently overwrites the first one's artefacts.

`/sdlc:doctor` reports the state file's age and `phase_status` summary, including when it is
stale.

---

## Run-Scoped Guards

Three hooks are **inert outside a pipeline run** and active only while a fresh
`.claude/.sdlc-run-active.json` exists. That condition is the whole design: these guards exist
to constrain agents working unattended, and a tool that second-guessed a human's own commit or
config edit would be a bug.

| Hook | Event | What it does |
|---|---|---|
| `pre-commit-guard.sh` | `PreToolUse` / `Bash` | Denies `git commit --no-verify` and staged secrets (API keys, AWS key ids, private key blocks, hardcoded credential literals), naming `file:line`. Warns — never denies — on `console.log` / `dd(` / `var_dump(` / `debugger` outside test paths. |
| `config-protection.sh` | `PreToolUse` / `Edit\|Write` | Denies edits to the stack's tooling config (`pint.json`, `phpstan.neon*`, `eslint.config.*`, `ruff.toml`, `.editorconfig`, `checkstyle.xml`, …) — unless the run's `task_type` is `chore`, which is how tooling config is deliberately changed. |
| `post-implement-check.sh` | `SubagentStop` | Runs the stack's typecheck or linter **once** after an architect finishes, over the diff against the base branch, and relays failures to the orchestrator as a retry hint (≤40 lines). Silent when the tool is not installed. |

Why `config-protection` denies rather than warns: an agent that loosens a linter rule so its
own diff passes has widened the project's standards to fit one feature, and a diff review is
unlikely to catch a two-line config change sitting among source edits.

Why `post-implement-check` is batched rather than per-edit: a typecheck after every `Edit`
reports errors the next edit was about to fix, which trains everyone to ignore it. It also
cannot block — `SubagentStop` has no deny — so a type error is routed into the orchestrator's
implement-pass validation, not acted on by the hook.

A removed secret is the fix, not the defect: the commit guard scans **added** lines only, so
moving a key to an environment variable is never blocked.

---

## Stack-Detection Caching

Stack-profile detection (Step 0b in `pipeline-orchestrator/SKILL.md`) matches every installed plugin's `stack.md` against the current project — a Glob-then-Read-then-parse pass over every plugin, repeated on every `/sdlc:start` and `/sdlc:doctor` invocation.

A `SessionStart` hook — `plugins/sdlc/hooks/session-start-stack-cache.sh` — precomputes this once per session, for free, and writes the result to `${CLAUDE_PLUGIN_DATA}/stack-cache/{hash-of-repo-path}.json` (the plugin data directory Claude Code provides). It fires on `startup`, `resume`, and `clear` (not `compact`/`fork`, where the repo hasn't changed), runs `scripts/detect-stack.sh`, and exits silently — it never prints anything, since a `SessionStart` hook fires for every session on the machine, including ones with nothing to do with this plugin.

`/sdlc:start` Step 0b reads this cache when it is fresh (< 6h old, matching the repo it detected for) and skips the full scan entirely. A recorded aspect tie in the cache still halts the gate and asks for `--stack=NAME` — the cache never silently resolves a tie the inline algorithm wouldn't. `--redetect-stack` forces a full scan. `/sdlc:doctor` always computes fresh (same "a doctor that echoes a stale cache cannot diagnose a stale cache" principle as its git-flow check) but reports the cache's age and whether it agrees.

This hook is also registered in `hooks.json` and activates automatically on install — no manual `settings.json` changes needed.


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

### What a run actually costs

**Short answer: a medium feature costs roughly $4–10, and about $6 is the central case.**
A small fix lands near $2.50, a large one can pass $15. The figure below is a model, not a
quote — but it is built the way the pipeline actually bills, which the table this replaced was
not.

#### Why the old estimate was wrong by 2–3×

The previous table modelled each phase as **one API request**: ~40K tokens in, ~3K out. That is
not how an agentic dispatch bills. An agent runs a loop, and **every turn re-sends the entire
conversation so far**. A 45-turn implementation pass whose context grows by ~2.5K tokens a turn
bills over 3 million input tokens, not 250K — most of them at the cache-read rate, but still
billed.

So the dominant term is not the model tier. It is **turns × context size**, and because context
grows as the loop runs, cost is roughly **quadratic in dispatch length**:

| Turns and per-turn growth | With caching | Cache cold |
|---|---|---|
| ×0.6 (small task) | $2.77 | $6.50 |
| ×0.8 | $4.22 | $12.26 |
| **×1.0 (medium — the model below)** | **$6.04** | **$20.88** |
| ×1.3 | $9.87 | $41.81 |
| ×1.6 (large) | $14.94 | $72.91 |

That curve is why `maxTurns` exists, why the QA iteration cap is 3, and why "one fewer phase"
saves more than "one cheaper model". A dispatch that runs 60% longer costs 2.5× more, not 60%
more.

#### The model

Medium feature, single backend stack (Laravel), Opus plans / Sonnet implements.

| Phase | Tier | Turns | Cache write | Cache read | Output | Cached | Cold |
|---|---|---:|---:|---:|---:|---:|---:|
| business_analysis | opus | 14 | 44K | 299K | 10.5K | $0.69 | $1.77 |
| development — plan | opus | 20 | 77K | 789K | 16K | $1.27 | $4.38 |
| development — implement | sonnet | 45 | 128K | 3,157K | 43.5K | $1.39 | $6.78 |
| qa | sonnet | 30 | 78K | 1,160K | 26.5K | $0.69 | $2.59 |
| security | opus | 22 | 69K | 756K | 36K | $1.71 | $4.70 |
| security `[pass:fix]` ×0.35 | sonnet | 15 | 16K | 149K | 3.7K | $0.11 | $0.35 |
| qa `[pass:verify]` ×0.30 | sonnet | 8 | 4K | 18K | 1.3K | $0.03 | $0.05 |
| documentation | haiku | 10 | 22K | 106K | 5.5K | $0.07 | $0.14 |
| nested (`Explore`, skills) ×2 | haiku | 6 | 39K | 105K | 6.4K | $0.09 | $0.14 |
| **Total** | | | | | | **$6.04** | **$20.88** |

**Which end is realistic.** Turns inside one dispatch are seconds apart, so the 5-minute cache
holds and the **cached column is the normal case**. The cold column is what a run costs when
caching does not engage — and it is the honest upper bound, so it is shown rather than buried.

#### What is measured and what is assumed

Being explicit about this is the point; the estimate this replaces was not.

| Input | Source |
|---|---|
| Prices per MTok | **Measured** — [`references/pricing.json`](plugins/sdlc/references/pricing.json), verified against Anthropic's pricing page |
| Static prompt prefix per dispatch | **Measured** — byte counts of the actual agent, skill, `stack.md` and base-prompt files |
| Tokenizer ratio | **Measured rule** — Opus 5 and Sonnet 5 use a newer tokenizer producing ~30% more tokens for the same text (≈3.1 chars/token); Haiku 4.5 uses the previous one (≈4 chars/token) |
| Turns per dispatch | **Assumed** — 14/20/45/30/22/10, all well under each agent's `maxTurns` |
| Context growth per turn | **Assumed** — 1.5K–3.5K tokens, one file read or tool result |
| Fix-pass firing rate | **Assumed** — 35% of runs find a Critical or High issue |
| Nested dispatches | **Assumed** — two per run |

The last four rows are where your numbers will diverge from these. They are also exactly what
[measured telemetry](#measured-telemetry) now records, so **replace this table with your own
`docs/cost-baseline.md` as soon as you have one.**

#### What v2.0.0 added to the bill

Three of these are new costs, and one of them is the price of fixing a bug:

- **Convention skills now actually load.** No agent had `Skill` in its `tools:` allowlist
  before v2.0.0, so `architect-conventions` and every stack's convention skills — about 31K
  characters, ~10K tokens for a Laravel run — never reached the agent. They do now. That is a
  real increase, and it buys the guidance the architects were always documented as having.
- **Nested dispatches became visible.** `Explore` and superpowers skills spawned by a phase
  agent were always paid for and never counted. They are a line item now (`nested_cost_usd`),
  not a new expense.
- **Security fix pass and QA verify rerun** are genuinely new dispatches, but conditional and
  cheap — about $0.14 combined at the assumed firing rates, against an `opus/xhigh` review that
  no longer spends Opus output tokens writing the fix itself.

#### Cost caps were recalibrated against this model

`hotfix` previously capped at **$2.50** against a modelled healthy cost of **$2.45** — it would
have fired on normal runs, which is the one thing its own comment says a runaway guard must
never do. It is now **$8.00**. `docs-only` moved from $0.20 to $0.40 for the same reason, with
less margin at stake.

### Additional cost levers

- **Skip-rules:** typo-fix, whitespace-only, config-only, lightweight-no-db — skip unnecessary phases automatically.
- **QA hard cap:** max 3 attempts to fix failing tests, then STOP.
- **Compact handoffs:** each agent returns a ≤2–3K-token summary.
- **Prompt caching:** stable system prompts (no timestamps, slugs, or dynamic content) keep the prefix cacheable. The model above shows what this is worth: **$6 cached against $21 cold** on the same run. Anything that varies per dispatch in the stable prefix silently costs 3×.
- **Workflow cost caps:** `caps.max_total_cost_usd` in a recipe halts the run (with confirmation) once the running total crosses it. Set as a runaway guard, not a routine blocker.
- **`maxTurns` ceilings:** a bounded dispatch cannot run away. Because cost is roughly quadratic in dispatch length, a cap is worth more than it looks — and the current values are unmeasured starting points that telemetry should now tighten.
- **Shorter dispatches beat cheaper models.** The dominant cost driver is not the tier, it is turns × context. Removing a phase, or ending a dispatch two turns earlier, saves more than re-tiering one. Skip-rules are the strongest lever here; adding a cheap agent to feed an expensive one usually loses, because it adds a whole context-accumulating loop to save a per-token rate.

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

aspect_execution: sequential   # or parallel-implement (experimental)
post_check_fix_attempts: 0     # 1 allows one minimal-diff fix pass after a failed post-check

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
| `skip_phases` | removes phases from the resolved order — per **member**, so skipping `security` leaves QA running alone rather than dropping the whole step |
| `convention_skills_extra` | appends to `convention_skills` |
| `agent_overrides` | replaces the agent for a phase, and adds it to the run roster |
| `active_workflow` | forces a workflow recipe |
| `aspect_execution` | `sequential` (default) or `parallel-implement` — **experimental**, see [Per-aspect dispatch](#per-aspect-dispatch-multi-framework-projects) |
| `post_check_fix_attempts` | `0` (default) or `1` — one minimal-diff fix pass when a post-pipeline check fails |
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

### Plugin evals

`plugins/sdlc/evals/` holds four behavioural cases, run with
`claude plugin eval plugins/sdlc --scaffold`:

| Case | What it pins down |
|---|---|
| `empty-arguments` | `/sdlc:start` with no description asks and **stops** — it never guesses a feature and starts a multi-phase run |
| `unknown-workflow` | `--workflow=<nonexistent>` halts instead of quietly falling back to `default` |
| `stack-detection` | on a Laravel + Inertia/Vue fixture, `laravel` owns backend and `inertia-vue` owns frontend — not plain `vue` |
| `qualified-dispatch` | dispatch is always `plugin:agent`, and a failed dispatch is **never** retried bare |

These make real model calls, so they are a manual `workflow_dispatch` job rather than part of
every PR — the rest of CI is deterministic and free, and mixing the two would make every PR
wait on a paid, non-deterministic check.

### Schema validation

```bash
# Everything at once: 19 stack.md frontmatters, 24 plugin.json, 5 workflow recipes
bash scripts/ci/validate-schemas.sh

# Plus the two other declarative checks CI runs
bash scripts/ci/check-readme-drift.sh   # README agent table vs agent frontmatter
bash scripts/ci/check-links.sh          # relative markdown links resolve
```

Requires `jq`, the mikefarah `yq` v4 binary, and Node (for `ajv-cli`). The previous
recipe here piped `yq '.frontmatter'` into `check-jsonschema`, which never worked —
`yq` has no `.frontmatter` key for a markdown file.

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

- Claude Code v2.1.257 or later (earlier builds resolve the subagent model in a different
  order — see [Model Enforcement](#model-enforcement))
- `jq` — required for measured telemetry, the stack cache and the run-scoped guards. Without
  it those features degrade silently rather than failing: telemetry rows fall back to
  `estimated`, the cache is skipped, the guards allow. The pipeline still runs.
- API Tier 2+ or Claude Max. A medium feature bills several **million** input tokens once
  the agentic loop's per-turn context re-sends are counted (see [What a run actually
  costs](#what-a-run-actually-costs)) — most of them at the cache-read rate, but Pro-plan
  rate limits will throttle the pipeline well before cost becomes the constraint.
- A Git repository for `document-writer` (PR creation).

## License

MIT — see [`LICENSE`](./LICENSE).
