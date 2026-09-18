---
name: fastapi-conventions
description: |
  FastAPI web framework conventions: APIRouter with prefix/tags/dependencies, Pydantic v2 schemas (BaseModel, model_config, field_validator, model_validator), dependency injection with Depends, async SQLAlchemy session yielding, OAuth2PasswordBearer + JWT auth, lifespan context manager, pydantic-settings configuration, OpenAPI customization, and HTTPException error handling. Activated automatically by fastapi-plugin/stack.md.

  Use this skill to:
  - Structure FastAPI apps with per-feature APIRouter modules and a central app factory.
  - Write Pydantic v2 request and response schemas with proper validators.
  - Build a reusable Depends-based dependency chain for DB session, auth, and pagination.
  - Implement JWT-based authentication with get_current_user dependency.
  - Configure the app from environment variables via pydantic-settings.

  Do NOT use this skill for:
  - SQLAlchemy ORM model configuration and Alembic migrations — see fastapi-plugin:sqlalchemy-patterns.
  - Python language idioms — see python-foundation:python-conventions.
  - Testing patterns — see python-foundation:pytest-testing.
user-invocable: false
paths: ["**/*.py"]
---

# FastAPI Conventions

## Detection

Read `pyproject.toml` before writing any code:
- Find the FastAPI version under `[project.dependencies]` or `[tool.poetry.dependencies]`. FastAPI 0.100+ uses Pydantic v2 by default — this is the assumed baseline.
- Find the SQLAlchemy version. 2.0+ uses `Mapped`/`mapped_column` syntax. If the project uses SQLAlchemy 1.x, note it and use `Column()`/`relationship()` style instead.

```bash
grep -E "fastapi|sqlalchemy" pyproject.toml
```

---

## App factory and lifespan

Use a `create_app()` factory that returns a configured `FastAPI` instance. Use the `@asynccontextmanager` lifespan pattern (introduced in FastAPI 0.93+) for startup/shutdown logic.

```python
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.core.config import settings
from app.db.session import engine
from app.users.router import router as users_router
from app.auth.router import router as auth_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Startup: initialize DB connection pool, caches, etc.
    async with engine.begin() as conn:
        pass  # pool warm-up; alembic manages schema
    yield
    # Shutdown: close DB pool, flush caches, etc.
    await engine.dispose()


def create_app() -> FastAPI:
    app = FastAPI(
        title=settings.APP_NAME,
        version=settings.APP_VERSION,
        lifespan=lifespan,
    )

    app.add_middleware(
        CORSMiddleware,
        allow_origins=settings.CORS_ALLOWED_ORIGINS,
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

    app.include_router(auth_router)
    app.include_router(users_router)

    return app


app = create_app()
```

---

## APIRouter — per-feature modules

Create one `APIRouter` per feature module. Group related endpoints under a shared prefix and tags. Apply shared dependencies (e.g., auth) at the router level to avoid repeating them on every endpoint.

```python
# app/users/router.py
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession

from app.db.session import get_db
from app.auth.dependencies import get_current_user
from app.users import schemas, service
from app.users.models import User

router = APIRouter(
    prefix="/users",
    tags=["users"],
    dependencies=[Depends(get_current_user)],  # all endpoints require auth
)


@router.get("/me", response_model=schemas.UserRead)
async def get_current_user_profile(
    current_user: User = Depends(get_current_user),
) -> User:
    return current_user


@router.put("/me", response_model=schemas.UserRead)
async def update_profile(
    body: schemas.UserUpdate,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> User:
    return await service.update_user(db, current_user.id, body)


@router.get("/{user_id}", response_model=schemas.UserRead)
async def get_user(
    user_id: int,
    db: AsyncSession = Depends(get_db),
) -> User:
    user = await service.get_user_by_id(db, user_id)
    if user is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="User not found")
    return user
```

Include routers in the app factory:
```python
app.include_router(users_router)
app.include_router(auth_router, prefix="/auth")
```

---

## Pydantic v2 schemas

All request/response schemas use Pydantic v2 `BaseModel`. Use `model_config = ConfigDict(from_attributes=True)` for ORM-to-schema conversion. Separate `Create`, `Update`, and `Read` schemas when field sets differ.

```python
# app/users/schemas.py
from datetime import datetime
from typing import Annotated
from pydantic import BaseModel, ConfigDict, EmailStr, Field, field_validator, model_validator


class UserBase(BaseModel):
    email: EmailStr
    display_name: Annotated[str, Field(min_length=2, max_length=100)]


class UserCreate(UserBase):
    password: Annotated[str, Field(min_length=8)]

    @field_validator("password")
    @classmethod
    def password_strength(cls, v: str) -> str:
        if not any(c.isupper() for c in v):
            raise ValueError("Password must contain at least one uppercase letter")
        return v


class UserUpdate(BaseModel):
    display_name: Annotated[str, Field(min_length=2, max_length=100)] | None = None
    email: EmailStr | None = None


class UserRead(UserBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    created_at: datetime
    is_active: bool


class UserWithOrders(UserRead):
    orders: list["OrderRead"] = []

    @model_validator(mode="after")
    def check_active_has_orders(self) -> "UserWithOrders":
        if not self.is_active and self.orders:
            raise ValueError("Inactive users should not have active orders")
        return self
```

