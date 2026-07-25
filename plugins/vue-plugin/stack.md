---
stack: vue
priority: 150
aspects: [frontend]
detect:
  all:
    - file_exists: package.json
    - file_contains:
        path: package.json
        pattern: '"vue"\s*:'
---

# Vue Stack Profile

Vue 3 SPA frontend stack provider. Triggers when `package.json` contains `"vue"`. Priority=150 — equal to `react-plugin` (frontend tie on Vue+React migration projects → orchestrator HALT с error → use `--stack=NAME`).

**Vue 3 primary**, Vue 2 fallback notes for legacy projects. Nuxt projects also match (Nuxt has `vue` in deps); without `nuxt-plugin` (Phase 11+ roadmap) this plugin is acceptable fallback. Future `nuxt-plugin` priority=250 will override.

Composes naturally with backend plugins (nodejs / nestjs / laravel) on full-stack monorepos via aspect resolution.

## Agents per phase

- business_analysis: business-analyst        # core agent
- development: vue-architect                 # ⚡ Vue-specific
- qa: qa-engineer                            # core agent
- security: security-analyst                 # core agent
- documentation: document-writer             # core agent

## Convention skills to apply

- vue-plugin:vue-conventions
- vue-plugin:vue-state-management
- vue-plugin:vue-routing
- vue-plugin:vue-forms
- vue-plugin:vue-testing
- js-foundation:typescript-patterns
- js-foundation:npm-patterns
- frontend-design:frontend-design  # optional external; skipped automatically when absent

## Extra phases

(none)

## Phase prompts injection

For development phase, inject:
  "Vue SPA. Detect Vue version from package.json: \"vue\": \"^3\" → Vue 3 (modern, preferred); \"vue\": \"^2\" → Vue 2 (legacy fallback — flag in DECISIONS).
   Detect bundler: Vite (`vite.config.{ts,js}`) — modern default; Webpack/Vue CLI — legacy.
   Detect routing: `vue-router` v4 (Vue 3) or v3 (Vue 2).
   Detect state: `pinia` (Vue 3 default store), `vuex` (Vue 2 legacy — recommend Pinia for new code if Vue 3).
   Detect forms: `vee-validate` (most common), `@vueuse/core` for VueUse forms helpers, native v-model patterns.
   Detect validation: `zod`, `yup`, `valibot`.
   Detect UI library (use what's installed; do not introduce new): Vuetify, Quasar, PrimeVue, Naive UI, Element Plus, shadcn-vue (radix-vue), HeadlessUI Vue. Mirror its component import patterns.
   Detect styling: scoped <style scoped>, CSS Modules, Tailwind, UnoCSS.
   For Vue 3: prefer `<script setup lang=\"ts\">` over plain `<script>`. Composition API over Options API.
   `ref` for primitives AND objects (works everywhere, no destructure footgun); `reactive` only when team convention says so. Don't destructure `reactive()` — loses reactivity (use `toRefs()`).
   Composables under `src/composables/use*.ts`; return `{ refs, actions }` shape.
   Apply skills: vue-plugin:vue-conventions, vue-plugin:vue-state-management, vue-plugin:vue-routing, vue-plugin:vue-forms, js-foundation:typescript-patterns, js-foundation:npm-patterns.
   If superpowers is available, invoke superpowers:verification-before-completion before returning."

For qa phase, inject:
  "Vue testing strategy:
   - Vitest is the default for Vue 3 (Vite-native). Detect via `vitest` in devDeps.
   - `@vue/test-utils` provides `mount` (renders children real) and `shallowMount` (stubs children). Prefer mount; use shallowMount only for very large component trees.
   - `@testing-library/vue` is RTL-style API alternative — query by accessible name.
   - Test the public contract: props in, emitted events out, slot rendering. Don't test internal refs.
   - Pinia testing: `setActivePinia(createPinia())` in beforeEach. For mocked stores: `createTestingPinia({ initialState: {...} })` from `@pinia/testing`.
   - Composables: call directly inside `setup()` of a test component, OR use a `withSetup` helper.
   - msw for API mocks at network boundary.
   - Cypress component testing: in-browser, slower, more realistic — if installed.
   - Playwright e2e: same patterns as react. Webserver config in `playwright.config.ts`.
   - After state mutations, `await wrapper.vm.$nextTick()` or `await flushPromises()` before assertions.
   Apply skill: vue-plugin:vue-testing."

For security phase, inject:
  "Vue-specific security checks:
   - `v-html`: bypasses Vue's reactive escaping. Any usage MUST be paired with sanitization (DOMPurify). Flag every occurrence.
   - Auth tokens: NEVER in localStorage/sessionStorage (XSS-readable). Use httpOnly cookies (server-set) or in-memory (Pinia store reset on logout).
   - Env vars build-time: Vite exposes `import.meta.env.VITE_*` — PUBLIC by definition (bundled into JS shipped to browser). Never put secrets there.
   - SSR/SSG: out of scope for SPA-only vue-plugin. Nuxt territory.
   - Open redirects: validate URL from query params before `router.push(userInput)`.
   - Third-party scripts: prefer self-hosted; if external, verify SRI hash; CSP <script-src> allowlist.
   - File uploads: validate MIME + extension client-side as UX hint, server validates again.
   - Dependencies: run `npm audit` and address Critical/High."

## Pre-phase commands

(none)

## Post-pipeline checks

Plugin auto-detects package manager from lockfile (`pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, otherwise npm). `vue-tsc` understands `.vue` SFC TypeScript; falls back to plain `tsc` if not installed. Override per-project via `.claude/sdlc.local.yaml` `post_pipeline_checks` for monorepo runners (Nx, Turborepo).

- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm test; elif [ -f yarn.lock ]; then yarn test; else npm test; fi'
- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm run lint 2>/dev/null || true; elif [ -f yarn.lock ]; then yarn run lint 2>/dev/null || true; else npm run lint --if-present; fi'
- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm run build 2>/dev/null || true; elif [ -f yarn.lock ]; then yarn build 2>/dev/null || true; else npm run build --if-present; fi'
- sh -c 'npx --no-install vue-tsc --noEmit 2>/dev/null || npx --no-install tsc --noEmit'
