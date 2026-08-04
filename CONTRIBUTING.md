# Contributing a Stack Plugin

The `claude-sdlc` marketplace is designed to be extended with stack plugins — language/framework-specific adapters that plug into the core orchestration. This guide walks through adding one.

## What "stack plugin" means

A stack plugin is a Claude Code plugin that lives under `packages/<stack>/` and declares:

- At least a `developer` agent and a `tester` agent.
- A `stack-manifest.json` that the core orchestrator uses to discover and route to these agents.
- Lint/test/build shell commands.
- Optional auto-detection rules (which project files indicate this stack).

The orchestrator in the `sdlc` core plugin reads all installed stack manifests at session start and maps generic roles ("developer", "tester", "qa") to your stack-specific agents.

## Directory layout

```
packages/<stack>/
├── .claude-plugin/
│   └── plugin.json           # { "name": "sdlc-<stack>", "version": "0.1.0" }
├── stack-manifest.json       # Contract with core — validates against schema
├── agents/
│   ├── developer.md          # Required
│   ├── tester.md             # Required
│   ├── qa.md                 # Optional (E2E)
│   └── ...                   # Any custom roles
├── skills/
│   └── <framework-skill>/SKILL.md
├── rules/
│   ├── code-style.md
│   └── architecture.md
└── README.md
```

## stack-manifest.json contract

Validate against [`packages/core/schema/stack-manifest.schema.json`](./packages/core/schema/stack-manifest.schema.json). Minimum required fields:

```json
{
  "stack": "<unique-id>",
  "language": "<primary-language>",
  "version": "0.1.0",
  "agents": {
    "developer": { "file": "agents/developer.md", "required": true },
    "tester":    { "file": "agents/tester.md",    "required": true }
  },
  "commands": {
    "test": "<shell command to run tests>",
    "lint": "<shell command to run linter>"
  }
}
```

Recommended additions:

- `detect` — files/content patterns for auto-detection (e.g. `composer.json` → laravel).
- `pipeline_overrides` — reorder phases for `feature` / `bugfix` when your stack needs extra steps (DDD modelling, migrations, etc.).
- Optional agents: `qa`, `dba`, `frontend`, or anything custom.

## Local development

```
# From the repo root
claude --plugin-dir ./packages/core --plugin-dir ./packages/<your-stack>
```

Then inside Claude Code:

```
/sdlc:bugfix "reproduce the failing test"
```

The orchestrator will detect your stack via the manifest and route the `developer`/`tester` roles to your agents.

## Schema validation

If you have `ajv` installed:

```
npx ajv validate \
  -s packages/core/schema/stack-manifest.schema.json \
  -d packages/<your-stack>/stack-manifest.json
```

## Pull request checklist

- [ ] `stack-manifest.json` validates against the schema.
- [ ] Both `developer` and `tester` agents exist and have `tools:` frontmatter (principle of least privilege).
- [ ] `commands.test` and `commands.lint` actually work in a sample project.
- [ ] `README.md` in your package documents the stack version, prerequisites, and any MCP dependencies.
- [ ] You tested locally with `claude --plugin-dir` against the core plugin.
- [ ] No Laravel/React/etc.-specific assumptions leak into `packages/core/`.

## Role naming convention

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

## Universal vs stack-specific — quick reference

| Component                                 | Lives in core | Lives in stack |
|-------------------------------------------|:-------------:|:--------------:|
| orchestrator, BA, reviewer, security, docs, debugger, devil | ✅ | — |
| `workflow.md`, `git-operations.md`        | ✅            | —              |
| `stack-discovery`, `checkpoint-protocol`, `pipeline-synthesis` skills | ✅ | — |
| developer, tester, qa, dba, frontend      | —             | ✅             |
| `code-style.md`, `architecture.md`        | —             | ✅             |
| Framework-specific skills                 | —             | ✅             |
| `stack-manifest.json`                     | —             | ✅             |

If you're not sure where something belongs — if it's stack-agnostic, it goes in core; if it references PHP/TypeScript/C#, it goes in the stack package.
