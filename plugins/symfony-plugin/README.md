# symfony-plugin

Symfony backend + database stack provider. Auto-detects Symfony projects (`composer.json` containing `"symfony/framework-bundle"`) and substitutes Symfony-specific agents into the pipeline. Renders Twig views and designs the Serializer/API contract for SPA frontends (pair with `vue-plugin` or `react-plugin`).

> Requires [`sdlc`](../sdlc/README.md) and [`php-foundation`](../php-foundation/README.md) — installed automatically as dependencies.

## What this plugin adds

| Component | Purpose |
|---|---|
| `stack.md` | Registers Symfony as a stack provider with `priority: 100`. |
| `agents/symfony-architect.md` | Replaces vanilla `developer` for the **backend aspect**. Controllers, services, DI, Form types, validation, Voters, Serializer, Messenger, Twig, and the API contract. (Sonnet) |
| `agents/doctrine-specialist.md` | Runs in the extra `database` phase after development. Finalizes entity mappings, generates + reviews migrations, fixtures, schema verification. (Sonnet) |
| `skills/symfony-conventions/SKILL.md` | Attribute routing, controllers-as-services, autowiring, Form types, validation, Voters, Serializer, Messenger. |
| `skills/doctrine-patterns/SKILL.md` | Entity mapping, repositories, parameterized DQL, N+1/fetch joins, relations, batch, generated migrations. |
| `security-patterns.yaml` | Symfony security regex rules for `security-guidance` (via `/sdlc:security-init`). |
| `hooks/hooks.json` | Stop hook that runs PHP-CS-Fixer formatting after each session. |

Shared PHP conventions (PSR-12, PHP 8 idioms, Composer, PHPUnit/Pest base) come from `php-foundation`.

## Pipeline shape on a Symfony project

```
business_analysis      → core's business-analyst       (Opus)
development (backend)  → symfony-architect             (Sonnet)
development (frontend) → vue-architect / react-architect (Sonnet, if a SPA frontend plugin is installed)
database               → doctrine-specialist           (Sonnet)  ← extra phase
qa                     → core's qa-engineer            (Sonnet)
security               → core's security-analyst       (Opus)    ← with Symfony-specific injection
documentation          → core's document-writer        (Haiku)

Post-pipeline:
  vendor/bin/php-cs-fixer fix --dry-run --diff
  php bin/phpunit
  php bin/console lint:container
  php bin/console debug:router
  php bin/console doctrine:schema:validate
```

## Prerequisites

- Symfony 6.4+ / 7.x project with `composer.json` containing `"symfony/framework-bundle"`.
- For the PHP-CS-Fixer Stop hook: `friendsofphp/php-cs-fixer` in dev deps.
- For the database phase: `doctrine/orm` + `doctrine/doctrine-migrations-bundle`. For fixtures: `doctrine/doctrine-fixtures-bundle`.
- For SPA frontend: install `vue-plugin` or `react-plugin` (wins the frontend aspect; symfony-architect provides the API contract). Twig projects need no frontend plugin.
- There is no Symfony MCP server — agents use `php bin/console` via Bash (Docker-aware).

## Installation

```bash
/plugin marketplace add AratKruglik/claude-sdlc
/plugin install symfony-plugin@sdlc-marketplace
# sdlc and php-foundation install as dependencies
```

## Verifying

```bash
cd /path/to/your/symfony/project
/sdlc:list-stacks
# Expected output:
#   🎯 vanilla   priority=0   (always matches)
#   🎯 symfony   priority=100 (matches: composer.json + symfony/framework-bundle)
```

If you see only `vanilla`, your project doesn't have `"symfony/framework-bundle"` in `composer.json` (or the file isn't in the project root).

## Running

```bash
/sdlc:start "Add subscription billing with Stripe"
```

Auto-detects Symfony, substitutes `symfony-architect` for development, inserts the `database` phase after development, injects Symfony-specific guidance into security review, runs PHP-CS-Fixer + PHPUnit + console checks at the end.

## Override stack manually

```bash
/sdlc:start --stack=vanilla "Quick prototype"
# Bypasses Symfony-specific agents and runs the vanilla pipeline.
```

## What this plugin does NOT include (yet)

- API Platform-specific agent (works via conventions, but no dedicated agent — V2)
- EasyAdmin / Sonata admin panel agent (V2 — sub-stack plugin)
- Frontend SPA pages — use `vue-plugin` (Vue) or `react-plugin` (React)
- Pure E2E browser tests (Panther/Playwright agent — V2 capability plugin)

If you need any of these, file an issue or submit a sub-stack plugin via PR.

## License

MIT — see [`../../LICENSE`](../../LICENSE).
