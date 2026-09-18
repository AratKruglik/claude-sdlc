---
name: sqlalchemy-patterns
description: |
  FastAPI-specific delta on top of python-foundation:sqlalchemy-patterns: async engine and AsyncSession lifecycle, get_db dependency injection, async-safe lazy loading rules, async Alembic env.py wiring. Used by fastapi-architect (model definitions) and alembic-specialist (column type finalization and migration generation). Activated automatically by fastapi-plugin/stack.md.

  Use this skill to:
  - Manage async database sessions with AsyncSession and async_sessionmaker.
  - Inject sessions into routes via the get_db() dependency.
  - Apply async-safe lazy loading (lazy="selectin" or "raise"; never sync lazy loads).
  - Integrate async Alembic env.py for migration autogeneration.

  Do NOT use this skill for:
  - Framework-agnostic model, column, relationship, and querying rules — see python-foundation:sqlalchemy-patterns (load it first).
  - FastAPI routing and Pydantic schemas — see fastapi-plugin:fastapi-conventions.
  - Alembic migration execution (that's alembic-specialist's job) — this skill covers definitions.
user-invocable: false
paths: ["**/*.py"]
---

# SQLAlchemy Patterns for FastAPI (async delta)

**Load `python-foundation:sqlalchemy-patterns` via the Skill tool FIRST.** It contains the shared SQLAlchemy 2.0 core: detection, `Mapped`/`mapped_column` model definition, column type guidance, `select()` querying, relationship structure, lazy-strategy overview, and migration metadata rules. This skill covers only the async/FastAPI delta.

---

## Async session setup

```python
# app/db/session.py
from collections.abc import AsyncGenerator

from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine

from app.core.config import settings

engine = create_async_engine(
    settings.DATABASE_URL,
    echo=False,
    pool_pre_ping=True,
    pool_size=10,
    max_overflow=20,
)

AsyncSessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
```

Use `expire_on_commit=False` so that model attributes remain accessible after a commit without triggering lazy loads — important in async contexts where implicit IO is not allowed.

Use `pool_pre_ping=True` to detect stale connections before use.

The `get_db()` dependency owns the transaction boundary: it commits on successful `yield` exit and rolls back on exception. Never call `session.commit()` in a router handler.

---

## Async querying

Every execution is awaited; statement construction follows the foundation skill.

```python
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.users.models import User


async def get_user_by_id(db: AsyncSession, user_id: int) -> User | None:
    result = await db.execute(select(User).where(User.id == user_id))
    return result.scalar_one_or_none()


async def get_user_with_orders(db: AsyncSession, user_id: int) -> User | None:
    result = await db.execute(
        select(User)
        .options(selectinload(User.orders))
        .where(User.id == user_id)
    )
    return result.scalar_one_or_none()


async def create_user(db: AsyncSession, email: str, hashed_password: str, display_name: str) -> User:
    user = User(email=email, hashed_password=hashed_password, display_name=display_name)
    db.add(user)
    await db.flush()  # assigns id without committing; session.commit() happens in get_db()
    return user
```

---

## Async lazy loading rules

The foundation skill defines the lazy-strategy catalog; in async contexts only a subset is safe:

- `lazy="selectin"` — safe; loads collections with a separate `SELECT IN` query.
- `lazy="raise"` — safe; raises `MissingGreenlet` if accessed without explicit eager loading, forcing `selectinload()` at query time. Best for large or rarely-needed collections.
- `lazy="select"` (the SQLAlchemy default) — **forbidden**: sync lazy load raises in async context. Never leave a `relationship()` without an explicit `lazy=`.
- `lazy="subquery"` — **forbidden**: not supported by async drivers.

---

## Alembic integration (async)

### alembic.ini

Point `script_location` to the `alembic/` directory and configure the async database URL:

```ini
[alembic]
script_location = alembic
sqlalchemy.url = driver://user:pass@localhost/dbname
```

The URL in `alembic.ini` is overridden in `env.py` — do not put production credentials here.

### env.py — async pattern

```python
# alembic/env.py
import asyncio
from logging.config import fileConfig

from alembic import context
from sqlalchemy.ext.asyncio import create_async_engine

from app.core.config import settings
from app.db.base import Base  # import all models so Base.metadata is populated

config = context.config
fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    context.configure(
        url=settings.DATABASE_URL,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
    )
    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    connectable = create_async_engine(settings.DATABASE_URL)
    async with connectable.connect() as connection:
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


def do_run_migrations(connection):
    context.configure(connection=connection, target_metadata=target_metadata)
    with context.begin_transaction():
        context.run_migrations()


def run_migrations_online() -> None:
    asyncio.run(run_async_migrations())


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
```

Per the foundation skill's metadata rules, import every model before `target_metadata = Base.metadata`. The FastAPI convention is an `app/db/base.py` aggregator:

```python
# app/db/base.py
from app.db.session import Base  # noqa: F401 — must import Base
from app.users.models import User  # noqa: F401
from app.orders.models import Order, OrderLine  # noqa: F401
```

---

## Async anti-patterns

| Anti-pattern | Problem | Correct approach |
|---|---|---|
| `session.execute(select(...))` without `await` on `AsyncSession` | Implicit IO in async — raises `MissingGreenlet` | Always `await session.execute(...)` |
| `session.commit()` in a router handler | Couples transport layer to transaction lifecycle | Let the `get_db()` dependency commit on `yield` exit |
| Bare `relationship()` with no `lazy=` | Defaults to `lazy="select"` (sync lazy load) — raises in async context | Always set `lazy="selectin"` or `lazy="raise"` |
| `lazy="subquery"` on any relationship | Not supported by async drivers | `lazy="selectin"` or query-time `selectinload()` |
