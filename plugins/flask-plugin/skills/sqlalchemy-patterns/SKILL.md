---
name: sqlalchemy-patterns
description: |
  Flask-specific delta on top of python-foundation:sqlalchemy-patterns: Flask-SQLAlchemy extension setup, db.Model declarative models (3.x Mapped style and 2.x legacy db.Column), synchronous db.session lifecycle bound to the app context, Flask-Migrate integration. Used by flask-architect (model definitions) and flask-migrate-specialist (column finalization and migration). Activated automatically by flask-plugin/stack.md.

  Use this skill to:
  - Set up the SQLAlchemy and Migrate extensions with the app-factory pattern.
  - Write Flask-SQLAlchemy models with the db.Model base.
  - Query with db.session and manage the request-scoped session lifecycle.
  - Integrate Flask-Migrate for Alembic-based migrations managed via flask db commands.

  Do NOT use this skill for:
  - Framework-agnostic model, column, relationship, and querying rules — see python-foundation:sqlalchemy-patterns (load it first).
  - Flask routing and template/API patterns — see flask-plugin:flask-conventions.
  - Migration execution (flask db migrate, flask db upgrade) — that's flask-migrate-specialist's job.
user-invocable: false
paths: ["**/*.py"]
---

# SQLAlchemy Patterns for Flask (sync delta)

**Load `python-foundation:sqlalchemy-patterns` via the Skill tool FIRST.** It contains the shared SQLAlchemy 2.0 core: detection, `Mapped`/`mapped_column` model definition, column type guidance, `select()` querying, relationship structure, lazy-strategy overview, and migration metadata rules. This skill covers only the Flask-SQLAlchemy delta.

---

## Version detection

Beyond the foundation skill's SQLAlchemy detection, determine the Flask-SQLAlchemy version:

```bash
grep -E "flask.sqlalchemy" requirements.txt pyproject.toml
```

- **Flask-SQLAlchemy 3.x** (released 2022+): Uses SQLAlchemy 2.0 under the hood. Supports `Mapped`/`mapped_column` style with `db.Model`. This is the baseline for new projects.
- **Flask-SQLAlchemy 2.x** (legacy): Uses `db.Column()` style. Still common in existing projects.

Always use **Flask-SQLAlchemy 3.x style** for new code. When working in an existing project using 2.x style throughout, match the existing style. Never mix `db.Column()` and `mapped_column()` in the same model.

---

## Extension setup

Define extensions at module level in `app/extensions.py` and call `.init_app(app)` in the factory. This avoids circular imports and allows multiple app instances for testing.

```python
# app/extensions.py
from flask_migrate import Migrate
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()
migrate = Migrate()
```

Initialize in the factory:

```python
# app/__init__.py
from app.extensions import db, migrate


def create_app(config_name: str = "development") -> Flask:
    app = Flask(__name__)
    app.config.from_object(config_by_name[config_name])

    db.init_app(app)
    migrate.init_app(app, db)

    return app
```

---

## Model definition with db.Model

Models inherit from `db.Model` instead of a hand-written `DeclarativeBase`; all mapped-column, typing, and relationship rules from the foundation skill apply unchanged.

```python
from datetime import datetime

from sqlalchemy import DateTime, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.extensions import db


class User(db.Model):
    __tablename__ = "users"

    id: Mapped[int] = mapped_column(primary_key=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )

    orders: Mapped[list["Order"]] = relationship(
        "Order", back_populates="user", lazy="select"
    )
```

### Flask-SQLAlchemy 2.x with db.Column (legacy)

```python
from app.extensions import db


class User(db.Model):
    __tablename__ = "users"

    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(255), unique=True, nullable=False)
    display_name = db.Column(db.String(100), nullable=False)
    hashed_password = db.Column(db.String(255), nullable=False)
    is_active = db.Column(db.Boolean, default=True)
    created_at = db.Column(db.DateTime(timezone=True), server_default=db.func.now())

    orders = db.relationship("Order", back_populates="user", lazy="select")

    def __repr__(self) -> str:
        return f"<User id={self.id} email={self.email!r}>"
```

