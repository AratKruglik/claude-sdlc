# angular-plugin

Angular 18-22 SPA frontend stack provider for the [SDLC marketplace](../../README.md).

Adds an Angular-specific implementation agent (`angular-architect`) and 5 skills covering modern conventions (standalone + NgModule equally, signals, new control flow), state management (signals + services + NgRx variants), Angular Router with functional guards, typed Reactive Forms, and TestBed-based testing. Activates automatically on projects with `@angular/core` in `package.json`. Priority=200 — opinionated full framework (like NestJS).

**Modern era focus** (signal-first, standalone-first, control flow `@if`/`@for`/`@switch`) with **NgModule legacy fallback** for projects that haven't migrated. Angular Universal (SSR) is pointer-only — SPA-focused plugin.

## What this plugin adds

| Component | Purpose |
|---|---|
| `stack.md` | Stack profile, priority=200, aspects=[frontend]. |
| `agents/angular-architect.md` | Developer for Angular SPAs (Sonnet implement pass, Opus plan pass). Replaces vanilla `developer` for Angular projects. |
| `skills/angular-conventions/` | Standalone components + NgModule fallback, project structure, control flow, decorators, DI via `inject()`, lifecycle, pipes, Angular Universal pointer. |
| `skills/angular-state-and-rx/` | Signals (signal/computed/effect), services-as-state, NgRx Store + Effects + Selectors, NgRx Component Store, NgRx Signals, RxJS essentials, signal/observable interop. |
| `skills/angular-routing/` | Angular Router, functional guards (canActivate as function), lazy loading, resolvers, typed params via signals/observables, route data and meta. |
| `skills/angular-forms/` | Reactive Forms (typed FormGroup/FormControl, FormBuilder, custom + async validators, FormArray, multi-step), Template-driven fallback, server error mapping. |
| `skills/angular-testing/` | TestBed, component harnesses (@angular/cdk/testing), Vitest / Karma+Jasmine / Jest detection, Angular Testing Library, HttpTestingController, NgRx Effects testing, Cypress/Playwright e2e. |
| `hooks/hooks.json` | Auto-format TS/HTML/SCSS/CSS via Prettier + ESLint after Edit/Write (silent if not installed). |

## What it does NOT cover

- **Angular Universal (SSR/SSG)** — pointer only. SPA-focused plugin. For full SSR, separate plugin or feature-specific spec.
- **Ionic Angular** — different ecosystem (mobile-focused).
- **Older Angular (<17)** — patterns mentioned but plugin targets 18-22 modern era.
- **AngularJS (1.x)** — completely different framework, out of scope.
- **React / Vue / etc.** — separate framework plugins.
- **Backend code** — `nodejs-plugin` / `nestjs-plugin`.
- **Specific UI library opinions** — agent detects Angular Material / PrimeNG / NG-ZORRO / Taiga UI / NG-Bootstrap and mirrors patterns; plugin doesn't bundle a UI choice.

## Cross-plugin skill reuse

`angular-plugin` declares `dependencies: ["sdlc", "js-foundation"]` in `plugin.json` — Claude Code auto-installs `js-foundation` when you install this. The stack profile references skills from both plugins:

- `js-foundation:typescript-patterns` — strict TypeScript discipline (stack-agnostic).
- `js-foundation:npm-patterns` — package manager detection, semver, lockfile hygiene.
- `angular-plugin:angular-conventions` — components, decorators, control flow, DI.
- `angular-plugin:angular-state-and-rx` — signals + services + NgRx + RxJS.
- `angular-plugin:angular-routing` — Angular Router + functional guards.
- `angular-plugin:angular-forms` — Reactive Forms + validators.
- `angular-plugin:angular-testing` — TestBed + harnesses + Angular Testing Library.

## Installation

```
/plugin marketplace add AratKruglik/claude-sdlc
/plugin install angular-plugin@sdlc-marketplace
```

`sdlc` core and `js-foundation` install automatically as dependencies.

## Usage

On any Angular project, the plugin activates automatically:

```
/sdlc:start "Add a paginated user list with filter and sort"
```

The orchestrator detects the Angular stack profile, claims the `frontend` aspect, and dispatches `angular-architect` for the development phase. All other phases (BA, QA, Security, Docs) use the core agents.

## Verification

```
/sdlc:list-stacks
```

Should show `angular priority=200` with active match (frontend) on an Angular project.

```
/sdlc:doctor
```

Confirms 9 plugins installed (sdlc + js-foundation + nodejs + nestjs + nextjs + react + react-native + vue + angular), no degraded mode warnings.

## Composition with backend plugins

