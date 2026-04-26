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

Claude Code's `Agent` tool accepts only **bare agent names** — there is no `plugin:agent` namespacing. To keep core and stack plugins coexisting cleanly, reserve names by tier:

- **Core plugin (`sdlc`) reserves:** `orchestrator`, `ba`, `reviewer`, `security-scanner`, `docs-writer`, `debugger`, `devil`. Stack plugins MUST NOT ship agents with these names.
- **Stack plugins reserve generic role names:** `developer`, `tester`, `qa`, `dba`, `frontend`. Use exactly these names so the orchestrator's dispatch works unmodified across stacks.
- **One stack plugin per project.** If two stack plugins both expose `developer`, the orchestrator will prompt the user rather than silently pick one. Users are expected to enable a single stack plugin per project.

If your stack needs an extra role that no other plugin has ("erp-ledger-specialist", "ssr-renderer"), pick a distinctive name that is unlikely to collide, and document it in your stack's README.

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
