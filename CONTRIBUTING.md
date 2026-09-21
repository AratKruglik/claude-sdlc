# Contributing a Stack Plugin

This marketplace extends by **adding a plugin**, never by modifying the core. A stack plugin
declares what it can handle in a `stack.md` profile; the `sdlc` orchestrator discovers it,
resolves which aspects it owns, and dispatches to its agents. Nothing in `plugins/sdlc/`
changes when you add a stack.

## What a stack plugin is

A Claude Code plugin under `plugins/<name>/` that ships a `stack.md` with:

- `stack` — a unique lowercase name
- `priority` — `0` for the vanilla fallback, `100+` for a framework. Highest wins **per aspect**
- `aspects` — which of `backend, frontend, database, infra, testing, messaging` it owns
- `detect` — the file/content rules that make it match a project

Plus the agents it dispatches, the convention skills they load, and the shell commands it wants
run after a pipeline.

## Directory layout

```
plugins/<name>/
├── .claude-plugin/plugin.json     # name, version, description, dependencies
├── stack.md                       # the profile: frontmatter + phase prompt injections
├── agents/
│   └── <name>-architect.md        # distinctive names — see Agent naming below
├── skills/
│   └── <name>-conventions/SKILL.md
├── security-patterns.yaml         # optional, rule_name prefixed with your stack
├── hooks/hooks.json               # optional: formatter, config protection, typecheck
└── README.md
```

Look at `plugins/laravel-plugin/` for a full-stack example with a database specialist, and
`plugins/react-plugin/` for a frontend-only one.

## The `stack.md` contract

The frontmatter validates against [`schemas/stack.schema.json`](schemas/stack.schema.json) and
allows exactly four keys:

```yaml
---
stack: laravel
aspects: [backend, database]
priority: 100
detect:
  all:
    - file_exists: composer.json
    - file_contains:
        path: composer.json
        pattern: '"laravel/framework"'
---
```

`detect` takes `any` (OR) or `all` (AND). Rules are `file_exists`, `file_contains`, or the
literal `"*"` — the last one is reserved for the vanilla profile.

The body declares, in prose the orchestrator reads: `agents_per_phase`, per-phase prompt
injections, the convention skills to apply, `post_pipeline_checks`, and any `extra_phases`.

**Priority is a claim about specificity, not quality.** `inertia-vue` outranks `vue` because it
is the narrower match, not because it is better. Set yours so the more specific profile wins on
a project where both would match.

## Agent naming


Claude Code's `Agent` tool DOES support `plugin:agent` namespacing, and the orchestrator
dispatches every phase agent qualified that way (e.g. `sdlc:qa-engineer`,
`laravel-plugin:laravel-architect` — see `pipeline-orchestrator/SKILL.md` Step 3c).
Qualifying the dispatch does not, by itself, make a bare name safe to reuse: a project's
own `.claude/agents/{name}.md` is resolved by the *same* bare basename, so a stack plugin
agent named `developer` or `qa` still collides in name with any project-local agent the
user happens to have under that name — that collision is exactly what let a project-local
`tester`/`reviewer` roster silently shadow this pipeline's `qa-engineer`/`security-analyst`
in a real incident. **Prefer distinctive, plugin-scoped agent names** (`laravel-architect`,
`fastapi-architect`, `artisan-specialist`) over generic ones (`developer`, `tester`, `qa`,
`dba`, `frontend`) — this repo's own stack plugins already follow this convention (see
any `plugins/*/agents/*.md`). Reserve the generic names only for the core `sdlc` plugin's
own agents (`business-analyst`, `developer`, `qa-engineer`, `security-analyst`,
`document-writer` — the vanilla fallback used when no stack plugin overrides a phase).

If two active profiles declare the same agent name for the same phase, the orchestrator
prompts the user rather than silently picking one.

## Agent frontmatter

Every agent declares its cost and capability envelope:

| Field | Meaning |
|---|---|
| `model` | tier for normal dispatches — `opus` / `sonnet` / `haiku` / `fable` |
| `model_plan` | tier for the development **planning** pass (this marketplace's own field, not Claude Code's) |
| `effort` | reasoning budget: `low` / `medium` / `high` / `xhigh` / `max` |
| `maxTurns` | hard turn ceiling, so a stuck agent costs a bounded amount |
| `memory` | `project` to keep per-project notes under `.claude/agent-memory/` |
| `skills` | skills injected into the agent's context — architects carry `[sdlc:architect-conventions]` |
| `tools` | an **allowlist**. If you want the agent to invoke skills, `Skill` must be in it |

That last row is not a formality: before v2.0.0 no agent had `Skill` in `tools`, so every
documented "load this skill" instruction in the marketplace was dead text.

Your agent's `model` / `model_plan` / `effort` must also appear in the README's agent table —
`scripts/ci/check-readme-drift.sh` fails the build otherwise, in both directions.

## Local development

```bash
claude --plugin-dir ./plugins/sdlc --plugin-dir ./plugins/<your-stack>
```

Then, inside a project that your `detect` rules should match:

```
/sdlc:list-stacks     # did your profile match, and which aspects did it win?
/sdlc:doctor          # full preflight: detection, git flow, model routing, hooks
```

`/sdlc:list-stacks` is the fastest loop while tuning `detect` rules.

## Validation

Run what CI runs, before pushing:

```bash
bash scripts/ci/validate-schemas.sh       # stack.md, plugin.json, workflow recipes
bash scripts/ci/check-readme-drift.sh     # agent table vs frontmatter
bash scripts/ci/check-links.sh            # relative markdown links
claude plugin validate plugins/<name> --strict
find plugins -name 'test-*.sh' -exec bash {} \;
```

Requires `jq`, the mikefarah `yq` v4 binary, and Node. Every script here is bash — this repo
has no Python anywhere, deliberately, so that a contributor needs no language runtime beyond
what their own stack already requires.

## Pull request checklist

- [ ] `stack.md` frontmatter validates, and `priority` is set deliberately against the profiles
      it could collide with
- [ ] Agent names are distinctive, not generic
- [ ] Agent `model` / `model_plan` / `effort` added to the README table
- [ ] `tools:` includes `Skill` if the agent is told to invoke one
- [ ] `security-patterns.yaml` rule names are prefixed with your stack, and duplicate nothing a
      foundation plugin already ships
- [ ] Detection tested against a real project of that stack, not just a fixture
- [ ] `plugins/<name>/README.md` documents prerequisites and any MCP dependency
- [ ] Nothing in `plugins/sdlc/` changed

## Universal vs stack-specific

| Component | Core (`sdlc`) | Stack plugin |
|---|:---:|:---:|
| orchestrator, workflow recipes, git-flow detection | ✅ | — |
| BA, QA, security, docs agents | ✅ | — |
| `architect-conventions` skill | ✅ | — |
| core (`core_*`) security patterns | ✅ | — |
| architects and database specialists | — | ✅ |
| convention skills, framework idioms | — | ✅ |
| `stack.md`, stack security patterns, format hooks | — | ✅ |

If it references PHP, TypeScript or C#, it belongs in a stack plugin. If it would read the same
for every language, it belongs in core.
