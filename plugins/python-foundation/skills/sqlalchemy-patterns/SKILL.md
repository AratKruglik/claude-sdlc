---
name: sqlalchemy-patterns
description: |
  Framework-agnostic SQLAlchemy 2.0 core shared by fastapi-plugin and flask-plugin: declarative mapped classes with Mapped/mapped_column, column type selection, relationships with explicit lazy loading and cascades, 2.0-style select() querying, transaction/flush discipline, and Alembic-agnostic migration metadata rules. Framework plugins layer their delta skills (async sessions for FastAPI, Flask-SQLAlchemy integration for Flask) on top of this skill.

  Use this skill to:
  - Write SQLAlchemy 2.0 declarative models with Mapped[T] annotations and mapped_column().
  - Pick correct column types (String(N), Numeric, DateTime(timezone=True), Uuid, Enum).
  - Define relationships with explicit lazy loading strategy and cascade settings.
  - Query with 2.0-style select() statements and manage flush vs commit boundaries.
  - Keep model metadata visible to Alembic autogenerate.

  Do NOT use this skill for:
  - FastAPI async engine/session lifecycle — see fastapi-plugin:sqlalchemy-patterns.
  - Flask-SQLAlchemy extension setup and Flask-Migrate — see flask-plugin:sqlalchemy-patterns.
  - Python idioms — see python-foundation:python-conventions.
---

# SQLAlchemy 2.0 Patterns (framework-agnostic core)

## Detection

Read `pyproject.toml` or `requirements.txt` before writing any model code:

```bash
grep -E "sqlalchemy" pyproject.toml requirements.txt
```

- SQLAlchemy **2.0+**: use `Mapped`/`mapped_column` syntax (shown throughout this skill). This is the assumed baseline.
- SQLAlchemy **1.x**: use `Column()`/`relationship()` style. Mark a comment in the code noting the legacy version; do not silently mix styles.

Always prefer 2.0 style for new code. When working in an existing project using 1.x style throughout, match the existing style. Never mix 1.x `Column()` and 2.0 `mapped_column()` in the same model.

---

## Declarative base and mapped classes

