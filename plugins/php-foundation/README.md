# php-foundation

Shared PHP foundation skills for the [SDLC Marketplace](../../README.md).

This is a **pure skill library** — no agent, no stack profile. It ships stack-agnostic PHP conventions referenced by every PHP plugin in the marketplace (`laravel-plugin`, `symfony-plugin`, and future framework plugins).

## Skills

| Skill | Description |
|---|---|
| `php-foundation:php-conventions` | Modern PHP 8.x idioms: readonly properties, enums, `match`, constructor promotion, typed properties, named arguments, first-class callable syntax, `declare(strict_types=1)`, PSR-12, null safety |
| `php-foundation:composer-tooling` | Composer detection, PSR-4 autoloading, version constraints (`^`/`~`), `composer.json` vs `composer.lock`, scripts, platform requirements |
| `php-foundation:php-testing` | PHPUnit + Pest structure, data providers, test doubles (mocks/stubs/Mockery), fixtures, coverage targets |

## Dependencies

- [`sdlc`](../sdlc) — core pipeline (auto-pulled on install)

## Installation

This plugin is pulled automatically as a dependency of `laravel-plugin` and `symfony-plugin`:

```
/plugin install laravel-plugin@sdlc-marketplace
# or
/plugin install symfony-plugin@sdlc-marketplace
```

To install standalone (if you want PHP skills without a stack provider):

```
/plugin install php-foundation@sdlc-marketplace
```
