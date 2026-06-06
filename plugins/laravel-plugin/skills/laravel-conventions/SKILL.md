---
name: laravel-conventions
description: |
  Consolidated Laravel project conventions: Action pattern, Form Requests, Policies, routing, Inertia integration, code style.
  Apply when: writing or reviewing Laravel backend code (controllers, actions, requests, policies, providers).
  Activated automatically by laravel-plugin/stack.md as a convention skill for the development phase.
---

# Laravel Conventions

This skill encodes the conventions used across modern Laravel + Inertia + Vue projects. Apply when implementing features in such projects.

## 1. Routing

### Web vs API

- **`routes/web.php`** — Inertia / browser-driven flows. Has session, CSRF, web middleware.
- **`routes/api.php`** — JSON-only flows. Stateless. Token-authenticated.

Don't put Inertia render calls in `api.php`. Don't put JSON-API endpoints in `web.php` (use a separate `/api/internal/...` namespace if absolutely needed).

### Route style

```php
// Preferred: explicit routes with action classes
Route::post('subscriptions', CreateSubscriptionAction::class)
    ->name('subscriptions.store')
    ->middleware(['auth', 'verified']);

// Acceptable: resource controllers for plain CRUD
Route::resource('subscriptions', SubscriptionController::class)
    ->only(['index', 'show', 'store', 'destroy']);

// Avoid: closures in routes (no caching, no testability)
// Route::post('subscriptions', function (Request $r) { ... });  // DON'T
```

## 2. Action pattern (preferred for non-trivial business logic)

A single-action invokable class that does one thing.

```php
namespace App\Actions;

use App\Models\Subscription;
use App\Http\Requests\StoreSubscriptionRequest;
use Inertia\Response;

class CreateSubscriptionAction
{
    public function __invoke(StoreSubscriptionRequest $request): Response
    {
        $this->authorize('create', Subscription::class);

        $subscription = DB::transaction(function () use ($request) {
            $stripeCustomer = app(StripeClient::class)->customers->create([
                'email' => $request->user()->email,
            ]);

            return Subscription::create([
                'user_id' => $request->user()->id,
                'stripe_customer_id' => $stripeCustomer->id,
                'status' => 'trialing',
                ...$request->validated(),
            ]);
        });

        SubscriptionCreated::dispatch($subscription);

        return Inertia::render('Subscription/Show', [
            'subscription' => $subscription,
        ]);
    }
}
```

When to prefer Action over Controller method:
- Logic spans 3+ steps
- Uses transactions
- Dispatches events / jobs
- Will be invoked from multiple places (e.g., HTTP + queue worker)

When a plain controller method is fine:
- Single Eloquent operation
- No side effects
- Simple resource CRUD

## 3. Form Requests for validation

**Always** extract validation into a Form Request class. Never inline `$request->validate()`.

```php
namespace App\Http\Requests;

use Illuminate\Foundation\Http\FormRequest;

class StoreSubscriptionRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()->can('create', Subscription::class);
    }

    public function rules(): array
    {
        return [
            'plan' => ['required', 'string', 'in:basic,pro,enterprise'],
            'starts_at' => ['nullable', 'date', 'after_or_equal:today'],
            'payment_method_id' => ['required', 'string'],
        ];
    }

    public function messages(): array
    {
        return [
            'plan.in' => 'Plan must be one of: basic, pro, enterprise.',
        ];
    }
}
```

The `authorize()` method is the first line of defense — ALWAYS implement it. Returning `true` blindly defeats Laravel's auth pipeline.

## 4. Policies for authorization

Every model that has owner-or-admin access patterns gets a Policy.

```php
namespace App\Policies;

use App\Models\Subscription;
use App\Models\User;

class SubscriptionPolicy
{
    public function view(User $user, Subscription $subscription): bool
    {
        return $user->id === $subscription->user_id || $user->isAdmin();
    }

    public function update(User $user, Subscription $subscription): bool
    {
        return $user->id === $subscription->user_id;
    }

    public function delete(User $user, Subscription $subscription): bool
    {
        return $user->isAdmin();
    }
}
```

Register in `AuthServiceProvider::$policies`. Use via `$this->authorize('update', $subscription)` in actions/controllers, or `Gate::authorize('update', $subscription)`.

**Never** inline role checks: `if ($user->role === 'admin') { ... }` — that bypasses Laravel's auth pipeline and makes testing harder.

## 5. Eloquent models

```php
namespace App\Models;

use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Casts\Attribute;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

class Subscription extends Model
{
    use SoftDeletes;

    protected $fillable = [
        'user_id',
        'stripe_customer_id',
        'plan',
        'status',
        'starts_at',
        'ends_at',
    ];

    protected $casts = [
        'starts_at' => 'datetime',
        'ends_at'   => 'datetime',
        'amount'    => 'decimal:2',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    protected function isActive(): Attribute
    {
        return Attribute::get(fn () => $this->status === 'active' && $this->ends_at?->isFuture());
    }
}
```

- `$fillable` is mandatory. Never `$guarded = []`.
- `$casts` for everything that isn't a string.
- Relations use return-type declarations (`BelongsTo`, `HasMany`).
- Use `Attribute::get()` for computed properties — clean and cacheable.

## 6. Inertia integration

Pass typed data to Inertia pages:

```php
return Inertia::render('Subscription/Show', [
    'subscription' => fn () => SubscriptionResource::make($subscription),
    'paymentMethods' => fn () => PaymentMethodResource::collection($user->paymentMethods),
]);
```

Use closures for lazy props — Inertia only evaluates them on full reload, not partial.

API Resources prevent leaking model internals to the frontend:

```php
class SubscriptionResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'plan' => $this->plan,
            'status' => $this->status,
            'starts_at' => $this->starts_at?->toISOString(),
            // NEVER $this->stripe_customer_id — stays internal
        ];
    }
}
```

## 7. Code style

General PHP style (PSR-12, `declare(strict_types=1)`, enums, readonly, single quotes, `fn` arrow functions) lives in `php-foundation:php-conventions` — follow it. Laravel-specific additions on top:

- Pint runs auto-fix on the Stop hook (laravel-plugin provides one) — do not hand-tune whitespace Pint owns.
- PHPStan / Larastan level 6+ where the project supports it.

## 8. Anti-patterns to avoid

| Don't | Do |
|---|---|
| `$request->all()` into model | Specify fields, or use `$request->validated()` |
| `User::where('role', 'admin')->get()` | Add a scope: `User::admins()->get()` |
| Logic in Blade templates | Move to Action / Resource / view-helper |
| Eager-load everywhere | Eager-load only what the view needs (use `with()` selectively) |
| `DB::raw('...')` with concatenation | Parameter bindings always |
| Closure in routes | Action class or controller |

## 9. Checklist before completing development phase

- [ ] All new routes have explicit middleware (`auth`, `verified`, etc.)
- [ ] All Form Requests have `authorize()` returning a real check
- [ ] All Policies registered in `AuthServiceProvider`
- [ ] All models have `$fillable` (never `$guarded = []`)
- [ ] All datetime/decimal columns have `$casts`
- [ ] All Inertia pages get typed data through Resources, not raw models
- [ ] `./vendor/bin/pint` clean
- [ ] `php -l <changed-file>` passes for each changed PHP file