`angular-plugin` is frontend-only — claims `frontend` aspect. On full-stack projects (single repo OR monorepo), the orchestrator picks per-aspect winners:

- Node.js + Angular → `node-architect` (backend) + `angular-architect` (frontend).
- NestJS + Angular → `nest-architect` (backend, database) + `angular-architect` (frontend).
- Laravel + Angular → `laravel-architect` (backend, database) + `angular-architect` (frontend) — once `laravel-plugin` ships.

The development phase fans out — runs once per relevant aspect, in canonical order: `database → backend → frontend → testing`.

## Detection edge cases

| Condition | Outcome |
|---|---|
| `package.json` has `@angular/core` | `angular-plugin` (200) wins frontend. |
| `package.json` has `@angular/core` + `react` | Extremely rare. `angular-plugin` (200) wins via priority over `react-plugin` (150). Use `--stack=react` to override if Angular is being phased out. |
| `package.json` has `@angular/ssr` or `@nguniversal/*` | Plugin matches; agent flags Angular Universal in DECISIONS but doesn't deeply support SSR (pointer-only in this plugin). |
| `package.json` has `@ionic/angular` | Plugin matches (Ionic uses Angular). Agent detects Ionic-specific patterns aren't covered; flags in BLOCKERS. Future ionic-plugin out of roadmap. |
| Angular <17 (`@angular/core: ^16` etc.) | Plugin matches. Agent applies legacy NgModule patterns (no signals, no `@if`/`@for`, no functional guards in some cases). |

## Standalone vs NgModule detection

Plugin's regex match doesn't distinguish style. Agent inspects at runtime:

- **Standalone-first** (Angular 17+ default): `bootstrapApplication(AppComponent, { providers: [...] })` in `main.ts`, NO `*.module.ts` files (or only `app-routing.module.ts`).
- **NgModule legacy**: `platformBrowserDynamic().bootstrapModule(AppModule)` + `app.module.ts` exists.
- **Mixed/migrating**: both bootstrap calls or partial migration. Agent mirrors per-area, prefers standalone for new code.

For new code in mixed projects, prefer standalone unless team has a strict consistency rule.

## Package manager detection

`post_pipeline_checks` auto-detect from lockfile:

| Lockfile present | Runner used |
|---|---|
| `pnpm-lock.yaml` | `pnpm test --watch=false`, `pnpm run lint`, `pnpm run build` |
| `yarn.lock` | `yarn test --watch=false`, `yarn run lint`, `yarn build` |
| (default) | `npm test -- --watch=false`, `npm run lint --if-present`, `npm run build` |

NOTE: the SubagentStop hook also runs `tsc --noEmit -p tsconfig.json` as a quick TS-only check, but Angular templates are not pure TS (and on the CLI's solution-style `tsconfig.json` it checks nothing). `ng build` (Angular Compiler) does AOT compilation + template type-check + DI validation, the most valuable single check. `--watch=false` flag prevents `ng test` from hanging in watch mode.

The `angular-architect` agent applies the same detection for any install/script invocations during development.

## Local override

To customize per-project (e.g., Nx/Turborepo monorepo runners, Jest or Karma instead of Vitest, custom builders), create `.claude/sdlc.local.yaml` in the project root and set `post_pipeline_checks` explicitly. Recognized top-level keys: `post_pipeline_checks` (replaces plugin defaults), `phase_command_overrides` (passed as context to agents), `extra_phase_prompts` (appends per-phase guidance), `skip_phases`, `convention_skills_extra`.

## Coverage scope (v0.0.1)

This plugin covers the **full Angular 18-22 SPA surface**:
- Standalone components + NgModule equally — both styles supported.
- Signals + services + all NgRx variants (Store, Component Store, Signals).
- Reactive Forms (typed) + Template-driven fallback.
- Angular Router with functional guards, resolvers, typed params, lazy loading.
- TestBed + component harnesses + Angular Testing Library + Cypress/Playwright e2e.

**Angular Universal** (SSR/SSG) is pointer-only — SPA-focused plugin. Real SSR projects need separate spec or follow-up plugin.

**Older Angular versions (<17)** — agent applies legacy NgModule + non-signal patterns when detected, but plugin targets the modern era.

**UI libraries** are detection-only — agent identifies Angular Material, PrimeNG, NG-ZORRO, Taiga UI, NG-Bootstrap and mirrors patterns. No opinionated UI choice.

Smoke testing (end-to-end pipeline run on a real Angular fixture) is deferred to a follow-up PR — verification in v0.0.1 is limited to schema/structure validation via `/sdlc:list-stacks`, `/sdlc:doctor`, and GitHub Actions lint.