**Always** set `response_model=` on each endpoint to control what fields are exposed. Pydantic v2 will strip fields not declared in the response schema.

---

## Dependency injection

Build a reusable dependency chain. Each dependency is a plain callable (function or class) that FastAPI resolves via `Depends()`.

```python
# app/db/session.py
from collections.abc import AsyncGenerator
from sqlalchemy.ext.asyncio import AsyncSession, async_sessionmaker, create_async_engine
from app.core.config import settings

engine = create_async_engine(settings.DATABASE_URL, echo=False, pool_pre_ping=True)
AsyncSessionLocal = async_sessionmaker(engine, expire_on_commit=False)


async def get_db() -> AsyncGenerator[AsyncSession, None]:
    async with AsyncSessionLocal() as session:
        try:
            yield session
            await session.commit()
        except Exception:
            await session.rollback()
            raise
```

```python
# app/auth/dependencies.py
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.db.session import get_db
from app.users.models import User
from app.users import service

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/auth/token")


async def get_current_user(
    token: str = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db),
) -> User:
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, settings.JWT_SECRET, algorithms=[settings.JWT_ALGORITHM])
        user_id: int | None = payload.get("sub")
        if user_id is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception

    user = await service.get_user_by_id(db, int(user_id))
    if user is None:
        raise credentials_exception
    return user


async def require_admin(current_user: User = Depends(get_current_user)) -> User:
    if not current_user.is_admin:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Admin access required")
    return current_user
```

Override dependencies in tests:
```python
from app.main import app
from app.db.session import get_db

app.dependency_overrides[get_db] = get_test_db
```

---

## OAuth2 + JWT

Use `OAuth2PasswordBearer` for token extraction from the `Authorization: Bearer` header. Issue JWTs with an expiry claim.

```python
# app/auth/service.py
from datetime import datetime, timedelta, timezone
from jose import jwt
from passlib.context import CryptContext
from app.core.config import settings

pwd_context = CryptContext(schemes=["bcrypt"], deprecated="auto")


def verify_password(plain: str, hashed: str) -> bool:
    return pwd_context.verify(plain, hashed)


def hash_password(plain: str) -> str:
    return pwd_context.hash(plain)


def create_access_token(subject: str | int, expires_delta: timedelta | None = None) -> str:
    expire = datetime.now(timezone.utc) + (expires_delta or timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES))
    payload = {"sub": str(subject), "exp": expire}
    return jwt.encode(payload, settings.JWT_SECRET, algorithm=settings.JWT_ALGORITHM)
```

```python
# app/auth/router.py
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.ext.asyncio import AsyncSession

from app.auth import service as auth_service
from app.auth.schemas import Token
from app.db.session import get_db
from app.users import service as user_service

router = APIRouter(tags=["auth"])


@router.post("/auth/token", response_model=Token)
async def login(
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: AsyncSession = Depends(get_db),
) -> Token:
    user = await user_service.get_user_by_email(db, form_data.username)
    if user is None or not auth_service.verify_password(form_data.password, user.hashed_password):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    token = auth_service.create_access_token(subject=user.id)
    return Token(access_token=token, token_type="bearer")
```

**Never** store `JWT_SECRET` in source code. Read from `pydantic-settings` `Settings(BaseSettings)` via environment variable.

---

## HTTPException and error handling

Use `HTTPException` for expected domain errors. Use custom exception handlers for application-wide error types.

```python
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse


class ItemNotFoundError(Exception):
    def __init__(self, item_id: int) -> None:
        self.item_id = item_id


app = FastAPI()


@app.exception_handler(ItemNotFoundError)
async def item_not_found_handler(request: Request, exc: ItemNotFoundError) -> JSONResponse:
    return JSONResponse(
        status_code=404,
        content={"detail": f"Item {exc.item_id} not found"},
    )


# In a router endpoint:
raise HTTPException(status_code=404, detail="User not found")

# FastAPI returns 422 Unprocessable Entity automatically for Pydantic validation errors.
# The response body looks like:
# {
#   "detail": [
#     {"loc": ["body", "email"], "msg": "value is not a valid email address", "type": "value_error"}
#   ]
# }
```

---

## pydantic-settings configuration

```python
# app/core/config.py
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", case_sensitive=False)

    APP_NAME: str = "My FastAPI App"
    APP_VERSION: str = "0.1.0"

    DATABASE_URL: str  # required — must be set in env
    JWT_SECRET: str    # required — must be set in env
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30

    CORS_ALLOWED_ORIGINS: list[str] = ["http://localhost:3000"]


settings = Settings()
```

Never set `DATABASE_URL` or `JWT_SECRET` as literals in `config.py`. Always require them from the environment.

---

## Checklist before completing development phase

- [ ] Every endpoint has `response_model=` to filter the output schema
- [ ] Every state-changing endpoint (`POST`, `PUT`, `PATCH`, `DELETE`) requires `Depends(get_current_user)` or an explicit BA-approved exemption
- [ ] `Settings(BaseSettings)` reads all secrets from env — no literals
- [ ] `pydantic-settings` and `python-jose` (or `authlib`) are listed in `pyproject.toml` dependencies
- [ ] `python -c "from app.main import app"` passes without import errors
- [ ] No `alembic revision` or migration files created — that is alembic-specialist's job