Define one `Base` class per project. All models inherit from it. (Framework plugins may supply the base for you — e.g., Flask-SQLAlchemy's `db.Model` — but the mapped-column rules below are identical.)

```python
from datetime import datetime
from decimal import Decimal
from typing import Optional

from sqlalchemy import DateTime, ForeignKey, Numeric, String, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    display_name: Mapped[str] = mapped_column(String(100))
    hashed_password: Mapped[str] = mapped_column(String(255))
    is_active: Mapped[bool] = mapped_column(default=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    orders: Mapped[list["Order"]] = relationship(
        "Order", back_populates="user", lazy="selectin"
    )

    def __repr__(self) -> str:
        return f"<User id={self.id} email={self.email!r}>"
```

Key rules:
- `Mapped[T]` without `Optional` means `NOT NULL`. `Mapped[Optional[T]]` means nullable.
- `mapped_column()` without a SQLAlchemy type uses Python type inference — always provide the type explicitly (e.g., `String(255)`) so the migration specialist can finalize column lengths, precision, and constraints correctly.
- Use `server_default=func.now()` for database-side default timestamps, not Python-side `default=datetime.utcnow` (Python-side defaults are not reflected in the DB schema, and `utcnow` is deprecated).

---

## Column type guidance

| Python type | SQLAlchemy column type | Notes |
|---|---|---|
| `str` | `String(N)` | Always set length; never bare `String` |
| `Decimal` | `Numeric(precision, scale)` | Never `Float` for money or precise values |
| `datetime` | `DateTime(timezone=True)` | Always set `timezone=True` |
| `int` | `Integer` or `BigInteger` | Use `BigInteger` for large tables (users, events) |
| `bool` | `Boolean` | |
| `UUID` | `Uuid` (SA 2.0+) or `String(36)` | `Uuid` stores as native UUID on PostgreSQL |
| enum | `Enum(MyEnum, native_enum=False)` | `native_enum=False` for DB portability |
| `float` | `Float` | Only for non-monetary approximations (lat/lon, scores) |

---

## Querying patterns (2.0 style)

Always use 2.0-style `select()` statements executed through the session. The session/execution style (sync `db.session` vs async `AsyncSession`) comes from the framework delta skill; the statement construction is identical.

```python
from sqlalchemy import select
from sqlalchemy.orm import selectinload

select(User).where(User.id == user_id)                      # single row by predicate
select(User).where(User.email == email)                     # lookup by unique column
select(User).offset(skip).limit(limit)                      # pagination
select(User).options(selectinload(User.orders)).where(...)  # explicit eager load
```

Result handling rules:
- Use `scalar_one_or_none()` for single-row queries.
- Use `scalars().all()` for multi-row queries.
- Use `session.get(Model, pk)` for primary-key lookups where the session API supports it.

Transaction/flush discipline:
- Use `flush()` inside a unit of work to get the generated PK without committing.
- Commit once per request/unit of work at the boundary the framework defines (FastAPI: the `get_db()` dependency on `yield` exit; Flask: the view/service layer at the end of the request) — never scattered through helper functions.

---

## Relationships

Define relationships with **explicit** `lazy` and `cascade` settings. Never rely on defaults.

```python
from sqlalchemy.orm import Mapped, mapped_column, relationship


class User(Base):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)

    orders: Mapped[list["Order"]] = relationship(
        "Order",
        back_populates="user",
        lazy="selectin",
        cascade="all, delete-orphan",
    )

    profile: Mapped[Optional["UserProfile"]] = relationship(
        "UserProfile",
        back_populates="user",
        lazy="selectin",
        uselist=False,
        cascade="all, delete-orphan",
    )


class Order(Base):
    __tablename__ = "orders"

    id: Mapped[int] = mapped_column(primary_key=True)
    user_id: Mapped[int] = mapped_column(ForeignKey("users.id", ondelete="CASCADE"))

    user: Mapped["User"] = relationship("User", back_populates="orders", lazy="selectin")
    lines: Mapped[list["OrderLine"]] = relationship(
        "OrderLine",
        back_populates="order",
        lazy="selectin",
        cascade="all, delete-orphan",
    )
```

Structural rules:
- Always pair both sides with `back_populates`.
- Use `uselist=False` for the scalar side of one-to-one relations.
- Set `ondelete` on the `ForeignKey` (e.g., `"CASCADE"`) so the constraint matches the ORM cascade.

**Lazy loading strategy guide:**
- `lazy="selectin"` — loads the related collection with a separate `SELECT IN` query. Best for small-to-medium collections that are always needed. Safe in both sync and async contexts.
- `lazy="select"` — separate `SELECT` on first attribute access (SQLAlchemy default). Only safe in synchronous contexts; in async it triggers implicit IO and fails.
- `lazy="joined"` — loads the relation with a JOIN in the same query. Best for one-to-one relations or small, always-needed collections.
- `lazy="raise"` — raises if accessed without explicit eager loading, forcing `selectinload()`/`joinedload()` at query time. Best for large or rarely-needed collections to prevent N+1.
- `lazy="subquery"` — sync-only; not supported by async drivers.
- `lazy="dynamic"` — **deprecated in SQLAlchemy 2.0**. Do not use. Replace with explicit `select()` queries.

Which strategies are permitted per framework is refined by the framework delta skill (async contexts forbid `select`/`subquery`).

To prevent N+1 queries on list endpoints, apply eager-load options at query time:

```python
from sqlalchemy.orm import joinedload, selectinload

select(User).options(selectinload(User.orders))
```

---

## Migration metadata rules (Alembic-agnostic)

Both FastAPI (raw Alembic) and Flask (Flask-Migrate, which wraps Alembic) rely on `--autogenerate` reading the metadata object (`Base.metadata` / `db.metadata`).

- **Import all models** before `target_metadata` is set. Any model module not imported is invisible to autogenerate and its tables are silently missed.
- Centralize model imports in one module (e.g., `app/db/base.py` or `app/models/__init__.py`) so a single import guarantees complete metadata.
- The metadata object is the source of truth for `--autogenerate`; explicit column types (lengths, precision, `timezone=True`) are what make the generated migrations correct.
- The migration specialist agent runs migration commands; the architect agent only defines models.

Framework-specific wiring (async `env.py` for FastAPI, `flask db init` scaffolding for Flask) lives in the respective delta skill.

---

## Anti-patterns (shared)

| Anti-pattern | Problem | Correct approach |
|---|---|---|
| `String` without length | Alembic autogenerate produces `VARCHAR` with no length; some databases use `TEXT` or reject it | Always `String(N)` |
| `Float` for monetary values | IEEE 754 rounding errors on financial calculations | `Numeric(precision, scale)` |
| `lazy="dynamic"` | Deprecated in SQLAlchemy 2.0; raises a warning | Use `lazy="selectin"`/`lazy="select"` (per framework) or explicit `selectinload()` |
| `default=datetime.utcnow` | Python-side default — not reflected in DB schema; `utcnow` is deprecated | `server_default=func.now()` with `DateTime(timezone=True)` |
| Importing models only in routers | Migration tooling never sees them; `--autogenerate` misses tables | Import all models in the central metadata module |
| Mixing `Column()` and `mapped_column()` | Produces inconsistent metadata; confuses tooling | One style per project; prefer `mapped_column()` for new code |
| Scattered `commit()` calls in helpers | Makes unit testing harder; unclear transaction boundaries | Commit once per unit of work at the framework-defined boundary; `flush()` for PKs |
