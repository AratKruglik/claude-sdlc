# nestjs-plugin

NestJS opinionated backend stack provider for the [SDLC marketplace](../../README.md).

Adds a NestJS-specific implementation agent (`nest-architect`) and 5 conventions skills covering modules/DI, decorators, ORM, advanced surfaces (GraphQL/WebSockets/Microservices), and testing. Activates automatically on projects with `package.json` containing `@nestjs/core`. Wins over `nodejs-plugin` (priority 100) via priority 200.

## What this plugin adds

| Component | Purpose |
|---|---|
| `stack.md` | Stack profile, priority=200, aspects=[backend, database]. |
| `agents/nest-architect.md` | Sonnet-tier developer for NestJS backend. Replaces vanilla `developer` and `node-architect`. |
| `skills/nest-conventions/` | Module structure, DI, lifecycle, configuration, exception handling, logging. |
| `skills/decorator-patterns/` | Built-in + custom decorators, metadata reflection via `Reflector`. |
| `skills/nest-data-layer/` | TypeORM, Prisma, Mongoose patterns + transactions + migrations. |
| `skills/nest-advanced/` | GraphQL (code-first), WebSocket gateways, microservice transports. Applied on detect. |
| `skills/nest-testing/` | `Test.createTestingModule`, supertest, ORM mocking, e2e patterns. |
| `hooks/hooks.json` | Auto-format TS/JS via Prettier + ESLint after Edit/Write (silent if not installed). |

## What it does NOT cover

- **Plain Node.js backend** without `@nestjs/core` — `nodejs-plugin` handles those (Express/Fastify/Koa/plain).
- **Frontend** (React/Vue/RN/Next) — separate frontend plugins, frontend aspect.
- **Laravel-style monolith DBs** — `laravel-plugin` (PHP/database aspect) for Laravel projects. Aspect resolution prevents collision (NestJS detects only on JS projects).

## Cross-plugin skill reuse

`nestjs-plugin` declares `dependencies: ["sdlc", "js-foundation"]` in `plugin.json` — Claude Code auto-installs `js-foundation` when you install this. The stack profile references skills from both plugins in `convention_skills`:

- `js-foundation:typescript-patterns` — strict TypeScript discipline (no-`any`, validation at boundary, etc.).
- `js-foundation:npm-patterns` — package manager detection, semver, lockfile hygiene.
- `nestjs-plugin:nest-conventions` — NestJS module/DI patterns.
- `nestjs-plugin:decorator-patterns` — decorator usage.
- `nestjs-plugin:nest-data-layer` — ORM patterns (applied when ORM detected).
- `nestjs-plugin:nest-advanced` — GraphQL/WS/Microservices (applied on detection).
- `nestjs-plugin:nest-testing` — testing patterns.

This is the first cross-plugin skill reuse in the marketplace — DRY without duplication.

## Installation

```
/plugin marketplace add AratKruglik/claude-sdlc
/plugin install nestjs-plugin@sdlc-marketplace
```

`sdlc` core and `js-foundation` install automatically as dependencies.

## Usage

On any NestJS project, the plugin activates automatically:

```
/sdlc:start "Add user CRUD with role-based authorization"
```

The orchestrator detects the NestJS stack profile (priority 200 wins over nodejs's 100), claims both `backend` and `database` aspects, and dispatches `nest-architect` for the development phase. All other phases (BA, QA, Security, Docs) use the core agents.

## Verification

```
/sdlc:list-stacks
```

Should show `nestjs priority=200` with active match (backend + database) on a NestJS project, and `nodejs priority=100` as a no-match-loser.

```
/sdlc:doctor
```

Confirms 3 plugins installed (sdlc + js-foundation + nestjs-plugin), no degraded mode warnings.

## Composition with frontend plugins

Once `react-plugin` / `vue-plugin` / `nextjs-plugin` are installed, full-stack NestJS + frontend projects activate both `nestjs-plugin` (backend + database) and the matching frontend plugin (frontend aspect). The orchestrator runs the development phase per aspect:

- `Phase 2/N: development — backend → nest-architect`
- `Phase 2/N: development — frontend → react-architect` (or `vue-architect` etc.)

## Package manager detection

`post_pipeline_checks` auto-detect from lockfile:

| Lockfile present | Runner used |
|---|---|
| `pnpm-lock.yaml` | `pnpm test`, `pnpm run lint`, `pnpm run build` |
| `yarn.lock` | `yarn test`, `yarn run lint`, `yarn run build` |
| (default) | `npm test`, `npm run lint --if-present`, `npm run build --if-present` |

Plus `npx --no-install tsc --noEmit` always runs to catch type errors.

The `nest-architect` agent applies the same detection for any install/script invocations during development.

## Local override

To customize per-project (e.g., monorepo runners like Nx/Turborepo, custom test scripts, skip security phase if external SAST handles it), create `.claude/sdlc.local.yaml` in the project root and set `post_pipeline_checks` explicitly. Recognized top-level keys: `post_pipeline_checks` (replaces plugin defaults), `phase_command_overrides` (passed as context to agents), `extra_phase_prompts` (appends per-phase guidance), `skip_phases`, `convention_skills_extra`.

## Coverage scope (v0.0.1)

This plugin covers the **full NestJS surface** — REST controllers, ORM (TypeORM/Prisma/Mongoose), GraphQL (code-first), WebSocket gateways, microservices (TCP/RabbitMQ/NATS/Redis/Kafka). The `nest-advanced` skill is intentionally orientation-level; deep dives defer to NestJS docs.

Smoke testing (end-to-end pipeline run on a real NestJS fixture) is deferred to a follow-up PR — verification in v0.0.1 is limited to schema/structure validation via `/sdlc:list-stacks`, `/sdlc:doctor`, and GitHub Actions lint.
