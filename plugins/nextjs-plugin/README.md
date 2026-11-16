# nextjs-plugin

Next.js full-stack React framework stack provider for the [SDLC marketplace](../../README.md).

Adds a Next.js-specific implementation agent (`nextjs-architect`) and 5 skills covering App Router conventions, Server Component / Client Component boundaries, data fetching + caching, routing primitives, and testing strategies. Activates automatically on projects with `next` in `package.json`. Multi-aspect plugin — claims **both** `backend` and `frontend` aspects (priority=250, highest among full-stack frameworks except React Native's frontend-only 300).

## What this plugin adds

| Component | Purpose |
|---|---|
| `stack.md` | Stack profile, priority=250, aspects=[backend, frontend]. |
| `agents/nextjs-architect.md` | Sonnet-tier developer for Next.js with an Opus planning pass. Replaces `developer` / `node-architect` / `nest-architect` / `react-architect` for Next.js projects. |
| `skills/nextjs-conventions/` | App Router file conventions (page/layout/loading/error/route), metadata, image/font optimization, next.config.js patterns. |
| `skills/server-component-patterns/` | RSC vs Client boundary, "use client" / "use server" directives, Server Actions (auth + validation + revalidation), data passing across the boundary. |
| `skills/nextjs-data-fetching/` | Native fetch caching, ISR/SSG/SSR per-route, `unstable_cache`, `generateStaticParams`, `revalidatePath` / `updateTag` / `revalidateTag`, Route Handlers, edge vs node runtime. |
| `skills/nextjs-routing/` | Dynamic segments, route groups, parallel routes, intercepting routes, proxy (`middleware.ts` on Next ≤15), Link/useRouter, redirects/rewrites. |
| `skills/nextjs-testing/` | Vitest + RTL for Client Components, Playwright for RSC integration and e2e, Server Action and Route Handler unit tests, msw for network mocks. |
| `hooks/hooks.json` | Auto-format TS/JS/MDX via Prettier + ESLint after Edit/Write (silent if not installed). |

## What it does NOT cover

- **Plain Node.js backend** without Next.js — `nodejs-plugin` handles those.
- **NestJS-specific projects** — `nestjs-plugin` (separate package.json in monorepos).
- **React SPA without Next.js** — `react-plugin` (frontend-only aspect).
- **React Native** — `react-native-plugin` (mobile aspect).
- **Pages Router-only patterns** beyond brief acknowledgment — App Router is the modern default; Pages-only patterns are mostly legacy.
- **Vercel-specific deployment** — pipeline doesn't run `vercel deploy`. The plugin focuses on code, not deploy.

## Cross-plugin skill reuse

`nextjs-plugin` declares `dependencies: ["sdlc", "js-foundation"]` in `plugin.json` — Claude Code auto-installs `js-foundation` when you install this. The stack profile references skills from both plugins in `convention_skills`:

- `js-foundation:typescript-patterns` — strict TypeScript discipline.
- `js-foundation:npm-patterns` — package manager detection, semver, lockfile hygiene.
- `nextjs-plugin:nextjs-conventions` — file-based routing primitives, metadata, configuration.
- `nextjs-plugin:server-component-patterns` — RSC/Client boundary discipline.
- `nextjs-plugin:nextjs-data-fetching` — caching, revalidation, route handlers.
- `nextjs-plugin:nextjs-routing` — dynamic segments, groups, parallel/intercepting routes.
- `nextjs-plugin:nextjs-testing` — testing strategies per layer.

## Installation

```
/plugin marketplace add AratKruglik/claude-sdlc
/plugin install nextjs-plugin@sdlc-marketplace
```

`sdlc` core and `js-foundation` install automatically as dependencies.

## Usage

On any Next.js project, the plugin activates automatically:

```
/sdlc:start "Add /dashboard page with server-rendered user list and client-side filter"
```

The orchestrator detects the Next.js stack profile, claims both `backend` and `frontend` aspects, and dispatches `nextjs-architect` for the development phase. All other phases (BA, QA, Security, Docs) use the core agents.

## Verification

```
/sdlc:list-stacks
```

Should show `nextjs priority=250` with active match (backend + frontend) on a Next.js project.

```
/sdlc:doctor
```

Confirms 3 plugins installed (sdlc + js-foundation + nextjs-plugin), no degraded mode warnings.

## Composition with other plugins

Multi-aspect ownership means `nextjs-plugin` typically wins both `backend` and `frontend` aspects on Next.js projects, leaving no slot for other backend or frontend plugins on the same `package.json`.

For NestJS + Next.js MONOREPOS with separate `package.json` per app:
- In `apps/api/` (Nest backend) — only nestjs-plugin detects.
- In `apps/web/` (Next frontend) — only nextjs-plugin detects.
- The orchestrator runs per-cwd, so each app gets the right architect.

For SINGLE-`package.json` mixed projects (rare): nextjs-plugin wins both aspects via priority. Use `--stack=NAME` override at `/sdlc:start` if that's wrong for your setup.

## Package manager detection

`post_pipeline_checks` auto-detect from lockfile:

| Lockfile present | Runner used |
|---|---|
| `pnpm-lock.yaml` | `pnpm test`, `pnpm run lint`, `pnpm run build` |
| `yarn.lock` | `yarn test`, `yarn run lint`, `yarn build` |
| (default) | `npm test`, `npm run lint --if-present`, `npm run build` |

`npm run build` is the most valuable single check — Next.js's build runs compile + type-check (linting was removed from `next build` in 16; run the project's lint script separately) and prerendering. It catches RSC violations, missing exports, type errors, and most runtime issues at compile time. Plus `npx --no-install tsc --noEmit` runs as a safety net.

The `nextjs-architect` agent applies the same detection for any install/script invocations during development.

## Local override

To customize per-project (e.g., monorepo runners like Nx/Turborepo, custom test scripts, skip security phase if external SAST handles it), create `.claude/sdlc.local.yaml` in the project root and set `post_pipeline_checks` explicitly. Recognized top-level keys: `post_pipeline_checks` (replaces plugin defaults), `phase_command_overrides` (passed as context to agents), `extra_phase_prompts` (appends per-phase guidance), `skip_phases`, `convention_skills_extra`.

## Coverage scope (v0.0.1)

This plugin covers the **full Next.js surface** for App Router projects — file conventions, RSC/Client boundary, data fetching with all caching modes, routing primitives including parallel/intercepting routes, proxy, and testing across all layers. The agent handles BOTH backend (Route Handlers, Server Actions, proxy) AND frontend (RSC pages, Client Components) within one feature implementation.

Pages Router is acknowledged but not deeply documented — App Router is the modern default and Pages is mostly legacy. New code should be App Router.

Smoke testing (end-to-end pipeline run on a real Next.js fixture) is deferred to a follow-up PR — verification in v0.0.1 is limited to schema/structure validation via `/sdlc:list-stacks`, `/sdlc:doctor`, and GitHub Actions lint.
