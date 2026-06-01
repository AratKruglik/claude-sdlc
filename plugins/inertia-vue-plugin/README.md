# inertia-vue-plugin

Inertia.js + Vue 3 frontend stack provider for the SDLC marketplace. Auto-detects `@inertiajs/vue3` (or legacy `@inertiajs/inertia-vue3`) in `package.json` and substitutes the Inertia-aware `inertia-vue-architect` into the frontend development phase. Works alongside `laravel-plugin` — the two compose cleanly: `laravel-architect` writes the backend and documents the props contract; `inertia-vue-architect` implements the Vue pages consuming that contract.

> Requires [`sdlc`](../sdlc/README.md), [`js-foundation`](../js-foundation/README.md), and [`vue-plugin`](../vue-plugin/README.md) — installed automatically as dependencies.

## What this plugin adds

| Component | Purpose |
|---|---|
| `stack.md` | Registers `inertia-vue` as a stack provider with `priority: 175` — beats generic `vue-plugin` (150) for Inertia projects. |
| `agents/inertia-vue-architect.md` | Replaces `vue-architect` for the frontend aspect on Inertia+Vue projects. Knows `useForm`, `usePage`, `<Link>`, `router` — no `vue-router`. (Sonnet) |

## Pipeline shape on a Laravel + Inertia + Vue project

With both `laravel-plugin` and `inertia-vue-plugin` installed, the pipeline fans out across two stack providers:

```
business_analysis    → core's business-analyst          (Opus)
development
  backend aspect     → laravel-architect                (Sonnet)  ← from laravel-plugin
  frontend aspect    → inertia-vue-architect            (Sonnet)  ← from inertia-vue-plugin
database             → artisan-specialist               (Sonnet)  ← from laravel-plugin
qa                   → core's qa-engineer               (Sonnet)
security             → core's security-analyst          (Opus)
documentation        → core's document-writer           (Haiku)

Post-pipeline (inertia-vue-plugin):
  npm test (or pnpm/yarn)
  npm run lint --if-present
  npm run build --if-present
  npx vue-tsc --noEmit (or tsc --noEmit fallback)

Post-pipeline (laravel-plugin):
  ./vendor/bin/pint --test
  php artisan test
  php artisan route:list
```

`laravel-architect` documents the Inertia props contract in `docs/plans/{task_slug}/02-development-backend.md`. `inertia-vue-architect` reads that contract and implements the matching Vue pages.

## Prerequisites

- Laravel project with `composer.json` containing `"inertiajs/inertia-laravel"`.
- `package.json` containing `"@inertiajs/vue3"` (modern) or `"@inertiajs/inertia-vue3"` (legacy).
- `vue-plugin` installed (provides convention skills reused by this plugin).

## Installation

```bash
/plugin marketplace add AratKruglik/claude-sdlc
/plugin install inertia-vue-plugin@sdlc-marketplace
# sdlc, js-foundation, vue-plugin install as dependencies
```

## Verifying

```bash
cd /path/to/your/laravel-inertia-vue/project
/sdlc:list-stacks
# Expected output:
#   🎯 vanilla       priority=0   (always matches)
#   🎯 laravel       priority=100 (matches: composer.json + laravel/framework)
#   🎯 vue           priority=150 (matches: package.json + vue dependency)
#   🎯 inertia-vue   priority=175 (matches: package.json + @inertiajs/vue3)
```

`inertia-vue` wins the frontend aspect over `vue` because 175 > 150. `vue-plugin` still provides convention skills (`vue-conventions`, `vue-state-management`, `vue-forms`, `vue-testing`) but does not run its own architect for the frontend.

Note: `vue-plugin:vue-routing` is intentionally excluded — Inertia does not use a client-side Vue Router.

## Tie behavior

If `package.json` contains both `@inertiajs/vue3` and `@inertiajs/react` (a vue↔react migration project), both Inertia profiles match at priority 175. The orchestrator halts with a tie error. Resolve by passing the stack flag explicitly:

```bash
/sdlc:start --stack=inertia-vue "Migrate billing page to React"
```

## Override stack manually

```bash
/sdlc:start --stack=vue "Quick prototype without Inertia"
# Uses generic vue-architect instead of inertia-vue-architect.
```

## License

MIT — see [`../../LICENSE`](../../LICENSE).
