---
stack: nodejs
priority: 100
aspects: [backend]
detect:
  all:
    - file_exists: package.json
    - file_contains:
        path: package.json
        pattern: '"(express|fastify|koa|hapi|@hapi/hapi|hono|@nestjs/core)"\s*:'
---

# Node.js Stack Profile

Stack provider for Node.js backend projects. Triggers when `package.json` declares a backend framework (Express, Fastify, Koa, Hapi / `@hapi/hapi`, Hono, or `@nestjs/core`). `@types/node` and `engines.node` are deliberately not markers — frontend SPAs carry them too. A framework-less Node service does not auto-detect: run it with `--stack=nodejs`.

Specialized backend frameworks (NestJS) and full-stack frameworks (Next.js) declare higher priority and override this profile via aspect resolution.

## Agents per phase

- business_analysis: business-analyst        # core agent
- development: node-architect                # ⚡ Node.js-specific
- qa: qa-engineer                            # core agent
- security: security-analyst                 # core agent
- documentation: document-writer             # core agent

## Convention skills to apply

- nodejs-plugin:node-conventions
- js-foundation:npm-patterns
- js-foundation:typescript-patterns   # apply when tsconfig.json + typescript devDep present

## Extra phases

(none)

## Phase prompts injection

For development phase, inject:
  "Detect package manager from lockfile: package-lock.json → npm, yarn.lock → yarn, pnpm-lock.yaml → pnpm.
   Detect module system from package.json: \"type\": \"module\" → ESM (use import/export), otherwise CJS (require/module.exports). Be consistent with the project — do not mix.
   Detect TypeScript: tsconfig.json + typescript in devDependencies (or dependencies). When present, match the tsconfig strictness level — never use `any`, prefer `unknown` + runtime validation at boundaries, use discriminated unions over optional fields, brand IDs to prevent mix-ups. Run `npx tsc --noEmit` (or the project's typecheck script) before completion; type errors block completion.
   Use async/await over callbacks unless the surrounding code uses callbacks already.
   Centralize error handling — Express: error-handling middleware (4-arg signature); Fastify: setErrorHandler; Koa: try/catch in middleware. In TypeScript, type errors as classes extending Error and narrow via instanceof in catch blocks.
   Read environment variables through a single config module (e.g., src/config.js or src/config.ts loading from process.env). Never hard-code secrets.
   Apply skills: nodejs-plugin:node-conventions, js-foundation:npm-patterns, and js-foundation:typescript-patterns when the project is TypeScript.
   If superpowers is available, invoke superpowers:verification-before-completion before returning, to systematically verify the implementation against acceptance criteria."

For qa phase, inject:
  "Detect test framework from devDependencies in package.json: jest → Jest, vitest → Vitest, mocha → Mocha, node:test → built-in. Match existing tests' style.
   Run tests via the script defined in package.json scripts.test (auto-detect runner per the post_pipeline_checks pattern). If a coverage script exists, prefer it.
   For TypeScript: ensure tests are also strictly typed. Run `npx tsc --noEmit` after writing tests; type errors in test files block completion just like in source files. If the project has separate tsconfig for tests (tsconfig.test.json), use it.
   For HTTP routes, use supertest or framework-native test client (Fastify .inject(), Koa request).
   Mock external services at the module boundary, not inside business logic."

For security phase, inject:
  "Check Node.js-specific issues:
   - Prototype pollution (Object.assign / lodash.merge with untrusted input).
   - ReDoS (catastrophic backtracking in regexes built from user input).
   - Path traversal in fs operations on user-controlled paths.
   - Command injection via child_process.exec with concatenated input.
   - Insecure deserialization of session data.
   - Run npm audit; fix Critical/High vulnerabilities (npm audit fix).
   - Check for exposed .env files or hardcoded credentials in committed code.
   - Verify rate limiting and input validation on public endpoints."

## Pre-phase commands

(none)

## Post-pipeline checks

The plugin auto-detects the package manager from the lockfile (`pnpm-lock.yaml` → pnpm, `yarn.lock` → yarn, otherwise npm) and runs the equivalent command. Override per-project via `.claude/sdlc.local.yaml` `post_pipeline_checks` if you need explicit control (Yarn Berry workspaces, custom monorepo runner, etc.).

- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm test; elif [ -f yarn.lock ]; then yarn test; else npm test; fi'
- sh -c 'if [ -f pnpm-lock.yaml ]; then pnpm run lint 2>/dev/null || true; elif [ -f yarn.lock ]; then yarn run lint 2>/dev/null || true; else npm run lint --if-present; fi'
