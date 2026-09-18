---
name: django-orm-patterns
description: |
  Django ORM patterns: model definitions, field types, model managers, custom QuerySet methods, select_related/prefetch_related for N+1 prevention, transactions, F/Q expressions, Meta indexes and constraints. For django-architect (model definitions) and django-migrations-specialist (field finalization). Activated automatically by django-plugin/stack.md.

  Use this skill to:
  - Write clean, efficient Django model definitions with proper field choices and __str__.
  - Use custom managers and QuerySets to encapsulate query logic.
  - Prevent N+1 queries with select_related and prefetch_related.
  - Use transactions for atomic operations.
  - Define Meta indexes and constraints (for django-migrations-specialist to finalize).

  Do NOT use this skill for:
  - Creating actual migrations (makemigrations) — that is django-migrations-specialist.
  - Web view / API patterns — see django-plugin:django-conventions.
  - Python idioms — see python-foundation:python-conventions.
user-invocable: false
paths: ["**/*.py", "**/migrations/**"]
---

# Django ORM Patterns

This skill covers Django ORM model definitions, query patterns, and database-level options. Apply alongside `django-plugin:django-conventions` when implementing features.

**Role split:**
- `django-architect` uses this skill for model *definitions* — fields, `__str__`, choices, `class Meta` ordering, custom managers, and query patterns.
- `django-migrations-specialist` uses this skill for field *finalization* — setting `max_digits`, `on_delete`, `db_index`, `Meta.indexes`, `Meta.constraints` — before running `makemigrations`.

## 1. Detection

Check the Django version in `requirements.txt` or `pyproject.toml` before writing constraint code — `Meta.constraints` using `CheckConstraint` uses `condition=` in Django 5.1+ and `check=` in Django 4.x. When uncertain, check the installed version with `python manage.py --version` or read the pinned version from the dependency file.

## 2. Model definition patterns

Use `TextChoices` for string-typed status/type fields. Write a meaningful `__str__`. Always specify `class Meta` ordering.

```python
from django.db import models
from django.contrib.auth import get_user_model

User = get_user_model()


class Order(models.Model):
    class Status(models.TextChoices):
        PENDING = 'pending', 'Pending'
        PROCESSING = 'processing', 'Processing'
        SHIPPED = 'shipped', 'Shipped'
        CANCELLED = 'cancelled', 'Cancelled'

    user = models.ForeignKey(User, on_delete=models.PROTECT, related_name='orders')
    product = models.CharField(max_length=255)
    qty = models.PositiveIntegerField()
    unit_price = models.DecimalField(max_digits=10, decimal_places=2)
    status = models.CharField(max_length=20, choices=Status.choices, default=Status.PENDING)
    notes = models.TextField(blank=True, default='')
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [
            models.Index(fields=['status', 'created_at']),
        ]
        constraints = [
            models.UniqueConstraint(fields=['user', 'reference'], name='unique_user_reference'),
            # Django 5.1+: condition=; Django 4.x: check=
            models.CheckConstraint(condition=models.Q(qty__gt=0), name='orders_order_qty_positive'),
        ]

    def __str__(self) -> str:
        return f'Order #{self.pk} — {self.product} ({self.get_status_display()})'

    @property
    def is_cancellable(self) -> bool:
        return self.status in (self.Status.PENDING, self.Status.PROCESSING)
```

## 3. Custom managers and QuerySets

Encapsulate common query logic in a custom `QuerySet` and expose it via a manager. Use `as_manager()` for the shortcut form when you don't need manager-specific methods.

```python
from django.db import models


class OrderQuerySet(models.QuerySet):
    def active(self) -> 'OrderQuerySet':
        return self.exclude(status=Order.Status.CANCELLED)

    def by_user(self, user) -> 'OrderQuerySet':
        return self.filter(user=user)

    def pending(self) -> 'OrderQuerySet':
        return self.filter(status=Order.Status.PENDING)


class OrderManager(models.Manager):
    def get_queryset(self) -> OrderQuerySet:
        return OrderQuerySet(self.model, using=self._db)

    def active(self) -> OrderQuerySet:
        return self.get_queryset().active()

    def for_dashboard(self, user) -> OrderQuerySet:
        return self.get_queryset().by_user(user).active().select_related('user')


class Order(models.Model):
    objects = OrderManager()
    # shortcut form (no custom manager methods needed):
    # objects = OrderQuerySet.as_manager()
    ...
```

Usage: `Order.objects.active()`, `Order.objects.for_dashboard(request.user)`.

## 4. N+1 prevention

