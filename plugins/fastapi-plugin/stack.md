---
stack: fastapi
priority: 150
aspects: [backend, database]
detect:
  any:
    - file_contains:
        path: pyproject.toml
        pattern: "fastapi"
    - file_contains:
        path: requirements.txt
        pattern: "fastapi"
---

# FastAPI Stack Profile (backend + database)

Registers FastAPI projects with the SDLC pipeline. Auto-detected by `fastapi` listed in `pyproject.toml` or `requirements.txt`.

This plugin owns the **backend** and **database** aspects. FastAPI is an API-only framework — there are no server-rendered templates. `fastapi-architect` designs and documents the endpoint/schema contract for SPA frontend plugins (vue/react):

- FastAPI APIRouter endpoints, Pydantic v2 schemas, auth → handled by `fastapi-architect` (backend aspect)
- SQLAlchemy 2.0 model finalization, Alembic migrations → handled by `alembic-specialist` (database aspect, extra phase)
- Vue / React SPA → a frontend-aspect plugin (`vue-plugin`, `react-plugin`) wins the frontend aspect; `fastapi-architect` provides the API contract it consumes

## Agents per phase

```yaml
business_analysis: business-analyst    # core agent
development:
  backend: fastapi-architect           # owned by this plugin
database: alembic-specialist           # extra phase, aspect=database
qa: qa-engineer                        # core agent
security: security-analyst             # core agent
documentation: document-writer         # core agent
```

Note: this plugin does NOT declare `development.frontend`. That slot is filled by whichever frontend-aspect plugin is active in the project (for SPA frontends). FastAPI has no server-rendered template layer.

## Convention skills to apply

- python-foundation:python-conventions
- python-foundation:python-tooling
- python-foundation:pytest-testing
- fastapi-plugin:fastapi-conventions
- fastapi-plugin:sqlalchemy-patterns

## Extra phases

- name: database
  after: development
  agent: alembic-specialist
  aspect: database
  description: |
    Finalize SQLAlchemy 2.0 mapped class configurations (column types, indexes, unique constraints, relationships with cascade/load strategy), run alembic revision --autogenerate, review the generated migration script, run alembic upgrade head, verify no pending revisions.
    Skip if the development phase made no ORM model changes.

## Phase prompts injection

For development phase (backend aspect), inject:
> You are working on the **backend** aspect of a **FastAPI** project. Your scope:
> - `APIRouter` endpoint groups, Pydantic v2 request/response schemas, `Depends` injection chain, async handlers, OAuth2/JWT security, OpenAPI metadata, SQLAlchemy ORM model *definitions* (alembic-specialist finalizes column types, indexes, and runs migrations in the next phase), lifespan context manager, and `pydantic-settings` configuration.
> - For SPA frontends (Vue/React) the frontend-aspect agent runs separately and handles UI — you design and document the API contract (endpoint path + method + Pydantic request/response schema) it consumes. FastAPI has no server-rendered template layer.
>
> Read `pyproject.toml` to learn the FastAPI version (0.100+ uses Pydantic v2 by default) and SQLAlchemy version (2.0+ uses `Mapped`/`mapped_column` syntax).
>
> Available tools via Bash:
> - `uvicorn app.main:app --reload` — run the dev server
> - `python -m pytest` — run tests
>
> Apply `fastapi-plugin:fastapi-conventions`:
> - **APIRouter:** one router per feature module with `prefix` and `tags`. Include routers in the app factory via `app.include_router(...)`.
> - **Pydantic v2 schemas:** `BaseModel` with `model_config = ConfigDict(from_attributes=True)` for ORM mode. Use `@field_validator` and `@model_validator` for cross-field validation. Separate `Create`, `Update`, and `Read` schemas when field sets differ.
> - **Dependency injection:** `Depends()` for DB session, auth, and pagination. Yield `AsyncSession` from `get_db()`. Use `app.dependency_overrides` in tests.
> - **Response model:** always set `response_model=` on each endpoint to filter output. Use `JSONResponse` only for custom status codes.
> - **Auth:** `OAuth2PasswordBearer(tokenUrl="/auth/token")` + JWT. Implement `get_current_user` dependency that decodes and validates the token. Never store the JWT secret in source code.
> - **Lifespan:** use `@asynccontextmanager async def lifespan(app)` for startup/shutdown (DB pool init/close). Pass to `FastAPI(lifespan=lifespan)`.
> - **Settings:** `pydantic-settings` `class Settings(BaseSettings)` reading from environment variables and `.env`. Never hardcode secrets.
> - **Async:** all I/O-bound handlers must be `async def`. DB calls via `AsyncSession`. No sync blocking in async context.
>
> Apply `fastapi-plugin:sqlalchemy-patterns` for model *definitions* — alembic-specialist finalizes column types and indexes in the next phase.
>
> Apply `python-foundation:python-conventions` (type hints, dataclasses for value objects, enums for choices).
>
> After writing code:
> - `python -c "from app.main import app"` — import check; fix any import errors before continuing.
> - Formatting (`ruff format`, per file) and `ruff check .` (once, after you return) are hook-driven — do not run them yourself; lint findings reach the orchestrator as a retry hint.
> - `mypy .` — type checking (advisory; do not fail the pipeline on mypy warnings).
>
> Note: FastAPI is API-only — provide an explicit **API contract** (endpoint path + HTTP method + Pydantic request/response schema) in the development report for the SPA frontend architect.

