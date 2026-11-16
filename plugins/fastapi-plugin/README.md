# fastapi-plugin

FastAPI backend + database stack provider for the `claude-sdlc` marketplace.

This is an **API-only** plugin. FastAPI does not render server-side HTML templates. SPA frontends (Vue, React) connect to the FastAPI application via the API contract that `fastapi-architect` designs and documents. The frontend aspect is handled by whichever frontend plugin is active (`vue-plugin`, `react-plugin`, etc.).

---

## Agents

| Agent | Phase | Aspect | Model / Effort | Responsibilities |
|---|---|---|---|---|
| `fastapi-architect` | development | backend | Sonnet / medium | APIRouter endpoint groups, Pydantic v2 request/response schemas, `Depends` injection chain, async endpoints, OAuth2 password bearer + JWT authentication, OpenAPI metadata customization, SQLAlchemy ORM model *definitions* (column stubs), lifespan context manager, `pydantic-settings` configuration, API contract for SPA frontend architects |
| `alembic-specialist` | database (extra) | database | Sonnet / low | SQLAlchemy 2.0 mapped class finalization (column types, nullable, indexes, unique constraints, relationships with cascade and load strategy), `alembic revision --autogenerate`, migration script review, `alembic upgrade head`, verification with `alembic check`, rollback test |

---

## Skills

| Skill | Registered as | Summary |
|---|---|---|
| `fastapi-conventions` | `fastapi-plugin:fastapi-conventions` | APIRouter structure, Pydantic v2 schemas, `Depends` dependency chain, OAuth2/JWT, `pydantic-settings`, lifespan, `HTTPException` handling |
| `sqlalchemy-patterns` | `fastapi-plugin:sqlalchemy-patterns` | SQLAlchemy 2.0 `Mapped`/`mapped_column` declarative models, `AsyncSession`, relationships with explicit lazy loading, Alembic integration |

Also reuses:

- `python-foundation:python-conventions`
- `python-foundation:python-tooling`
- `python-foundation:pytest-testing`

---

## Dependencies

| Dependency | Role |
|---|---|
| `sdlc` | Core pipeline orchestration |
| `python-foundation` | Python conventions, tooling, and pytest patterns |

---

## Installation

```bash
/plugin install fastapi-plugin@sdlc-marketplace
# sdlc and python-foundation install as dependencies
```

The plugin activates automatically when `fastapi` is found in `pyproject.toml`, `requirements.txt`, `Pipfile`, `setup.py`, or `setup.cfg`.

---

## API-only note

FastAPI is an API-only framework — `fastapi-architect` produces no server-rendered HTML. When a SPA frontend plugin (`vue-plugin`, `react-plugin`) is also active, `fastapi-architect` writes an explicit **API contract** section in `docs/plans/{task_slug}/02-development.md` describing each endpoint path, HTTP method, and Pydantic request/response schema. The frontend architect reads this contract to implement the UI.
