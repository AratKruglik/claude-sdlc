---
name: php-testing
description: |
  PHPUnit and Pest patterns for any PHP project: test structure, naming, data providers, test doubles (mocks/stubs/fakes), fixtures, and coverage targets. Stack-agnostic — referenced by every PHP plugin in the marketplace.

  Use this skill to:
  - Structure unit and integration tests with PHPUnit or Pest consistently.
  - Drive cases with data providers / datasets instead of copy-pasted test bodies.
  - Use test doubles with discipline — mock collaborators, not the system under test.
  - Set up and tear down fixtures cleanly and aim for a meaningful coverage target.

  Do NOT use this skill for:
  - PHP language idioms — see php-foundation:php-conventions.
  - Composer / autoloading — see php-foundation:composer-tooling.
  - Framework-specific test helpers (Laravel RefreshDatabase/actingAs, Symfony WebTestCase/KernelTestCase) — those are injected by the framework plugin's QA phase.
---

# PHP Testing Patterns (stack-agnostic)

Patterns for PHPUnit and Pest that apply to any PHP codebase. Detect which runner the project uses before writing tests: `pestphp/pest` in `require-dev` → Pest; otherwise PHPUnit. Both run on top of PHPUnit assertions.

## Detection and running

```bash
grep -q pestphp/pest composer.json && echo pest || echo phpunit
vendor/bin/phpunit            # PHPUnit
vendor/bin/pest               # Pest
vendor/bin/phpunit --coverage-text   # coverage (needs Xdebug or PCOV)
```

Prefer a `composer test` script if one exists.

## Test structure — Arrange / Act / Assert

PHPUnit (class-based):

```php
<?php

declare(strict_types=1);

namespace App\Tests\Unit;

use App\Domain\Money;
use App\Domain\Currency;
use PHPUnit\Framework\TestCase;

final class MoneyTest extends TestCase
{
    public function test_it_adds_two_amounts_of_the_same_currency(): void
    {
        // Arrange
        $a = new Money(100, Currency::USD);
        $b = new Money(250, Currency::USD);

        // Act
        $sum = $a->add($b);

        // Assert
        self::assertSame(350, $sum->amount);
    }

    public function test_it_rejects_a_currency_mismatch(): void
    {
        $this->expectException(\InvalidArgumentException::class);

        (new Money(100, Currency::USD))->add(new Money(100, Currency::EUR));
    }
}
```

Pest (function-based, same engine):

```php
<?php

declare(strict_types=1);

use App\Domain\Money;
use App\Domain\Currency;

it('adds two amounts of the same currency', function () {
    $sum = (new Money(100, Currency::USD))->add(new Money(250, Currency::USD));

    expect($sum->amount)->toBe(350);
});

it('rejects a currency mismatch', function () {
    expect(fn () => (new Money(100, Currency::USD))->add(new Money(100, Currency::EUR)))
        ->toThrow(InvalidArgumentException::class);
});
```

## Naming and organisation

- Tests live in `tests/`, namespace `App\Tests\...` (mapped via `autoload-dev`).
- Mirror the source tree: `src/Domain/Money.php` → `tests/Unit/Domain/MoneyTest.php`.
- Split `tests/Unit` (pure, no I/O) from `tests/Integration` / `tests/Feature` (DB, HTTP, filesystem).
- PHPUnit method names: `test_it_<behaviour>()` or `#[Test]` attribute. Pest: `it('<behaviour>')`. Describe behaviour, not implementation.

## Data providers / datasets

Drive many cases through one body instead of duplicating tests.

```php
// PHPUnit
public static function discountCases(): array
{
    return [
        'no discount below 100' => [50, 0.0],
        '5% at 100'             => [100, 0.05],
        '15% at 1000'           => [1000, 0.15],
    ];
}

#[DataProvider('discountCases')]
public function test_discount_tiers(int $total, float $expected): void
{
    self::assertSame($expected, discountFor($total));
}
```

```php
// Pest
it('applies discount tiers', function (int $total, float $expected) {
    expect(discountFor($total))->toBe($expected);
})->with([
    [50, 0.0],
    [100, 0.05],
    [1000, 0.15],
]);
```

## Test doubles — mock collaborators, not the SUT

```php
public function test_it_sends_a_receipt_after_charging(): void
{
    $gateway = $this->createMock(PaymentGateway::class);
    $gateway->expects(self::once())
        ->method('charge')
        ->with(self::equalTo(500))
        ->willReturn(new Receipt('rcpt_1'));

    $mailer = $this->createMock(Mailer::class);
    $mailer->expects(self::once())->method('send');

    $service = new CheckoutService($gateway, $mailer);
    $service->checkout($order);
}
```

Discipline:
- **Stub** queries (return canned data); **mock** commands (assert they were called).
- Mock the collaborators of the unit under test — never mock the class you are testing.
- Don't over-specify: assert the interactions that matter, not every call.
- Prefer real value objects and in-memory fakes over mocks for simple data.

## Fixtures — setUp / tearDown

```php
protected function setUp(): void
{
    parent::setUp();
    $this->repository = new InMemoryUserRepository();
}
```

- Build fresh state per test; do not share mutable state across tests (order-dependence is a bug).
- Use `setUp()` for common arrange steps; keep heavy fixtures out of unit tests.
- For DB-backed tests, the framework plugin's QA phase supplies isolation (transactions/rollback) — apply that there.

## Coverage target

- Aim for **≥80%** line coverage on changed code; 100% on domain/business logic.
- Coverage is a floor, not a goal — a covered line is not necessarily an asserted behaviour.
- Run `vendor/bin/phpunit --coverage-text` (requires PCOV or Xdebug). Report the number; do not chase the last few percent on glue code.
