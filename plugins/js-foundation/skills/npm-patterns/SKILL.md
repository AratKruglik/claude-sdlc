---
name: npm-patterns
description: |
  Package management discipline for any JavaScript/TypeScript project: dependency declaration, semver, scripts conventions, lockfile hygiene, package-manager detection (npm/yarn/pnpm). Stack-agnostic — referenced by every JS/TS framework plugin in the marketplace.

  Use this skill to:
  - Add a dependency correctly (right field, right semver range).
  - Pick the project's package manager from lockfile.
  - Define `scripts` entries that match conventions.
  - Avoid lockfile mistakes (manual edits, wrong commits).

  Do NOT use this skill for:
  - Code-level conventions (see the active framework plugin's conventions skill).
  - Framework-specific package patterns (NestJS modules, Angular schematics, Expo SDK choice etc.).
user-invocable: false
paths: ["package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock", ".npmrc"]
---

# npm / yarn / pnpm Patterns (stack-agnostic)

This skill consolidates package management idioms applicable to any JS/TS project — backend, frontend, mobile, library. Apply when modifying `package.json`, adding dependencies, or defining scripts.

## Detect the package manager

Look at the lockfile in the project root:

| Lockfile present | Use |
|---|---|
| `package-lock.json` | npm |
| `yarn.lock` | yarn |
| `pnpm-lock.yaml` | pnpm |
| `bun.lockb` / `bun.lock` | bun (rare; mostly drop-in for npm) |
| (none) | npm — but flag in DECISIONS that no lockfile is committed |

Also check `package.json` `"packageManager"` field (e.g. `"packageManager": "pnpm@8.6.0"`) — when present, it overrides lockfile inference.

Map common commands:

| Action | npm | yarn | pnpm |
|---|---|---|---|
| Install all | `npm install` | `yarn install` | `pnpm install` |
| Add runtime dep | `npm install pkg` | `yarn add pkg` | `pnpm add pkg` |
| Add dev dep | `npm install -D pkg` | `yarn add -D pkg` | `pnpm add -D pkg` |
| Run script | `npm run x` | `yarn x` | `pnpm x` |
| Update lockfile | `npm install` | `yarn install` | `pnpm install` |

Always run the install command after editing `package.json` — never edit the lockfile by hand.

## Dependency fields

| Field | Use for |
|---|---|
| `dependencies` | Runtime — what the production app needs to run (express, react, pinia, axios). |
| `devDependencies` | Dev tooling — bundlers, test runners, linters, type definitions, dev servers. |
| `peerDependencies` | Library authors only — declares what host app must provide (e.g., `react` for a React component library). |
| `optionalDependencies` | Rare — install failure should not break install (native binaries with fallbacks). |
| `bundledDependencies` | Rare — packaged inside `npm pack` tarball. |

Rule of thumb: if the code is bundled into the production output for runtime use, it's a dependency. If it only runs during `npm test` / `npm run build` / lint, it's a devDependency.

Frontend nuance: bundlers (Vite/Webpack/esbuild) often tree-shake unused exports — but the package still belongs in `dependencies` if any production-rendered code imports it.

## Semver discipline

| Range | Meaning | When to use |
|---|---|---|
| `^1.2.3` | >=1.2.3 <2.0.0 (no breaking changes) | Default — most deps |
| `~1.2.3` | >=1.2.3 <1.3.0 (only patch) | Conservative — production-critical |
| `1.2.3` | Exact | When you've debugged a specific version (rare) |
| `>=1.2.3` | Any version >=1.2.3 | Almost never — too loose |
| `*` or `latest` | Anything | NEVER. Reproducible builds matter. |
| `git+https://...` | Git ref | Only as last resort; pin to commit SHA. |

Default: `^x.y.z`. Lockfile pins exact versions for reproducibility — that's what makes `^` safe.

## `scripts` conventions

Common script names (be consistent — these are de-facto standard):

| Script | Purpose |
|---|---|
| `start` | Production entry: `node dist/index.js` (Node) or static server (frontend) |
| `dev` | Dev entry: `nodemon` / `tsx watch` / `vite` / `next dev` / `ng serve` |
| `build` | Compile/bundle: `tsc`, `vite build`, `next build`, `ng build`, `esbuild`, `webpack` |
| `test` | Test runner: `jest`, `vitest`, `mocha`, `ng test` |
| `test:watch` | Watch-mode tests |
| `test:coverage` | Coverage report |
| `test:e2e` | E2E tests (Playwright/Cypress/Detox) |
| `lint` | `eslint .` |
| `lint:fix` | `eslint . --fix` |
| `format` | `prettier --write .` |
| `format:check` | `prettier --check .` |
| `typecheck` | `tsc --noEmit` (or `vue-tsc --noEmit` for Vue) |
| `clean` | Remove `dist/`, `coverage/`, `.next/`, `out/` |
| `prepare` | Auto-runs after `install` (husky setup, etc.) |

Don't invent new names without a reason. CI configs and other tools assume these.

## Lockfile policy

- **Always commit** the lockfile to git.
- **Never edit** by hand. Always regenerate via the package manager.
- **Match the package manager**: don't commit `yarn.lock` and `package-lock.json` simultaneously.
- **Resolve conflicts** by accepting one side, then running `<pm> install` to regenerate.
- For library packages published to npm, lockfile is committed but not published (it's in `.npmignore` by default).

## `engines` field

Pin Node version when it matters (e.g., uses `node:test` requires ≥18, or your bundler requires ≥20):

```json
{
  "engines": {
    "node": ">=18.0.0"
  }
}
```

Add `engines.npm` only if you need a specific npm major version.

## `package.json` `type` field

- `"type": "module"` — files default to ESM. Use `import`/`export`. CJS files must use `.cjs` extension.
- Absent or `"type": "commonjs"` — files default to CJS. Use `require`/`module.exports`. ESM files must use `.mjs` extension.

Don't change this unless the BA spec explicitly asks; switching modes mid-project is invasive (especially for backend Node projects).

Frontend bundler-driven projects (Vite/Webpack/Next/Angular CLI) typically use `"type": "module"` regardless — bundler handles output.

## Workspaces (monorepos)

For monorepos:

```json
// Root package.json
{
  "name": "my-monorepo",
  "private": true,
  "workspaces": ["apps/*", "packages/*"]
}
```

- pnpm: uses `pnpm-workspace.yaml` instead.
- yarn: same `workspaces` field; berry vs classic differ in detail.
- Monorepo runners (Nx, Turborepo, Lerna): override default install/build/test orchestration. Match what's installed.

Per-app `package.json` files declare app-specific deps; root-only deps go in root.

## Dependency hygiene

- Run `npm audit` (or equivalent) when adding deps; fix Critical/High before committing.
- Avoid `--force` resolution unless you know what you're overriding and document it.
- Don't add deps for trivial utilities you can write in 5 lines (e.g., is-odd, padleft) — supply chain risk.
- Watch for typo-squatting: `lodash` vs `lodahs`, `chalk` vs `chal-k`.
- For frontend: bundle size matters — measure before adding heavy deps (use `bundlephobia.com` as a quick gauge).

## Anti-patterns

- ❌ `npm install --force` without justification.
- ❌ Editing `package-lock.json` / `yarn.lock` / `pnpm-lock.yaml` by hand.
- ❌ Using `*` or `latest` as a version range.
- ❌ Adding the same package to both `dependencies` and `devDependencies`.
- ❌ Committing `node_modules/`.
- ❌ Mixing package managers (lockfile from one, install via another).
- ❌ Adding `engines.node` without testing on the lower bound.
- ❌ For frontend: putting build-time tools in `dependencies` (bloats `npm ci` for production-only installs).
