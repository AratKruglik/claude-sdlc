---
name: eloquent-patterns
description: |
  Eloquent ORM best practices: query builders, scopes, relations, N+1 prevention, batch operations, soft deletes, model events, raw queries when needed.
  Apply when: writing or reviewing Eloquent queries and model interactions.
  Activated automatically by laravel-plugin/stack.md as a convention skill for the development phase.
---

# Eloquent Patterns

Patterns for working with Eloquent that catch the common pitfalls (N+1, mass assignment, race conditions on counts, raw SQL injection).

## 1. N+1 prevention

The single most common Eloquent performance bug.

### Problem

```php
$users = User::all();
foreach ($users as $user) {
    echo $user->subscription->plan;  // 1 query per user → N+1
}
```

### Solution: eager loading

```php
$users = User::with('subscription')->get();
foreach ($users as $user) {
    echo $user->subscription?->plan;  // No extra queries
}
```

### Nested eager loading

```php
$users = User::with('subscription.invoices')->get();
```

### Selective columns (further optimization)

```php
$users = User::with(['subscription:id,user_id,plan,status'])->get();
```

### Detection in code review

Look for any `foreach` or `array_map` over an Eloquent collection followed by `->relation` access without `with()` upstream. That's N+1 90% of the time.

## 2. Scopes for reusable query logic

Encapsulate common query fragments as model scopes.

```php
class Subscription extends Model
{
    public function scopeActive(Builder $query): void
    {
        $query->where('status', 'active')
              ->where('ends_at', '>=', now());
    }

    public function scopeForUser(Builder $query, User $user): void
    {
        $query->where('user_id', $user->id);
    }
}

// Usage:
$activeForUser = Subscription::active()->forUser($user)->get();
```

Benefits:
- DRY — definition lives once.
- Testable — scopes can be unit-tested.
- Self-documenting — `Subscription::active()` reads better than `where('status', 'active')->where(...)`.

## 3. Mass assignment safety

```php
class Subscription extends Model
{
    protected $fillable = [
        'user_id',
        'plan',
        'status',
        'starts_at',
    ];
}
```

Then:

```php
Subscription::create($request->validated());  // ✅ safe
```

**Never:**

```php
class Subscription extends Model
{
    protected $guarded = [];  // ❌ — opens door to mass-assigning is_admin, etc.
}
```

## 4. Relations: declare return types

```php
public function user(): BelongsTo
{
    return $this->belongsTo(User::class);
}

public function invoices(): HasMany
{
    return $this->hasMany(Invoice::class);
}

public function paymentMethod(): MorphOne
{
    return $this->morphOne(PaymentMethod::class, 'payable');
}
```

Return types let the IDE / static analyzers understand the relation, and they catch errors at boot time, not runtime.

## 5. Counts and aggregates

### Lazy count (incurs a query each time)

```php
$count = $user->subscriptions()->count();  // 1 query
```

### Eager count

```php
$users = User::withCount('subscriptions')->get();
foreach ($users as $user) {
    echo $user->subscriptions_count;  // 0 extra queries
}
```

### Eager sum / avg / max

```php
$users = User::withSum('subscriptions', 'amount')
             ->withMax('invoices', 'created_at')
             ->get();
```

## 6. Batch operations

### Inserting many rows

```php
// Slow: triggers events per row
foreach ($rows as $row) {
    Model::create($row);
}

// Fast: single query, NO events fired
Model::insert($rows);

// Compromise: chunked + events
Model::query()->chunkById(500, function ($chunk) {
    // process
});
```

If you need events (timestamps, observers), use `Model::insert()` only when you've consciously accepted that timestamps and events won't fire.

### Updating many rows

```php
// One query, no events
Subscription::where('status', 'pending')
    ->where('created_at', '<', now()->subDays(7))
    ->update(['status' => 'expired']);

// Per-row with events (slower)
Subscription::where(...)->each(function ($s) {
    $s->update(['status' => 'expired']);
});
```

## 7. Soft deletes

```php
use Illuminate\Database\Eloquent\SoftDeletes;

class Subscription extends Model
{
    use SoftDeletes;
}
```

Implications:
- Migration must have `$table->softDeletes();`.
- Queries auto-exclude soft-deleted: `Subscription::all()`.
- To include them: `Subscription::withTrashed()->get()`.
- To get only soft-deleted: `Subscription::onlyTrashed()->get()`.
- To restore: `$subscription->restore()`.
- Force delete: `$subscription->forceDelete()`.

Watch out: relations don't auto-cascade soft deletes. Use observers or explicit logic.

## 8. Race conditions on counts/aggregates

Concurrent updates to a counter cause classic race bugs. Use atomic operations.

### Wrong

```php
$user = User::find(1);
$user->credits = $user->credits + 10;  // race
$user->save();
```

### Right (atomic via SQL)

```php
User::where('id', 1)->increment('credits', 10);
```

Or for a balance debit with overflow protection:

```php
$affected = User::where('id', 1)
    ->where('credits', '>=', 10)
    ->decrement('credits', 10);

if ($affected === 0) {
    throw new InsufficientCreditsException();
}
```

## 9. Raw queries — when and how

Sometimes Eloquent isn't enough (CTEs, window functions, complex aggregations). Use raw queries with bindings.

### Right

```php
DB::select(
    'SELECT * FROM subscriptions WHERE user_id = ? AND status = ?',
    [$userId, 'active']
);
```

### Wrong (SQL injection)

```php
DB::select("SELECT * FROM subscriptions WHERE user_id = $userId");  // ❌
DB::raw("user_id = $userId")  // ❌
```

### Right with `whereRaw` + bindings

```php
Subscription::whereRaw('amount > ?', [100])->get();
```

### Right with `selectRaw` for aggregates

```php
$stats = Subscription::query()
    ->selectRaw('plan, COUNT(*) as count, AVG(amount) as avg_amount')
    ->groupBy('plan')
    ->get();
```

## 10. Model events and observers

For cross-cutting behaviors (audit logs, cache invalidation, notifications), use observers — not boot methods inline.

```php
class SubscriptionObserver
{
    public function created(Subscription $subscription): void
    {
        AuditLog::record('subscription.created', $subscription);
    }

    public function deleting(Subscription $subscription): void
    {
        // Cleanup before deletion
    }
}
```

Register in `AppServiceProvider::boot()`:

```php
Subscription::observe(SubscriptionObserver::class);
```

## 11. Checklist before merging Eloquent changes

- [ ] No N+1: every `foreach` over an Eloquent collection has `with()` upstream
- [ ] `$fillable` set on every new/modified model
- [ ] All datetime/decimal columns in `$casts`
- [ ] No `DB::raw()` with string concatenation
- [ ] Atomic operations (`increment`, `decrement`) for counters under concurrency
- [ ] Soft deletes set up correctly (migration + trait) if used
- [ ] Observers used for cross-cutting concerns instead of model boot methods
- [ ] Eager-loaded relations used in views are declared in `with()` of the controller/action
