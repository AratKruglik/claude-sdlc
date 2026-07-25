---
stack: nextjs
priority: 250
aspects: [backend, frontend]
detect:
  all:
    - file_exists: package.json
    - file_contains:
        path: package.json
        pattern: '"next"\s*:'
---

# Next.js Stack Profile

Full-stack React framework. Triggers when `package.json` contains `"next"`. Highest priority among backend frameworks (250) and highest among frontend frameworks except React Native (300). Claims BOTH `backend` AND `frontend` aspects — Next.js owns the entire stack via App Router, Server Components, Server Actions, and Route Handlers.

On a NestJS + Next.js monorepo with separate `package.json` per app, the orchestrator runs per-CWD: in `apps/api/` only nestjs detects; in `apps/web/` only nextjs detects. On a single-`package.json` mixed project, nextjs wins both aspects via priority — use `--stack=NAME` override if that's wrong.

## Agents per phase

- business_analysis: business-analyst        # core agent
- development: nextjs-architect              # ⚡ Next.js-specific
- qa: qa-engineer                            # core agent
- security: security-analyst                 # core agent
- documentation: document-writer             # core agent

## Convention skills to apply

- nextjs-plugin:nextjs-conventions
- nextjs-plugin:server-component-patterns
- nextjs-plugin:nextjs-data-fetching
- nextjs-plugin:nextjs-routing
- nextjs-plugin:nextjs-testing
- js-foundation:typescript-patterns
- js-foundation:npm-patterns
- frontend-design:frontend-design  # optional external; skipped automatically when absent

## Extra phases

(none)

## Phase prompts injection

For development phase, inject:
  "Next.js full-stack framework. Detect router: presence of `app/` directory → App Router (modern, preferred); presence of `pages/` directory → Pages Router (legacy, mirror existing patterns). Most new projects are App Router.
   In App Router: components are React Server Components (RSC) BY DEFAULT — they run on the server, do not have access to browser APIs (window, document, useState, useEffect), and can be async. Add `\"use client\"` directive ONLY at the top of files that need browser APIs or interactivity. Push the boundary as deep as possible — keep more code as RSC.
   Server Actions for mutations: declare with `\"use server\"` either as a top-of-file directive or inline above an async function. Pass to <form action={...}> or call from event handlers in Client Components.
   Data fetching: in RSC, use native `fetch()` with built-in caching/revalidation; the `cache: 'no-store'` and `next: { revalidate: N }` options control behavior. For dynamic params: `generateStaticParams()` for SSG, `dynamic = 'force-dynamic'` for SSR per-request.
   Metadata: export const metadata or generateMetadata() for SEO, OpenGraph, structured data.
   Image optimization: use next/image with explicit width/height; whitelist remote domains in `next.config.js`.
   Apply skills: nextjs-plugin:nextjs-conventions, nextjs-plugin:server-component-patterns, nextjs-plugin:nextjs-data-fetching, nextjs-plugin:nextjs-routing, js-foundation:typescript-patterns, js-foundation:npm-patterns.
   If superpowers is available, invoke superpowers:verification-before-completion before returning."

For qa phase, inject:
  "Next.js testing strategies depend on the layer:
   - Server Component testing: hard to unit-test directly (they're async, run on server). Prefer integration via Playwright/Cypress hitting the rendered page.
   - Client Component testing: Vitest/Jest + React Testing Library. Treat them like regular React components.
   - Server Actions: extract logic into pure functions, unit-test those; test the action wrapper via integration test.
   - Route Handlers: import the GET/POST handler, call with a mock NextRequest, assert on the NextResponse.
   - End-to-end: Playwright is the modern choice for Next.js (Vercel sponsors it). Cypress also works.
   Use msw for API mocks at the network layer in component tests.
   Apply skill: nextjs-plugin:nextjs-testing."

For security phase, inject:
  "Next.js-specific security checks:
   - Env vars: only NEXT_PUBLIC_* are bundled into the client. Verify no server-only secrets are prefixed with NEXT_PUBLIC_.
   - Server Actions are public by design — every Server Action MUST validate the caller is authorized (auth check at the top of the function). Never trust hidden form fields.
   - Route Handlers: same authorization rules as any HTTP endpoint. Validate input via zod or similar.
   - CSRF: Server Actions have built-in protection in Next.js 14+ via origin checks; verify `serverActions.allowedOrigins` is set restrictively.
   - CSP headers via `next.config.js` `headers()`. At minimum: `default-src 'self'`, `script-src 'self' 'unsafe-inline'` (review unsafe-inline carefully).
   - next/image domain whitelist in `images.remotePatterns`. Never use `images.domains: ['*']`.
   - Middleware (`middleware.ts`) runs on EVERY request — keep it lean; don't pull in heavy deps.
   - `unstable_*` APIs are unstable — flag any usage as a future maintenance risk."

## Pre-phase commands

(none)

## Post-pipeline checks

The plugin auto-detects the package manager from the lockfile (`pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, otherwise npm) and runs the equivalent commands. `npm run build` for Next.js performs combined compile + type-check + lint and catches most runtime issues — it's the most valuable single check. Override per-project via `.claude/sdlc.local.yaml` `post_pipeline_checks` for monorepo runners (Nx, Turborepo).

- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm test; elif [ -f yarn.lock ]; then yarn test; else npm test; fi'
- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm run lint 2>/dev/null || true; elif [ -f yarn.lock ]; then yarn run lint 2>/dev/null || true; else npm run lint --if-present; fi'
- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm run build; elif [ -f yarn.lock ]; then yarn build; else npm run build; fi'
- npx --no-install tsc --noEmit