Always load related objects in advance when iterating. The most common Django performance problem is accessing a FK in a loop without prefetching.

### `select_related` — SQL JOIN for FK/OneToOne

```python
# Bad: triggers 1 query per order to fetch user
orders = Order.objects.all()
for order in orders:
    print(order.user.email)  # N+1

# Good: single JOIN query
orders = Order.objects.select_related('user').all()
```

### `prefetch_related` — separate query for ManyToMany / reverse FK

```python
# Prefetch all items for each order in a single extra query
orders = Order.objects.prefetch_related('items').all()

# Custom prefetch with its own queryset
from django.db.models import Prefetch

orders = Order.objects.prefetch_related(
    Prefetch('items', queryset=OrderItem.objects.select_related('product'))
)
```

### `only()` and `defer()` for field projection

```python
# Fetch only the columns you need
orders = Order.objects.only('id', 'status', 'created_at')

# Defer a large column (e.g., rich text body)
articles = Article.objects.defer('body')
```

## 5. F expressions and Q objects

### `F()` — reference a field value in the database

```python
from django.db.models import F

# Atomic increment — no race condition
Order.objects.filter(pk=pk).update(qty=F('qty') + 1)

# Compare two fields
Order.objects.filter(shipped_at__lt=F('created_at'))
```

### `Q()` — complex OR / AND queries

```python
from django.db.models import Q

# OR
Order.objects.filter(Q(status='pending') | Q(status='processing'))

# NOT
Order.objects.filter(~Q(status='cancelled'))

# AND + OR combined
Order.objects.filter(
    Q(user=request.user) & (Q(status='pending') | Q(status='processing'))
)
```

### `annotate()` with aggregates

```python
from django.db.models import Count, Sum, Avg

# Count orders per user
from apps.users.models import User
users = User.objects.annotate(order_count=Count('orders'))

# Sum order totals per user
users = User.objects.annotate(
    total_spend=Sum(F('orders__qty') * F('orders__unit_price'))
)
```

## 6. Transactions

Use `@transaction.atomic` or the context manager form to wrap operations that must succeed or fail together.

```python
from django.db import transaction


@transaction.atomic
def place_order(user, product: str, qty: int) -> Order:
    order = Order.objects.create(user=user, product=product, qty=qty)
    inventory = Inventory.objects.select_for_update().get(product=product)
    if inventory.stock < qty:
        raise ValueError("Insufficient stock")
    inventory.stock = F('stock') - qty
    inventory.save(update_fields=['stock'])
    return order
```

### `transaction.on_commit()` — run after the transaction commits

Use this to enqueue async tasks. Never enqueue a task from inside an atomic block directly — if the transaction rolls back, the task will still run.

```python
from django.db import transaction

def place_order(user, product: str, qty: int) -> Order:
    with transaction.atomic():
        order = Order.objects.create(user=user, product=product, qty=qty)
        transaction.on_commit(lambda: send_confirmation_email.delay(order.pk))
    return order
```

## 7. Meta indexes and constraints

These are *defined* in model code by `django-architect` and *finalized* (verified, regenerated after version check) by `django-migrations-specialist`.

```python
class Meta:
    indexes = [
        models.Index(fields=['status', 'created_at']),         # composite index for common filter
        models.Index(fields=['user'], name='orders_user_idx'),  # explicit name
    ]
    constraints = [
        models.UniqueConstraint(
            fields=['user', 'reference'],
            name='unique_order_reference_per_user',
        ),
        # Django 5.1+: condition=  |  Django 4.x: check=
        models.CheckConstraint(
            condition=models.Q(qty__gt=0),
            name='orders_order_qty_must_be_positive',
        ),
    ]
```

Name conventions: `<app>_<model>_<description>` — keeps names unique and self-documenting.

## 8. Anti-patterns

| Don't | Do |
|---|---|
| `.filter(...)` inside a loop | Batch with `__in`: `Order.objects.filter(pk__in=ids)` |
| Access FK attribute in a loop without prefetch | Use `select_related` (FK/1:1) or `prefetch_related` (M2M/reverse FK) |
| Update many objects one by one with `.save()` | `QuerySet.update(status='shipped')` for bulk updates |
| `.save()` for single-field updates | `obj.save(update_fields=['status'])` — avoids overwriting concurrent writes |
| `Order.objects.all()` then filter in Python | Push filtering to the DB with `.filter()` / `.exclude()` |
| Raw SQL with f-strings: `.raw(f'... {user_id}')` | Parameterized: `.raw('... WHERE id = %s', [user_id])` or use ORM |
