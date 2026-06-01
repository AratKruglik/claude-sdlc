---
stack: inertia-react
priority: 175
aspects: [frontend]
detect:
  all:
    - file_exists: package.json
    - file_contains:
        path: package.json
        pattern: '"@inertiajs/(inertia-)?react"'
---

# Inertia + React Stack Profile

Inertia.js + React frontend stack provider. Detects `@inertiajs/react` (modern) or `@inertiajs/inertia-react` (legacy) adapter. Priority=175 — higher than generic `react-plugin` (150), so this profile wins the frontend aspect for any Inertia+React project. Generic `react-plugin` is still installed (convention skills come from it), but loses the frontend aspect to this profile.

Composes naturally with `laravel-plugin` (backend+database). `laravel-architect` writes backend + documents the Inertia props contract; `inertia-react-architect` then implements the React pages consuming that contract.

## Tie behavior

If both `@inertiajs/vue3` and `@inertiajs/react` are present (vue↔react migration) — both Inertia profiles match at priority 175 → orchestrator HALT with tie error → use `--stack=inertia-vue` or `--stack=inertia-react`.

## Agents per phase

- business_analysis: business-analyst        # core agent
- development: inertia-react-architect       # ⚡ Inertia+React specific
- qa: qa-engineer                            # core agent
- security: security-analyst                 # core agent
- documentation: document-writer             # core agent

## Convention skills to apply

- react-plugin:react-conventions
- react-plugin:react-state-management
- react-plugin:react-forms
- react-plugin:react-testing
- js-foundation:typescript-patterns
- js-foundation:npm-patterns

Note: `react-plugin:react-routing` is intentionally excluded — Inertia does not use a client-side React Router. Navigation is server-driven via `<Link>` and `router` from `@inertiajs/react`.

## Extra phases

(none)

## Phase prompts injection

For development phase, inject:
  "Inertia + React. This is NOT a React SPA — there is no client-side router. Navigation is server-driven.
   Key Inertia primitives (all from `@inertiajs/react`, NOT react-router-dom):
   - `useForm(fields)` — reactive form helper with `.post()`, `.put()`, `.delete()`, `.data`, `.setData('field', value)`, `.errors`, `.processing`.
   - `usePage<PageProps>()` — access shared props (auth.user, flash, etc.) from `HandleInertiaRequests`.
   - `<Link href='...' method='...' as='button'>` — Inertia link, prevents full-page reload.
   - `router.visit()`, `router.post()` for programmatic navigation.
   Pages in `resources/js/Pages/`, layouts via per-component pattern: `Component.layout = (page) => <AppLayout>{page}</AppLayout>`.
   Props are typed from the Laravel controller: read the props contract in `docs/plans/{task_slug}/02-development-backend.md` (left by laravel-architect).
   TypeScript: `import type { PageProps } from '@inertiajs/core'`; page component props extend `PageProps`.
   Detect UI library (use what's installed; do not introduce new): shadcn/ui, MUI, Ant Design, Chakra UI, Radix UI.
   Apply skills: react-plugin:react-conventions, react-plugin:react-state-management, react-plugin:react-forms, js-foundation:typescript-patterns, js-foundation:npm-patterns.
   If `superpowers` is available (no `superpowers_unavailable` flag in CONTEXT), invoke superpowers:verification-before-completion before returning."

For qa phase, inject:
  "Inertia+React testing strategy:
   - Vitest + React Testing Library (@testing-library/react) for unit/component tests.
   - For Inertia pages: mock `usePage()` return value to supply shared props; mock `useForm()` or test via full page mount with a custom wrapper.
   - Do NOT use react-router helpers (MemoryRouter, etc.) — pages do not use client-side routing.
   - Playwright or Laravel Dusk for browser/e2e testing across the Inertia layer.
   Apply skill: react-plugin:react-testing."

For security phase, inject:
  "Inertia+React security checks:
   - `dangerouslySetInnerHTML`: any usage MUST be paired with sanitization (DOMPurify or equivalent). Flag every occurrence.
   - Auth tokens: NEVER in localStorage / sessionStorage. Inertia passes auth user via shared props (usePage) from the Laravel session — this is correct.
   - CSRF: Inertia automatically includes X-XSRF-TOKEN header from the cookie on non-GET requests — do not disable it.
   - Env vars: Vite `import.meta.env.VITE_*` is PUBLIC (bundled). Never put secrets there.
   - Open redirects: validate any URL from Inertia redirect params before navigating."

## Pre-phase commands

(none)

## Post-pipeline checks

Plugin auto-detects package manager from lockfile (`pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, otherwise npm). React projects use `tsc` (not `vue-tsc`).

- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm test; elif [ -f yarn.lock ]; then yarn test; else npm test; fi'
- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm run lint 2>/dev/null || true; elif [ -f yarn.lock ]; then yarn run lint 2>/dev/null || true; else npm run lint --if-present; fi'
- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm run build 2>/dev/null || true; elif [ -f yarn.lock ]; then yarn build 2>/dev/null || true; else npm run build --if-present; fi'
- npx --no-install tsc --noEmit