For qa phase, inject:
> Apply `python-foundation:pytest-testing` plus FastAPI-specific test patterns:
> - **`TestClient`** (from `fastapi.testclient`) for synchronous test HTTP requests — boots the full FastAPI app in-process.
> - **`AsyncClient`** (from `httpx`) with `ASGITransport(app=app)` for async test HTTP requests:
>   ```python
>   import pytest
>   from httpx import AsyncClient, ASGITransport
>   from app.main import app
>
>   @pytest.mark.anyio
>   async def test_create_user():
>       async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as client:
>           response = await client.post("/users/", json={"email": "a@b.com", "password": "secret"})
>       assert response.status_code == 201
>       assert response.json()["email"] == "a@b.com"
>   ```
> - **`app.dependency_overrides`** for test isolation — inject a test DB session and mock external services:
>   ```python
>   from app.db import get_db
>   from tests.conftest import get_test_db
>
>   app.dependency_overrides[get_db] = get_test_db
>   ```
> - Override is scoped to the test module or a fixture; remember to restore it afterwards.
>
> Run: `pytest` or `python -m pytest`

For security phase, inject:
> Check FastAPI-specific issues in addition to OWASP Top 10:
> - **Hardcoded secrets:** any `SECRET_KEY = "..."`, `JWT_SECRET = "..."`, or `DATABASE_URL = "postgresql://..."` literal in settings or router files is a critical risk. Read all credentials from `pydantic-settings` `BaseSettings` via environment variables. Never hardcode.
> - **Debug mode:** `debug=True` in `uvicorn.run()` or `FastAPI(debug=True)` exposes Python stack traces to end users. Must be `False` in production and read from env.
> - **CORS misconfiguration:** `allow_origins=["*"]` combined with `allow_credentials=True` is forbidden by the CORS spec and blocked by browsers. Use an explicit allowed-origins list when credentials are required.
> - **SQL injection via `text()`:** `text(f"... WHERE id = {user_id}")` or `text("... WHERE id = %s" % id)` are injection risks. Use `text("... WHERE id = :id")` with bound parameters: `session.execute(stmt, {"id": user_id})`.
> - **Missing auth dependency:** every state-changing endpoint (`POST`, `PUT`, `PATCH`, `DELETE`) must include `Depends(get_current_user)` or `Security(get_current_user, scopes=[...])` unless the BA spec explicitly calls for anonymous access. Verify each router group and endpoint individually.
> - **JWT weaknesses:** no expiry validation (`exp` claim), weak algorithm (`algorithms=["none"]`), or `HS256` with a short secret. Use at least `HS256` with a 32+ byte secret from env, always validate `exp`, never allow `"none"` algorithm.

## Post-pipeline checks

- `ruff format --check .`
- `pytest`
- `alembic check` (or `alembic heads` to verify no branch points)
- `mypy .` (advisory)

These run after the documentation phase. They are advisory — failures are reported but do not retry.

## MCP integration

FastAPI has no standard MCP server. Agents use the CLI via Bash (or `docker compose exec -T app …` in Dockerized setups) for running the server, migrations, and tests. The pipeline runs fully without any MCP server.
