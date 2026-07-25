---
stack: react
priority: 150
aspects: [frontend]
detect:
  all:
    - file_exists: package.json
    - file_contains:
        path: package.json
        pattern: '"react"\s*:'
---

# React SPA Stack Profile

Standalone React SPA frontend. Triggers when `package.json` contains `"react"`. Priority=150 — loses to higher-priority frameworks that also have React in deps:
- `nextjs-plugin` (250) wins on Next.js projects.
- `react-native-plugin` (300) wins on React Native projects.

On a pure React SPA (Vite/CRA/Webpack/Parcel + react + react-dom, no next, no react-native), react-plugin wins frontend aspect via priority. Composes naturally with backend plugins (nodejs / nestjs / laravel) on full-stack monorepos via aspect resolution: backend goes to the matching backend plugin, frontend to react.

If `vue-plugin` AND `react-plugin` both match (gradual migration project) — both have priority 150 → orchestrator HALT with tie error. Use `--stack=NAME` override to pick one explicitly.

## Agents per phase

- business_analysis: business-analyst        # core agent
- development: react-architect               # ⚡ React-specific
- qa: qa-engineer                            # core agent; on full-stack runs (multiple active profiles) the orchestrator fans QA out per aspect, so this profile's QA pass covers only the frontend aspect with the React qa injection below
- security: security-analyst                 # core agent
- documentation: document-writer             # core agent

## Convention skills to apply

- react-plugin:react-conventions
- react-plugin:react-state-management
- react-plugin:react-routing
- react-plugin:react-forms
- react-plugin:react-testing
- js-foundation:typescript-patterns
- js-foundation:npm-patterns
- frontend-design:frontend-design  # optional external; skipped automatically when absent

## Extra phases

(none)

## Phase prompts injection

For development phase, inject:
  "React SPA. Detect bundler from devDependencies + config files: Vite (vite.config.{ts,js}), Webpack (webpack.config.js), Parcel (no config or package.json scripts), CRA (react-scripts in deps — legacy, mostly unmaintained as of 2024).
   Detect routing library: react-router-dom → React Router v6/v7 (most common); @tanstack/react-router → TanStack Router (typed, modern).
   Detect state management: Zustand (zustand), Jotai (jotai), Redux Toolkit (@reduxjs/toolkit), TanStack Query (@tanstack/react-query) for server state, Context API patterns. Match what's installed; never introduce a new state lib without BA approval.
   Detect form library: react-hook-form (most common), Formik (legacy but stable), TanStack Form (newer). Pair with zod or yup resolver for validation.
   File naming: PascalCase.tsx for components; useFooBar.ts for custom hooks; kebab-case.ts for non-component utilities. Mirror existing patterns.
   Component organization: src/components/{ui,features}/ OR per-feature colocation. Mirror the project.
   Hooks rules: only call from components or other hooks; declare deps explicitly in useEffect/useMemo/useCallback (or use exhaustive-deps lint).
   Apply skills: react-plugin:react-conventions, react-plugin:react-state-management, react-plugin:react-routing, react-plugin:react-forms, js-foundation:typescript-patterns, js-foundation:npm-patterns.
   If superpowers is available, invoke superpowers:verification-before-completion before returning."

For qa phase, inject:
  "React testing strategy:
   - Detect runner: Vitest (vitest in devDeps) — preferred for new projects; Jest (jest, jest-environment-jsdom) — common in CRA/legacy.
   - Use React Testing Library (@testing-library/react) for component tests. Query priority: getByRole > getByLabelText > getByText > getByTestId (last resort).
   - User events via @testing-library/user-event (not the lower-level fireEvent for interactions).
   - Mock network at the boundary with msw — never stub fetch directly per-test.
   - Test custom hooks via renderHook from @testing-library/react.
   - For e2e: detect Playwright (@playwright/test) or Cypress (cypress) and follow project patterns. Place under e2e/ or cypress/e2e/.
   Apply skill: react-plugin:react-testing."

For security phase, inject:
  "React-specific security checks:
   - XSS via dangerouslySetInnerHTML: any usage MUST be paired with sanitization (DOMPurify). Flag every occurrence.
   - Auth tokens: store in memory (React state, useRef) or httpOnly cookies — NEVER localStorage / sessionStorage (XSS-readable).
   - Env vars at build time: Vite exposes import.meta.env.VITE_*; CRA exposes process.env.REACT_APP_*. Treat as PUBLIC (bundled into JS shipped to browser). Never put secrets there.
   - Third-party scripts: prefer self-hosted; if external, verify SRI hash; CSP <script-src> allowlist.
   - Open redirects: validate any URL from query params before navigating (router.push(userInput) is dangerous).
   - File uploads / blob URLs: revoke createObjectURL after use; validate MIME types client-side AS a UX hint, not security (server validates again).
   - Dependencies: run `npm audit` and address Critical/High."

## Pre-phase commands

(none)

## Post-pipeline checks

The plugin auto-detects the package manager from the lockfile (`pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, otherwise npm) and runs the equivalent commands. Override per-project via `.claude/sdlc.local.yaml` `post_pipeline_checks` for monorepo runners (Nx, Turborepo, Lerna).

- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm test; elif [ -f yarn.lock ]; then yarn test; else npm test; fi'
- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm run lint 2>/dev/null || true; elif [ -f yarn.lock ]; then yarn run lint 2>/dev/null || true; else npm run lint --if-present; fi'
- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm run build 2>/dev/null || true; elif [ -f yarn.lock ]; then yarn build 2>/dev/null || true; else npm run build --if-present; fi'
- npx --no-install tsc --noEmit
