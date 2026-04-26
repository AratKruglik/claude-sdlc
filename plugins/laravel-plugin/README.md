# laravel-plugin

Laravel + Inertia + Vue stack provider for the SDLC marketplace. Auto-detects Laravel projects (`composer.json` containing `"laravel/framework"`) and substitutes Laravel-specific agents into the pipeline.

> Requires [`core-sdlc-plugin`](../core-sdlc-plugin/README.md) — installed automatically as a dependency.

## What this plugin adds

| Component | Purpose |
|---|---|
| `stack.md` | Registers Laravel as a stack provider with `priority: 100`. |
| `agents/laravel-architect.md` | Replaces vanilla `developer` for Laravel projects. Knows Action / Form Request / Policy / Inertia patterns. (Sonnet) |
| `agents/artisan-specialist.md` | Runs in the extra `database` phase after development. Elaborates migrations, factories, seeders. (Sonnet) |
| `skills/laravel-conventions/SKILL.md` | Routing, Action pattern, Form Requests, Policies, Eloquent basics. |
| `skills/eloquent-patterns/SKILL.md` | N+1 prevention, scopes, relations, batch operations, raw query safety. |
| `mcp.json` | Laravel Boost MCP fragment — copy/merge into your project's root `.mcp.json`. |
| `hooks/hooks.json` | Stop hook that runs Pint formatting after each session. |

## Pipeline shape on a Laravel project

```
business_analysis    → core's business-analyst       (Opus)
development          → laravel-architect             (Sonnet)
database             → artisan-specialist            (Sonnet)  ← extra phase
qa                   → core's qa-engineer            (Sonnet)
security             → core's security-analyst       (Opus)    ← with Laravel-specific injection
documentation        → core's document-writer        (Haiku)

Post-pipeline:
  ./vendor/bin/pint --test
  php artisan test
  php artisan route:list
```

## Prerequisites

- Laravel 10+ project with `composer.json` containing `"laravel/framework"`.
- For Laravel Boost MCP to work: docker-compose service named `app` with `laravel/boost` installed (`composer require laravel/boost --dev`). Copy `plugins/laravel-plugin/mcp.json`'s `mcpServers` block into your project's root `.mcp.json`. If you don't use Docker, replace `docker compose exec -T app php /var/www/artisan boost:mcp` with `php artisan boost:mcp`.
- For Pint Stop hook: `laravel/pint` in dev deps. Already in default Laravel since v9.

## Installation

```bash
/plugin marketplace add AratKruglik/claude-sdlc
/plugin install laravel-plugin@sdlc-marketplace
# core-sdlc-plugin installs as a dependency
```

## Verifying

```bash
cd /path/to/your/laravel/project
/sdlc:list-stacks
# Expected output:
#   🎯 vanilla   priority=0   (always matches)
#   🎯 laravel   priority=100 (matches: composer.json + laravel/framework)
```

If you see only `vanilla`, your project doesn't have `"laravel/framework"` in `composer.json` (or the file isn't in the project root).

## Running

```bash
/sdlc:sdlc-start "Add subscription billing with Stripe"
```

Auto-detects Laravel, substitutes `laravel-architect` for development, inserts the `database` phase after development, injects Laravel-specific guidance into security review, runs Pint + Pest + route:list at the end.

## Override stack manually

```bash
/sdlc:sdlc-start --stack=vanilla "Quick prototype"
# Bypasses Laravel-specific agents and runs the vanilla pipeline.
```

## What this plugin does NOT include (yet)

- Filament admin panel agent (V2 — sub-stack plugin)
- Livewire-specific guidance (Inertia-first project assumption)
- Frontend-only Vue agent (laravel-architect handles backend + Inertia pages)
- Pure E2E browser tests (Playwright agent — V2 capability plugin)

If you need any of these, file an issue or submit a sub-stack plugin via PR.

## License

MIT — see [`../../LICENSE`](../../LICENSE).
