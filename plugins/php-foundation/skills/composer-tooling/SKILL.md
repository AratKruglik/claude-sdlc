---
name: composer-tooling
description: |
  Composer conventions for any PHP project: dependency management, version constraints, PSR-4 autoloading, scripts, platform requirements, and the composer.json vs composer.lock contract. Stack-agnostic — referenced by every PHP plugin in the marketplace.

  Use this skill to:
  - Read composer.json to detect the PHP version, framework, and key packages before writing code.
  - Add dependencies with correct version constraints and the right require vs require-dev placement.
  - Configure PSR-4 autoloading and regenerate the autoloader after adding namespaces.
  - Use composer scripts and platform config consistently.

  Do NOT use this skill for:
  - PHP language idioms — see php-foundation:php-conventions.
  - Testing setup and runners — see php-foundation:php-testing.
  - Framework-specific package guidance (Laravel/Symfony bundles) — those live in framework plugin skills.
---

# Composer Tooling (stack-agnostic)

Composer is the dependency manager and autoloader entry point for every modern PHP project. Read `composer.json` before doing anything else — it tells you the PHP version, the framework, and the available packages.

## Project detection

```bash
cat composer.json                 # PHP version (require.php), framework, scripts
test -f composer.lock && echo "locked"   # lockfile present → reproducible installs
```

Key fields to read:

- `require.php` — minimum PHP version (drives which language features you may use).
- `require` — runtime dependencies; the framework marker lives here (`laravel/framework`, `symfony/framework-bundle`).
- `require-dev` — dev/test tooling (phpunit, pest, phpstan, pint, php-cs-fixer).
- `autoload.psr-4` — namespace → directory map.
- `config.platform.php` — pins the version the resolver targets (may differ from the runtime PHP).

## composer.json vs composer.lock

- **`composer.json`** declares *intent* — version ranges you accept.
- **`composer.lock`** records the *exact* resolved versions. It is committed and is the source of truth for `composer install`.

| Command | Effect |
|---|---|
| `composer install` | Installs the exact versions from `composer.lock`. Use in CI/deploy. |
| `composer update <pkg>` | Re-resolves the named package, rewrites the lock. Use deliberately. |
| `composer require <pkg>` | Adds to `composer.json` + updates the lock for that package. |
| `composer require --dev <pkg>` | Same, into `require-dev`. |

Never hand-edit `composer.lock`. Never run a bare `composer update` (updates everything) as part of a focused feature change.

## Version constraints

```jsonc
{
  "require": {
    "php": "^8.2",              // >=8.2.0 <9.0.0 — recommended for libraries/apps
    "guzzlehttp/guzzle": "^7.8" // caret: compatible up to the next major
  }
}
```

- **Caret `^7.8`** — allows `>=7.8.0 <8.0.0`. The default; respects SemVer.
- **Tilde `~7.8.0`** — allows `>=7.8.0 <7.9.0`. Tighter; use when you must pin to a minor.
- **Exact `7.8.3`** — avoid except to work around a specific broken release.
- Avoid `*` and unbounded `>=` — they break reproducibility.

## Adding a dependency — checklist

1. Confirm it is not already provided transitively (`composer why-not <pkg>` / check existing `require`).
2. Choose `require` (runtime) vs `require-dev` (tools/tests) correctly.
3. Use a caret constraint unless the project convention says otherwise.
4. Run `composer require <pkg>` so the lockfile updates atomically.
5. Verify nothing else moved: review the `composer.lock` diff — only the new package and its deps should change.

## PSR-4 autoloading

```jsonc
{
  "autoload": {
    "psr-4": {
      "App\\": "src/"
    }
  },
  "autoload-dev": {
    "psr-4": {
      "App\\Tests\\": "tests/"
    }
  }
}
```

- Namespace prefix maps to a base directory; sub-namespaces map to sub-directories, class name = file name.
- After adding a new top-level namespace mapping, run `composer dump-autoload`.
- Keep test namespaces in `autoload-dev` so they are excluded from production autoload maps.
- For deploy/CI, generate an optimized classmap: `composer dump-autoload --optimize` (or `--classmap-authoritative`).

## Scripts

```jsonc
{
  "scripts": {
    "test": "phpunit",
    "stan": "phpstan analyse",
    "cs": "php-cs-fixer fix"
  }
}
```

Run via `composer test`, `composer stan`. Prefer existing scripts over invoking the binary directly — they encode the project's intended flags. Discover them with `composer run-script --list`.

## Platform requirements

```jsonc
{
  "config": {
    "platform": {
      "php": "8.2.0"
    }
  }
}
```

`config.platform.php` tells Composer which PHP version to resolve against, independent of the local CLI version — keep it aligned with the production runtime so the lockfile is deployable.
