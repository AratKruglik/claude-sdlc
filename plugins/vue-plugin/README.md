# vue-plugin

Vue 3 SPA frontend stack provider for the [SDLC marketplace](../../README.md).

Adds a Vue-specific implementation agent (`vue-architect`) and 5 skills covering SFC conventions, state management, routing, forms, and testing. Activates automatically on projects with `vue` in `package.json`. Priority=150 — equal to `react-plugin` (Vue + React migration projects produce a tie that the orchestrator surfaces as an error → user picks via `--stack=NAME`).

**Vue 3 primary**, Vue 2 fallback notes for legacy projects. Nuxt projects also match — without the future `nuxt-plugin`, this plugin is acceptable fallback (Nuxt has `vue` in deps).

## What this plugin adds

| Component | Purpose |
|---|---|
| `stack.md` | Stack profile, priority=150, aspects=[frontend]. |
| `agents/vue-architect.md` | Developer for Vue 3 SPAs (Sonnet implement pass, Opus plan pass). Replaces vanilla `developer` for Vue projects without Nuxt-specific framework plugin. |
| `skills/vue-conventions/` | SFC structure, `<script setup>`, Composition API, props/emits/slots typing, `defineModel`, composables, lifecycle, UI library detection (Vuetify/Quasar/PrimeVue/Naive UI/Element Plus/shadcn-vue). Vue 2 fallback section. |
| `skills/vue-state-management/` | Pinia (Setup syntax preferred), `provide`/`inject` with `InjectionKey<T>`, TanStack Query Vue, VueUse `useStorage`, URL state via vue-router. Vuex pointer for legacy. |
| `skills/vue-routing/` | Vue Router v4/v5, dynamic/nested routes, navigation guards, lazy loading, typed routes, file-based routing (built into v5; `unplugin-vue-router` on v4), v3 pointer. |
| `skills/vue-forms/` | Native v-model + HTML5, vee-validate + zod (recommended), `defineModel` for custom inputs, field arrays, multi-step wizards, async validation. |
| `skills/vue-testing/` | Vitest + `@vue/test-utils`, mount vs shallowMount, Pinia testing via `createTestingPinia`, msw for network mocks, Cypress component testing, Playwright e2e. |
| `hooks/hooks.json` | Auto-format `.vue` / TS / JS via Prettier + ESLint after Edit/Write (silent if not installed). |

## What it does NOT cover

- **Nuxt** — out of scope; future `nuxt-plugin` will own server routes, layouts, server components, file-based routing.
- **React** — `react-plugin` (different reactivity model).
- **Next.js** — `nextjs-plugin`.
- **React Native** — `react-native-plugin`.
- **Backend code** — `nodejs-plugin` / `nestjs-plugin`.
- **SSR / SSG patterns** — out of scope for SPA-only Vue plugin (Nuxt territory).
- **Specific UI library opinions** — agent detects Vuetify/Quasar/PrimeVue/Naive UI/Element Plus/shadcn-vue and mirrors patterns; this plugin doesn't bundle a UI choice.

## Cross-plugin skill reuse

`vue-plugin` declares `dependencies: ["sdlc", "js-foundation"]` in `plugin.json` — Claude Code auto-installs `js-foundation` when you install this. The stack profile references skills from both plugins:

- `js-foundation:typescript-patterns` — strict TypeScript discipline.
- `js-foundation:npm-patterns` — package manager detection, semver, lockfile hygiene.
- `vue-plugin:vue-conventions` — SFC, Composition API, lifecycle.
- `vue-plugin:vue-state-management` — Pinia, provide/inject, vue-query.
- `vue-plugin:vue-routing` — vue-router v4.
- `vue-plugin:vue-forms` — vee-validate + zod patterns.
- `vue-plugin:vue-testing` — Vitest + test-utils.

## Installation

```
/plugin marketplace add AratKruglik/claude-sdlc
/plugin install vue-plugin@sdlc-marketplace
```

`sdlc` core and `js-foundation` install automatically as dependencies.

## Usage

On any Vue 3 SPA project, the plugin activates automatically:

```
/sdlc:start "Add a paginated user list with filter and sort"
```

The orchestrator detects the Vue stack profile, claims the `frontend` aspect, and dispatches `vue-architect` for the development phase. All other phases (BA, QA, Security, Docs) use the core agents.

## Verification

```
/sdlc:list-stacks
```

Should show `vue priority=150` with active match (frontend) on a Vue 3 SPA project.

```
/sdlc:doctor
```

