---
stack: inertia-vue
priority: 175
aspects: [frontend]
detect:
  all:
    - file_exists: package.json
    - file_contains:
        path: package.json
        pattern: '"@inertiajs/(inertia-)?vue3"'
---

# Inertia + Vue Stack Profile

Inertia.js + Vue 3 frontend stack provider. Detects `@inertiajs/vue3` (modern) or `@inertiajs/inertia-vue3` (legacy) adapter. Priority=175 — higher than generic `vue-plugin` (150), so this profile wins the frontend aspect for any Inertia+Vue project. Generic `vue-plugin` is still installed (convention skills come from it), but loses the frontend aspect to this profile.

Composes naturally with `laravel-plugin` (backend+database). `laravel-architect` writes backend + documents the Inertia props contract; `inertia-vue-architect` then implements the Vue pages consuming that contract.

## Tie behavior

If both `@inertiajs/vue3` and `@inertiajs/react` are present (vue↔react migration) — both Inertia profiles match at priority 175 → orchestrator HALT with tie error → use `--stack=inertia-vue` or `--stack=inertia-react`.

## Agents per phase

- business_analysis: business-analyst        # core agent
- development: inertia-vue-architect         # ⚡ Inertia+Vue specific
- qa: qa-engineer                            # core agent
- security: security-analyst                 # core agent
- documentation: document-writer             # core agent

## Convention skills to apply

- vue-plugin:vue-conventions
- vue-plugin:vue-state-management
- vue-plugin:vue-forms
- vue-plugin:vue-testing
- js-foundation:typescript-patterns
- js-foundation:npm-patterns

Note: `vue-plugin:vue-routing` is intentionally excluded — Inertia does not use a client-side Vue Router. Navigation is server-driven via `<Link>` and `router` from `@inertiajs/vue3`.

## Extra phases

(none)

## Phase prompts injection

For development phase, inject:
  "Inertia + Vue 3. This is NOT a Vue SPA — there is no client-side router. Navigation is server-driven.
   Key Inertia primitives (all from `@inertiajs/vue3`, NOT vue-router):
   - `useForm(fields)` — reactive form helper with `.post()`, `.put()`, `.delete()`, `.errors`, `.processing`.
   - `usePage()` — access shared props (auth.user, flash, etc.) from `HandleInertiaRequests`.
   - `<Link href='...' method='...' as='button'>` — Inertia link, prevents full-page reload.
   - `router.visit()`, `router.post()` for programmatic navigation.
   Pages in `resources/js/Pages/`, layouts in `resources/js/Layouts/`.
   Props are typed from the Laravel controller: read the props contract in `docs/plans/{task_slug}/02-development-backend.md` (left by laravel-architect).
   Detect Vue version from package.json: prefer `<script setup lang=\"ts\">` for Vue 3.
   Detect UI library (use what's installed; do not introduce new): Vuetify, Quasar, PrimeVue, Naive UI, Element Plus, shadcn-vue.
   Apply skills: vue-plugin:vue-conventions, vue-plugin:vue-state-management, vue-plugin:vue-forms, js-foundation:typescript-patterns, js-foundation:npm-patterns.
   If superpowers is available, invoke superpowers:verification-before-completion before returning."

For qa phase, inject:
  "Inertia+Vue testing strategy:
   - Vitest + @vue/test-utils for unit/component tests.
   - For Inertia pages: mock `usePage()` return value to supply shared props; mock `useForm()` or test via full page mount.
   - Do NOT use vue-router helpers — pages do not use client-side routing.
   - Playwright or Laravel Dusk for browser/e2e testing across the Inertia layer.
   Apply skill: vue-plugin:vue-testing."

For security phase, inject:
  "Inertia+Vue security checks:
   - `v-html`: any usage MUST be paired with sanitization (DOMPurify).
   - Auth tokens: NEVER in localStorage. Inertia passes auth user via shared props (usePage) from the Laravel session — this is correct.
   - CSRF: Inertia automatically includes X-XSRF-TOKEN header from the cookie on non-GET requests — do not disable it.
   - Env vars: Vite `import.meta.env.VITE_*` is PUBLIC (bundled). Never put secrets there.
   - Open redirects: validate any URL from Inertia redirect params before navigating."

## Pre-phase commands

(none)

## Post-pipeline checks

Plugin auto-detects package manager from lockfile (`pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, otherwise npm). `vue-tsc` understands `.vue` SFC TypeScript; falls back to plain `tsc` if not installed.

- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm test; elif [ -f yarn.lock ]; then yarn test; else npm test; fi'
- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm run lint 2>/dev/null || true; elif [ -f yarn.lock ]; then yarn run lint 2>/dev/null || true; else npm run lint --if-present; fi'
- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm run build 2>/dev/null || true; elif [ -f yarn.lock ]; then yarn build 2>/dev/null || true; else npm run build --if-present; fi'
- sh -c 'npx --no-install vue-tsc --noEmit 2>/dev/null || npx --no-install tsc --noEmit'
