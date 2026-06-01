# inertia-react-plugin

Inertia.js + React frontend stack provider for the SDLC marketplace. Auto-detects `@inertiajs/react` (or legacy `@inertiajs/inertia-react`) in `package.json` and substitutes the Inertia-aware `inertia-react-architect` into the frontend development phase. Works alongside `laravel-plugin` — the two compose cleanly: `laravel-architect` writes the backend and documents the props contract; `inertia-react-architect` implements the React pages consuming that contract.

> Requires [`sdlc`](../sdlc/README.md), [`js-foundation`](../js-foundation/README.md), and [`react-plugin`](../react-plugin/README.md) — installed automatically as dependencies.

## What this plugin adds

| Component | Purpose |
|---|---|
| `stack.md` | Registers `inertia-react` as a stack provider with `priority: 175` — beats generic `react-plugin` (150) for Inertia projects. |
| `agents/inertia-react-architect.md` | Replaces `react-architect` for the frontend aspect on Inertia+React projects. Knows `useForm`, `usePage`, `<Link>`, `router` — no `react-router-dom`. (Sonnet) |

## Pipeline shape on a Laravel + Inertia + React project

With both `laravel-plugin` and `inertia-react-plugin` installed, the pipeline fans out across two stack providers:

```
business_analysis    → core's business-analyst          (Opus)
development
  backend aspect     → laravel-architect                (Sonnet)  ← from laravel-plugin
  frontend aspect    → inertia-react-architect          (Sonnet)  ← from inertia-react-plugin
database             → artisan-specialist               (Sonnet)  ← from laravel-plugin
qa                   → core's qa-engineer               (Sonnet)
security             → core's security-analyst          (Opus)
documentation        → core's document-writer           (Haiku)

Post-pipeline (inertia-react-plugin):
  npm test (or pnpm/yarn)
  npm run lint --if-present
  npm run build --if-present
  npx tsc --noEmit

Post-pipeline (laravel-plugin):
  ./vendor/bin/pint --test
  php artisan test
  php artisan route:list
```

`laravel-architect` documents the Inertia props contract in `docs/plans/{task_slug}/02-development-backend.md`. `inertia-react-architect` reads that contract and implements the matching React pages.

## Prerequisites

- Laravel project with `composer.json` containing `"inertiajs/inertia-laravel"`.
- `package.json` containing `"@inertiajs/react"` (modern) or `"@inertiajs/inertia-react"` (legacy).
- `react-plugin` installed (provides convention skills reused by this plugin).

## Installation

```bash
/plugin marketplace add AratKruglik/claude-sdlc
/plugin install inertia-react-plugin@sdlc-marketplace
# sdlc, js-foundation, react-plugin install as dependencies
```

## Verifying

```bash
cd /path/to/your/laravel-inertia-react/project
/sdlc:list-stacks
# Expected output:
#   🎯 vanilla        priority=0   (always matches)
#   🎯 laravel        priority=100 (matches: composer.json + laravel/framework)
#   🎯 react          priority=150 (matches: package.json + react dependency)
#   🎯 inertia-react  priority=175 (matches: package.json + @inertiajs/react)
```

`inertia-react` wins the frontend aspect over `react` because 175 > 150. `react-plugin` still provides convention skills (`react-conventions`, `react-state-management`, `react-forms`, `react-testing`) but does not run its own architect for the frontend.

Note: `react-plugin:react-routing` is intentionally excluded — Inertia does not use a client-side React Router.

## Tie behavior

If `package.json` contains both `@inertiajs/vue3` and `@inertiajs/react` (a vue↔react migration project), both Inertia profiles match at priority 175. The orchestrator halts with a tie error. Resolve by passing the stack flag explicitly:

```bash
/sdlc:start --stack=inertia-react "Migrate billing page from Vue to React"
```

## Override stack manually

```bash
/sdlc:start --stack=react "Quick prototype without Inertia"
# Uses generic react-architect instead of inertia-react-architect.
```

## License

MIT — see [`../../LICENSE`](../../LICENSE).