Confirms 7 plugins installed (sdlc + nodejs + nestjs + nextjs + react + react-native + vue), no degraded mode warnings.

## Composition with backend plugins

`vue-plugin` is frontend-only — claims `frontend` aspect. On full-stack projects (single repo OR monorepo), the orchestrator picks per-aspect winners:

- Node.js + Vue → `node-architect` (backend) + `vue-architect` (frontend).
- NestJS + Vue → `nest-architect` (backend, database) + `vue-architect` (frontend).
- Laravel + Vue (Inertia or API) → `laravel-architect` (backend, database) + `vue-architect` (frontend) — once `laravel-plugin` ships.

The development phase fans out — runs once per relevant aspect, in canonical order: `database → backend → frontend → testing`.

## Detection edge cases

| Condition | Outcome |
|---|---|
| `package.json` has `next` | `nextjs-plugin` (250) wins both backend AND frontend. `vue-plugin` skipped. |
| `package.json` has `react-native` | `react-native-plugin` (300) wins frontend. `vue-plugin` skipped. |
| `package.json` has `nuxt` | `vue-plugin` matches (Nuxt has `vue`). Future `nuxt-plugin` (Phase 11+, priority=250) will override. Until then, vue-plugin is acceptable fallback. |
| `package.json` has both `vue` AND `react` | Both plugins detect at priority 150 → orchestrator HALTS with tie error. Use `--stack=vue` or `--stack=react` to disambiguate. |
| Vue 2 (`"vue": "^2"`) | Plugin matches. Agent flags Vue 2 in DECISIONS and applies Options API + Vuex 3 fallback patterns. |
| Pure Vue 3 SPA | `vue-plugin` wins frontend, composes with backend plugin per project. |

## Vue 3 vs Vue 2

The plugin's regex match doesn't distinguish version (`"vue"\s*:` matches both). The agent inspects the version at runtime:

- **Vue 3** (default): `<script setup lang="ts">`, Composition API, Pinia, vue-router v4, `defineModel`.
- **Vue 2** (legacy fallback): Options API (`data`/`computed`/`methods`), Vuex 3, vue-router v3, no `<script setup>`. Migrating to Vue 3 only when BA spec asks.

Most patterns differ between versions; the agent picks the right ones per project.

## Package manager detection

`post_pipeline_checks` auto-detect from lockfile:

| Lockfile present | Runner used |
|---|---|
| `pnpm-lock.yaml` | `pnpm test`, `pnpm run lint`, `pnpm run build` |
| `yarn.lock` | `yarn test`, `yarn run lint`, `yarn build` |
| (default) | `npm test`, `npm run lint --if-present`, `npm run build --if-present` |

Plus `npx --no-install vue-tsc --noEmit` (with `tsc` fallback) — `vue-tsc` understands `.vue` SFC types, `tsc` does not.

The `vue-architect` agent applies the same detection for any install/script invocations during development.

## Local override

To customize per-project (e.g., Nx/Turborepo monorepo runners, custom test scripts, skip security phase if external SAST handles it), create `.claude/sdlc.local.yaml` in the project root and set `post_pipeline_checks` explicitly. Recognized top-level keys: `post_pipeline_checks` (replaces plugin defaults), `phase_command_overrides` (passed as context to agents), `extra_phase_prompts` (appends per-phase guidance), `skip_phases`, `convention_skills_extra`.

## Coverage scope (v0.0.1)

This plugin covers the **full Vue 3 SPA surface** — SFC structure, all reactivity primitives, multiple state libraries (Pinia, vue-query, VueUse, provide/inject), Vue Router v4 with all route patterns, vee-validate forms, Vitest + @vue/test-utils + Cypress + Playwright testing.

**Vue 2** is fallback-noted — when detected, agent applies Options API + Vuex 3 patterns. Not deep coverage; just enough to maintain legacy code without forcing migration.

**UI libraries** are detection-only — agent identifies Vuetify/Quasar/PrimeVue/Naive UI/Element Plus/shadcn-vue (`reka-ui`, or legacy `radix-vue`) and mirrors existing patterns. No opinionated UI choice.

**Nuxt** is out of scope — separate `nuxt-plugin` planned for Phase 11+ roadmap. Until then, Nuxt projects work via vue-plugin as fallback (sub-optimal for Nuxt-specific features like server routes, layouts, server components).

Smoke testing (end-to-end pipeline run on a real Vue 3 fixture) is deferred to a follow-up PR — verification in v0.0.1 is limited to schema/structure validation via `/sdlc:list-stacks`, `/sdlc:doctor`, and GitHub Actions lint.
