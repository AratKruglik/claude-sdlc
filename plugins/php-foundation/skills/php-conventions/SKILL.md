---
name: php-conventions
description: |
  Modern PHP idioms for any PHP project (PHP 8.1+): readonly properties, enums, match expressions, constructor property promotion, typed properties, named arguments, nullsafe operator, first-class callable syntax, strict_types, PSR-12 style, and null discipline. Apply when the project is a PHP 8.1+ project. Stack-agnostic — referenced by every PHP plugin in the marketplace.

  Use this skill to:
  - Write strongly-typed, immutable-by-default value objects with readonly properties and enums.
  - Replace switch ladders and magic constants with match expressions and backed enums.
  - Cut constructor boilerplate with property promotion and express optionality with typed nullable returns.
  - Keep code PSR-12 compliant with declare(strict_types=1) in every file.

  Do NOT use this skill for:
  - Framework-specific idioms (Eloquent, Doctrine, Symfony services, Laravel facades — those live in framework plugin skills).
  - Composer / autoloading / dependency management — see php-foundation:composer-tooling.
  - Testing patterns — see php-foundation:php-testing.
---

# PHP Conventions (stack-agnostic, PHP 8.1+)

This skill encodes idioms that reduce bugs and improve readability in any PHP codebase. Apply alongside the active framework plugin's conventions skill (e.g., `laravel:laravel-conventions`, `symfony:symfony-conventions`).

## Detection

Read `composer.json` first to learn the target PHP version:

- `"require": { "php": "^8.1" }` (or higher) → all idioms below apply.
- `"config": { "platform": { "php": "8.x" } }` pins the resolver version.

Match the project's minimum version — do not use PHP 8.2+ features (e.g. readonly classes, DNF types) on an 8.1 project.

## strict_types — always on

Every `.php` file with logic starts with:

```php
<?php

declare(strict_types=1);

namespace App\Domain;
```

Strict typing turns silent coercions into `TypeError`s at the boundary, catching bugs early. The declaration must be the first statement.

## Constructor property promotion

Collapse the declare/assign boilerplate into the signature.

```php
// Prefer
final class Money
{
    public function __construct(
        public readonly int $amount,
        public readonly Currency $currency,
    ) {
    }
}

// Avoid — manual field + assignment
final class Money
{
    private int $amount;
    private Currency $currency;

    public function __construct(int $amount, Currency $currency)
    {
        $this->amount = $amount;
        $this->currency = $currency;
    }
}
```

## readonly properties — immutability by default

```php
final class OrderLine
{
    public function __construct(
        public readonly string $sku,
        public readonly int $quantity,
    ) {
    }

    public function withQuantity(int $quantity): self
    {
        return new self($this->sku, $quantity); // return a new instance, never mutate
    }
}
```

`readonly` properties can be assigned once (from within the declaring scope) and never again. Use them for value objects and DTOs. On PHP 8.2+ a whole class may be marked `readonly`.

## Enums — replace magic constants

Use backed enums for closed sets of values; attach behaviour with methods.

```php
enum Status: string
{
    case Draft = 'draft';
    case Active = 'active';
    case Archived = 'archived';

    public function isPublished(): bool
    {
        return $this === self::Active;
    }

    public function label(): string
    {
        return match ($this) {
            self::Draft => 'Draft',
            self::Active => 'Active',
            self::Archived => 'Archived',
        };
    }
}

$status = Status::from('active');        // throws ValueError on unknown
$maybe = Status::tryFrom($input);        // null on unknown
```

Never model a closed set with bare string constants or class `const` lists when a backed enum fits.

## match — exhaustive, type-safe branching

```php
$discount = match (true) {
    $total >= 1000 => 0.15,
    $total >= 500  => 0.10,
    $total >= 100  => 0.05,
    default        => 0.0,
};
```

`match` uses strict comparison (`===`), has no fallthrough, and throws `UnhandledMatchError` if nothing matches and no `default` is present — far safer than `switch`.

## Typed properties, parameters, and returns

```php
final class UserService
{
    public function findById(int $id): ?User      // explicit nullable return
    {
        return $this->repository->find($id);
    }

    /** @return list<User> */
    public function active(): array                // PHPDoc narrows array element type
    {
        return $this->repository->whereActive();
    }
}
```

- Type every parameter, property, and return value. Use `?T` for nullable, union types (`int|string`) where genuinely needed.
- PHP has no generics — use PHPDoc (`list<T>`, `array<K, V>`) so static analysers (PHPStan/Psalm) can check element types.

## Nullsafe operator and null discipline

```php
$country = $order?->customer?->address?->country;   // short-circuits to null

// Validate at boundaries instead of propagating null
public function charge(Customer $customer): void
{
    $card = $customer->defaultCard()
        ?? throw new NoPaymentMethodException($customer->id);
    // ...
}
```

- Do not return `null` to signal errors from public methods — throw a domain exception or return an empty collection.
- Use the nullsafe operator for optional read chains, not to hide missing required data.

## Named arguments

```php
$response = $client->request(
    method: 'POST',
    uri: '/orders',
    options: ['json' => $payload],
);
```

Use named arguments to clarify boolean/optional parameters at the call site. Do not reorder — pass them in declaration order for readability.

## First-class callable syntax

```php
$names = array_map(strtoupper(...), $words);
$ids = array_map($user->id(...), $users);
```

Prefer `$callable(...)` over string callable names or array `[$obj, 'method']` forms.

## Code style — PSR-12

- 4-space indentation, no tabs. One class per file. Files use `<?php` (no closing `?>`).
- `final` by default; open for extension only when designed for it.
- Single quotes for strings without interpolation.
- One blank line between methods; trailing comma in multi-line arrays/arguments.
- Run a formatter (the active framework plugin provides a Stop hook — Laravel Pint or PHP-CS-Fixer with the `@PSR12` / `@Symfony` ruleset). Do not hand-tune whitespace the formatter owns.

## Class design rules

- Single Responsibility: one reason to change per class.
- Prefer composition over inheritance; keep inheritance trees shallow.
- Keep the public API minimal — `private`/`protected` by default, `public` only when needed.
- Define contracts with `interface`; depend on abstractions, not concretions.
- Avoid static state. Pure static helpers for stateless functions are acceptable.
