# react-plugin

React SPA frontend stack provider for the [SDLC marketplace](../../README.md).

Adds a React-specific implementation agent (`react-architect`) and 5 skills covering component conventions, state management, routing, forms, and testing. Activates automatically on projects with `react` in `package.json`. Loses to higher-priority frameworks (`nextjs-plugin` 250, `react-native-plugin` 300) on their respective project types — composes cleanly via aspect resolution with backend plugins (`nodejs-plugin`, `nestjs-plugin`, `laravel-plugin`).

## What this plugin adds

| Component | Purpose |
|---|---|
| `stack.md` | Stack profile, priority=150, aspects=[frontend]. |
| `agents/react-architect.md` | Developer for React SPAs (Sonnet implement pass, Opus plan pass). Replaces vanilla `developer` for React projects without Next.js / RN. |
| `skills/react-conventions/` | Component structure, hooks rules, file naming, composition, performance, effects discipline. |
| `skills/react-state-management/` | useState/useReducer, Context, Zustand, Jotai, Redux Toolkit, TanStack Query, SWR — decision tree. |
| `skills/react-routing/` | React Router v6/v7, TanStack Router, wouter, lazy loading, protected routes, typed params. |
| `skills/react-forms/` | react-hook-form + zod, Formik, TanStack Form, controlled vs uncontrolled, field arrays, multi-step wizards. |
| `skills/react-testing/` | RTL + Vitest/Jest, msw for network mocks, Playwright/Cypress for e2e, hook testing via renderHook. |
| `hooks/hooks.json` | Auto-format TS/JS/JSX/TSX via Prettier + ESLint after Edit/Write (silent if not installed). |

## What it does NOT cover

- **Next.js** — `nextjs-plugin` (multi-aspect, owns both backend and frontend).
- **React Native** — `react-native-plugin` (mobile aspect).
- **Vue** — `vue-plugin` (alt frontend).
- **Backend code** — `nodejs-plugin` / `nestjs-plugin` for the backend slot in full-stack apps.
- **Server-side rendering** — pure React SPAs only. SSR is `nextjs-plugin` territory.
- **Specific UI libraries** (shadcn / MUI / Mantine / etc.) — the agent detects what's installed and mirrors patterns; this plugin doesn't bundle UI.

## Cross-plugin skill reuse

`react-plugin` declares `dependencies: ["sdlc", "js-foundation"]` in `plugin.json` — Claude Code auto-installs `js-foundation` when you install this. The stack profile references skills from both plugins in `convention_skills`:

- `js-foundation:typescript-patterns` — strict TypeScript discipline.
- `js-foundation:npm-patterns` — package manager detection, semver, lockfile hygiene.
- `react-plugin:react-conventions` — component patterns, hooks, file naming.
- `react-plugin:react-state-management` — state lib decision tree.
- `react-plugin:react-routing` — routing patterns.
- `react-plugin:react-forms` — form patterns.
- `react-plugin:react-testing` — testing strategies.

## Installation

```
/plugin marketplace add AratKruglik/claude-sdlc
/plugin install react-plugin@sdlc-marketplace
```

`sdlc` core and `js-foundation` install automatically as dependencies.

## Usage

On any React SPA project, the plugin activates automatically:

```
/sdlc:start "Add a paginated user list with filter and sort"
```

The orchestrator detects the React stack profile, claims the `frontend` aspect, and dispatches `react-architect` for the development phase. All other phases (BA, QA, Security, Docs) use the core agents.

## Verification

```
/sdlc:list-stacks
```

Should show `react priority=150` with active match (frontend) on a React SPA project. On Next.js / RN projects, `react` shows up but loses to higher-priority plugins.

```
/sdlc:doctor
```

Confirms 5 plugins installed (sdlc + nodejs-plugin + nestjs-plugin + nextjs-plugin + react-plugin), no degraded mode warnings.

## Composition with backend plugins

`react-plugin` is frontend-only — it claims `frontend` aspect. On full-stack projects (single repo OR monorepo), the orchestrator picks per-aspect winners:

- Node.js + React → `node-architect` (backend) + `react-architect` (frontend).
- NestJS + React → `nest-architect` (backend, database) + `react-architect` (frontend).
- Laravel + React → `laravel-architect` (backend, database) + `react-architect` (frontend) — once `laravel-plugin` ships.

The development phase fans out — runs once per relevant aspect, in canonical order: `database → backend → frontend → testing`.

## Detection edge cases

| Condition | Outcome |
|---|---|
| `package.json` has `next` | `nextjs-plugin` (250) wins both backend AND frontend. `react-plugin` skipped. |
| `package.json` has `react-native` | `react-native-plugin` (300) wins frontend. `react-plugin` skipped. |
| `package.json` has both `react` AND `vue` | Both detect at priority 150 → orchestrator HALTS with tie error. Use `--stack=react` or `--stack=vue` to disambiguate. |
| Pure React SPA | `react-plugin` wins frontend, composes with backend plugin per project. |

## Package manager detection

`post_pipeline_checks` auto-detect from lockfile:

| Lockfile present | Runner used |
|---|---|
| `pnpm-lock.yaml` | `pnpm test`, `pnpm run lint`, `pnpm run build` |
| `yarn.lock` | `yarn test`, `yarn run lint`, `yarn build` |
| (default) | `npm test`, `npm run lint --if-present`, `npm run build --if-present` |

Plus `npx --no-install tsc --noEmit` always runs as a type-check safety net.

The `react-architect` agent applies the same detection for any install/script invocations during development.

## Local override

To customize per-project (e.g., Nx/Turborepo monorepo runners, custom test scripts, skip security phase if external SAST handles it), create `.claude/sdlc.local.yaml` in the project root and set `post_pipeline_checks` explicitly. Recognized top-level keys: `post_pipeline_checks` (replaces plugin defaults), `phase_command_overrides` (passed as context to agents), `extra_phase_prompts` (appends per-phase guidance), `skip_phases`, `convention_skills_extra`.

## Coverage scope (v0.0.1)

This plugin covers the **full React SPA surface** — components, hooks, multiple state libraries (Zustand, Jotai, Redux Toolkit, TanStack Query, SWR, Context), multiple routing libraries (React Router, TanStack Router, wouter), multiple form libraries (react-hook-form, Formik, TanStack Form), and testing across all layers (unit + component + e2e).

The agent detects what's installed in the project and applies matching patterns — never imposes a single opinionated stack.

Smoke testing (end-to-end pipeline run on a real React fixture) is deferred to a follow-up PR — verification in v0.0.1 is limited to schema/structure validation via `/sdlc:list-stacks`, `/sdlc:doctor`, and GitHub Actions lint.