---

## Session lifecycle and querying (synchronous)

Flask-SQLAlchemy uses synchronous sessions. All queries are blocking — no `await`, no async generators. Statement construction follows the foundation skill; execution goes through `db.session`.

```python
from sqlalchemy import select

from app.extensions import db
from app.users.models import User


def get_user_by_id(user_id: int) -> User | None:
    return db.session.get(User, user_id)


def get_user_by_email(email: str) -> User | None:
    return db.session.execute(
        select(User).where(User.email == email)
    ).scalar_one_or_none()


def create_user(email: str, hashed_password: str, display_name: str) -> User:
    user = User(email=email, hashed_password=hashed_password, display_name=display_name)
    db.session.add(user)
    db.session.flush()  # assigns id without committing
    return user


def delete_user(user: User) -> None:
    db.session.delete(user)
```

**Session lifecycle in Flask:** Flask-SQLAlchemy automatically calls `db.session.remove()` at the end of each request via `teardown_appcontext`. This closes the session and returns the connection to the pool. You do not need to call `db.session.close()` manually in view functions.

**When to commit:** call `db.session.commit()` in the view function or service after all writes are complete for the request. Use `db.session.flush()` inside a unit of work to get the generated PK without committing.

```python
@orders_bp.route("/", methods=["POST"])
@login_required
def create_order_view():
    data = order_create_schema.load(request.get_json())
    order = create_order(data)
    db.session.commit()
    return jsonify(order_schema.dump(order)), 201
```

---

## Lazy loading in synchronous Flask

The foundation skill's lazy-strategy catalog applies; in synchronous Flask the sync-only strategies are also valid:

- `lazy="select"` — the SQLAlchemy default; loads on first attribute access with a separate `SELECT`. Safe in synchronous Flask (unlike async FastAPI, where it can block the event loop).
- `lazy="joined"` — JOIN in the same query; best for one-to-one relations or small, always-needed collections.
- `lazy="subquery"` — valid in synchronous Flask (unlike async where it is not supported). Useful for loading collections alongside the parent.
- `lazy="dynamic"` — deprecated in 2.0, do not use (see foundation skill).

For N+1 prevention on list endpoints, use query-time `options(joinedload(...))` or `options(selectinload(...))` as shown in the foundation skill.

---

## Flask-Migrate integration

Flask-Migrate wraps Alembic. Running `flask db init` scaffolds the `migrations/` directory including `migrations/env.py` and `migrations/alembic.ini`. Do not hand-write `env.py` — Flask-Migrate generates a synchronous configuration automatically.

```
migrations/
    alembic.ini
    env.py          — generated by flask db init; imports db.metadata
    script.py.mako
    versions/       — generated migration scripts live here
```

Per the foundation skill's metadata rules, all model modules must be imported before `target_metadata = db.metadata`. The Flask convention is to import them in `app/models/__init__.py` or in the app factory:

```python
# app/__init__.py
def create_app(config_name: str = "development") -> Flask:
    app = Flask(__name__)
    app.config.from_object(config_by_name[config_name])

    db.init_app(app)
    migrate.init_app(app, db)

    # Import models so Flask-Migrate sees them in db.metadata
    with app.app_context():
        from app.users import models as _user_models  # noqa: F401
        from app.orders import models as _order_models  # noqa: F401

    _register_blueprints(app)
    return app
```

Flask-migrate-specialist runs `flask db migrate` and `flask db upgrade`. Flask-architect only **defines the models**. Never call `flask db` commands from flask-architect.

---

## Flask-specific anti-patterns

| Anti-pattern | Problem | Correct approach |
|---|---|---|
| `db.session.commit()` in every helper function | Makes unit testing harder; scattered transaction boundaries | Commit at the end of the request in the view or service layer |
| Mixing `db.Column()` and `mapped_column()` | Produces inconsistent metadata; confuses tooling | One style per project; prefer `mapped_column()` for new code |
| Importing models only in routers | Flask-Migrate's `env.py` never sees them; `--autogenerate` misses tables | Import all models in the app factory or `app/models/__init__.py` |
