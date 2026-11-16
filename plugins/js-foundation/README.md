# js-foundation

Shared JavaScript/TypeScript foundation for the [SDLC marketplace](../../README.md).

Pure shared library — **no agent, no stack profile**. Provides 2 stack-agnostic skills referenced cross-plugin by every JS/TS framework provider in the marketplace:

| Skill | Purpose |
|---|---|
| `typescript-patterns` | Strict mode, type design (discriminated unions, branded types, readonly defaults), no-`any` discipline, generics, error narrowing, validation at boundary, tsconfig hygiene. |
| `npm-patterns` | Package manager detection (npm/yarn/pnpm/bun), semver discipline, `dependencies` vs `devDependencies`, scripts conventions, lockfile policy, workspaces basics. |

## Why a separate plugin

Originally `typescript-patterns` and `npm-patterns` lived inside `nodejs-plugin`. Frontend plugins (react / vue / angular / etc.) referenced them cross-plugin via `nodejs-plugin:typescript-patterns`. Semantically wrong — frontend SPAs don't run on Node.js at runtime, even if Node powers their dev tooling.

This plugin extracts those two stack-agnostic skills into their own home. `nodejs-plugin` keeps the genuinely backend-specific skill (`node-conventions` — Express/Fastify/Koa patterns).

## Installation

You won't typically install `js-foundation` directly. It's a transitive dependency declared by every JS/TS framework plugin:

```
/plugin install nodejs-plugin@sdlc-marketplace      # backend Node
/plugin install nestjs-plugin@sdlc-marketplace      # opinionated backend
/plugin install nextjs-plugin@sdlc-marketplace      # full-stack React framework
/plugin install react-plugin@sdlc-marketplace       # React SPA
/plugin install react-native-plugin@sdlc-marketplace  # mobile
/plugin install vue-plugin@sdlc-marketplace         # Vue 3 SPA
/plugin install angular-plugin@sdlc-marketplace     # Angular SPA
```

Any of these auto-installs `sdlc` core + `js-foundation`.

## What it does NOT cover

- **No agent** — this plugin doesn't dispatch development. Framework plugins do that.
- **No stack profile** — this plugin doesn't claim aspects, doesn't activate per-project. Pure shared library.
- **No framework-specific patterns** — those live in framework plugins' own conventions skills (`react-conventions`, `nest-conventions`, `vue-conventions`, etc.).

## How framework plugins reference its skills

In a framework plugin's `stack.md`:

```markdown
## Convention skills to apply

- <framework-plugin>:<framework>-conventions
- <framework-plugin>:<framework>-routing
- ...
- js-foundation:typescript-patterns
- js-foundation:npm-patterns
```

The orchestrator's pipeline-orchestrator/SKILL.md resolves these references at runtime via `mcp__skills__list_skills` (or filesystem fallback) and surfaces them to the development agent.

## Versioning

Patches and minor versions of this plugin should be backwards-compatible — additions to skills, refinements to anti-pattern lists. A major version bump signals a breaking change in skill contents (e.g., a recommendation reversed). Framework plugins reference by skill name, not version — so a breaking change here requires coordinated update across all dependents.
