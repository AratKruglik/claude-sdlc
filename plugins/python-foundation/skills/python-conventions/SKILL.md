---
name: python-conventions
description: |
  Modern Python idioms for any Python 3.10+ project: PEP 8 style, PEP 484/526 type hints, dataclasses, pathlib, enums, f-strings, structural pattern matching (match/case), context managers, exception handling, and null discipline. Stack-agnostic — referenced by every Python plugin in the marketplace.

  Use this skill to:
  - Write strongly-typed code with type hints on every function signature and class attribute.
  - Replace isinstance chains and magic constants with match/case and enums.
  - Use dataclasses or NamedTuple for value objects and data containers.
  - Handle resources safely with context managers and pathlib for all file paths.
  - Apply PEP 8 naming and structure conventions consistently.

  Do NOT use this skill for:
  - Framework-specific idioms (Django ORM, FastAPI routers, Flask blueprints — those live in framework plugin skills).
  - Packaging and dependency management — see python-foundation:python-tooling.
  - Testing patterns — see python-foundation:pytest-testing.
user-invocable: false
paths: ["**/*.py"]
---

# Python Conventions (stack-agnostic, Python 3.10+)

This skill encodes idioms that reduce bugs and improve readability in any Python codebase. Apply alongside the active framework plugin's conventions skill (e.g., `django-plugin:django-conventions`, `fastapi-plugin:fastapi-conventions`).

## Detection

Read `pyproject.toml` to determine the target Python version before writing code:

```toml
# pyproject.toml — Poetry style
[tool.poetry.dependencies]
python = "^3.10"

# pyproject.toml — PEP 621 style
[project]
requires-python = ">=3.10"
```

Also check for a `.python-version` file (used by pyenv):

```bash
cat .python-version   # e.g. "3.12.3"
```

Match the project's minimum version — do not use Python 3.11+ features (e.g. `StrEnum`, `tomllib`, `ExceptionGroup`) on a 3.10 project. All idioms in this skill apply from 3.10 onwards.

## Type hints — always on

Annotate every function parameter, return type, and class attribute. Type hints are documentation that a machine can check.

```python
from __future__ import annotations  # enables forward references on 3.10

from collections.abc import Sequence


def greet(name: str, times: int = 1) -> str:
    return (f"Hello, {name}!\n" * times).rstrip()


def first_active(users: Sequence[User]) -> User | None:  # union syntax (3.10+)
    return next((u for u in users if u.is_active), None)
```

Use `from __future__ import annotations` at the top of files that reference types not yet defined at parse time (forward references, self-referential types). It defers evaluation of all annotations to strings, avoiding `NameError`.

For library or shared utility code, use `TypeVar` and `Generic` to express parametric types:

```python
from typing import TypeVar, Generic

T = TypeVar("T")


class Result(Generic[T]):
    def __init__(self, value: T, ok: bool) -> None:
        self.value = value
        self.ok = ok

    @classmethod
    def success(cls, value: T) -> Result[T]:
        return cls(value, ok=True)

    @classmethod
    def failure(cls, value: T) -> Result[T]:
        return cls(value, ok=False)
```

Use `TypeAlias` to give complex types a readable name:

```python
from typing import TypeAlias

UserId: TypeAlias = int
Headers: TypeAlias = dict[str, str]
```

## Dataclasses — prefer over plain dicts

Use `@dataclass` instead of plain dicts or ad-hoc objects for structured data. Use `frozen=True` for immutable value objects.

```python
from dataclasses import dataclass, field
from datetime import datetime


@dataclass(frozen=True)
class Money:
    amount: int          # stored in cents
    currency: str

    def __post_init__(self) -> None:
        if self.amount < 0:
            raise ValueError(f"amount must be non-negative, got {self.amount}")
        if len(self.currency) != 3:
            raise ValueError(f"currency must be a 3-letter ISO code, got {self.currency!r}")

    def add(self, other: Money) -> Money:
        if self.currency != other.currency:
            raise ValueError(f"currency mismatch: {self.currency} vs {other.currency}")
        return Money(self.amount + other.amount, self.currency)


@dataclass
class Order:
    order_id: str
    lines: list[OrderLine] = field(default_factory=list)
    created_at: datetime = field(default_factory=datetime.utcnow)

    def total(self) -> Money:
        if not self.lines:
            return Money(0, "USD")
        totals = [line.subtotal() for line in self.lines]
        return sum(totals[1:], start=totals[0])
```

`field(default_factory=list)` is required for mutable defaults — never use `lines: list = []` as a default value (it shares the same list across all instances).

`__post_init__` runs after `__init__` and is the right place for validation.

Use `NamedTuple` when you need tuple unpacking or a lighter-weight immutable container:

```python
from typing import NamedTuple


class Point(NamedTuple):
    x: float
    y: float


origin = Point(0.0, 0.0)
x, y = origin  # tuple unpacking works
```

## Enums — replace magic constants

Use `Enum` for closed sets of values. Backed enums (`str`, `int`) serialize and deserialize cleanly.

```python
from enum import Enum


class Status(str, Enum):
    DRAFT = "draft"
    ACTIVE = "active"
    ARCHIVED = "archived"

    def is_published(self) -> bool:
        return self is Status.ACTIVE


class Priority(int, Enum):
    LOW = 1
    MEDIUM = 2
    HIGH = 3
```

Parse from external data with `Status(value)` — raises `ValueError` on unknown values, which is usually what you want at a boundary:

```python
raw = request.json["status"]
status = Status(raw)          # ValueError if raw is not a valid Status value
```

Use enums in `match`/`case` for exhaustive handling (see next section). Never model a closed set with bare string constants.

## match/case — structural pattern matching

Replace long `if/elif` chains and `isinstance` checks with `match`/`case`. Python's `match` is structural — it can destructure objects, sequences, and mappings in one expression.

**Matching on enum values:**

```python
def describe_status(status: Status) -> str:
    match status:
        case Status.DRAFT:
            return "Not yet published"
        case Status.ACTIVE:
            return "Live and visible"
        case Status.ARCHIVED:
            return "Hidden from public"
        case _:
            raise ValueError(f"Unhandled status: {status!r}")
```

**Matching on dataclass structure:**

```python
@dataclass
class Circle:
    radius: float

@dataclass
class Rectangle:
    width: float
    height: float

Shape = Circle | Rectangle


def area(shape: Shape) -> float:
    match shape:
        case Circle(radius=r):
            return 3.14159 * r * r
        case Rectangle(width=w, height=h):
            return w * h
        case _:
            raise TypeError(f"Unknown shape: {shape!r}")
```

**Matching sequences:**

```python
def parse_command(tokens: list[str]) -> str:
    match tokens:
        case ["quit"]:
            return "exit"
        case ["go", direction]:
            return f"moving {direction}"
        case ["pick", "up", item]:
            return f"picking up {item}"
        case [verb, *rest]:
            return f"unknown command: {verb} {rest}"
        case _:
            return "empty input"
```

**Guard clauses with `if`:**

```python
match point:
    case Point(x=x, y=y) if x == y:
        return "on diagonal"
    case Point(x=x, y=y):
        return f"at ({x}, {y})"
```

## pathlib — all filesystem paths

Replace every `os.path.*` call with `pathlib.Path`. Never concatenate path strings with `+` or `/` (the string operator).

```python
from pathlib import Path


def read_config(config_dir: Path) -> dict[str, str]:
    config_file = config_dir / "config.toml"    # / operator for joining
    if not config_file.exists():
        raise FileNotFoundError(f"Config not found: {config_file}")
    return parse_toml(config_file.read_text(encoding="utf-8"))


def ensure_output_dir(base: Path, name: str) -> Path:
    out = base / "output" / name
    out.mkdir(parents=True, exist_ok=True)
    return out


def find_python_files(src: Path) -> list[Path]:
    return sorted(src.glob("**/*.py"))


def write_report(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
```

Always pass `encoding="utf-8"` to `read_text`/`write_text` — do not rely on the platform default. Use `Path` objects throughout; convert to `str` only when an external API requires it (`str(path)`).

## Context managers

Use `with` for every resource that needs cleanup: files, locks, network connections, database sessions, temporary directories.

```python
from pathlib import Path


def process_file(path: Path) -> list[str]:
    with path.open(encoding="utf-8") as fh:
        return [line.rstrip() for line in fh]
```

Write custom context managers with `contextlib.contextmanager` instead of implementing `__enter__`/`__exit__` on a class, unless the class already exists for other reasons:

```python
from contextlib import contextmanager
from collections.abc import Generator
import time


@contextmanager
def timer(label: str) -> Generator[None, None, None]:
    start = time.perf_counter()
    try:
        yield
    finally:
        elapsed = time.perf_counter() - start
        print(f"{label}: {elapsed:.3f}s")


with timer("data load"):
    records = load_large_dataset()
```

Use `contextlib.suppress` to swallow expected exceptions without a bare `try/except/pass`:

```python
from contextlib import suppress
from pathlib import Path


def remove_if_exists(path: Path) -> None:
    with suppress(FileNotFoundError):
        path.unlink()
```

## Exception discipline

Never use bare `except:` or `except Exception:` without re-raising. Always catch the most specific exception type available.

```python
# Prefer
try:
    value = int(raw_input)
except ValueError as err:
    raise InvalidInputError(f"Expected integer, got {raw_input!r}") from err

# Avoid
try:
    value = int(raw_input)
except:          # catches SystemExit, KeyboardInterrupt, everything
    pass
```

Define domain exceptions that inherit from `Exception` (not `BaseException`):

```python
class AppError(Exception):
    """Base class for all application errors."""


class NotFoundError(AppError):
    def __init__(self, resource: str, id: int) -> None:
        super().__init__(f"{resource} with id={id} not found")
        self.resource = resource
        self.id = id


class ValidationError(AppError):
    def __init__(self, field: str, message: str) -> None:
        super().__init__(f"Validation failed for '{field}': {message}")
        self.field = field
```

Use exception chaining (`raise ... from err`) to preserve the original cause:

```python
def load_user(user_id: int) -> User:
    try:
        row = db.fetch_one("SELECT * FROM users WHERE id = %s", (user_id,))
    except DatabaseError as err:
        raise NotFoundError("User", user_id) from err
    if row is None:
        raise NotFoundError("User", user_id)
    return User.from_row(row)
```

The `from err` clause attaches the original exception as `__cause__`, giving full traceback context without losing information.

## Naming conventions (PEP 8)

| Element | Convention | Example |
|---|---|---|
| Functions and methods | `snake_case` | `calculate_total()` |
| Variables and parameters | `snake_case` | `order_id`, `is_active` |
| Classes | `PascalCase` | `OrderService`, `UserRepository` |
| Module-level constants | `UPPER_SNAKE_CASE` | `MAX_RETRIES = 3` |
| Private attributes / methods | `_single_underscore` prefix | `_cache`, `_validate()` |
| Name-mangled attributes | `__double_underscore` prefix | `__secret` (use rarely) |
| Type aliases | `PascalCase` | `UserId`, `Headers` |

Module structure — keep this order:

```python
"""Module docstring."""

from __future__ import annotations

# Standard library imports
import os
from pathlib import Path

# Third-party imports
import httpx

# Local imports
from myapp.domain import User
from myapp.exceptions import NotFoundError

# Module-level constants
DEFAULT_TIMEOUT: int = 30
MAX_RETRIES: int = 3

# Public API
__all__ = ["UserClient"]


class UserClient:
    ...
```

## Class design

Prefer composition over inheritance. Keep `__init__` (or `@dataclass`) typed. Use `@property` for computed attributes that derive from instance state without side effects. Use `@classmethod` for alternate constructors.

```python
from dataclasses import dataclass
from datetime import date


@dataclass
class DateRange:
    start: date
    end: date

    def __post_init__(self) -> None:
        if self.end < self.start:
            raise ValueError(f"end ({self.end}) must be >= start ({self.start})")

    @classmethod
    def for_month(cls, year: int, month: int) -> DateRange:
        import calendar
        last_day = calendar.monthrange(year, month)[1]
        return cls(
            start=date(year, month, 1),
            end=date(year, month, last_day),
        )

    @property
    def duration_days(self) -> int:
        return (self.end - self.start).days + 1

    def contains(self, d: date) -> bool:
        return self.start <= d <= self.end
```

`@dataclass` auto-generates `__repr__` and `__eq__`. When not using `@dataclass`, always define `__repr__` to aid debugging — it should return a string that ideally could be used to recreate the object:

```python
class Money:
    def __repr__(self) -> str:
        return f"Money(amount={self.amount!r}, currency={self.currency!r})"
```

Avoid deep inheritance hierarchies. If a class does too many things, extract collaborators and inject them via the constructor (composition). Depend on abstractions (abstract base classes or `Protocol`) rather than concrete types:

```python
from typing import Protocol


class Notifier(Protocol):
    def send(self, recipient: str, message: str) -> None: ...


class OrderService:
    def __init__(self, notifier: Notifier) -> None:
        self._notifier = notifier

    def confirm(self, order: Order) -> None:
        # ... business logic ...
        self._notifier.send(order.customer_email, f"Order {order.id} confirmed")
```

`Protocol` is structural typing — any class with a matching `send` method satisfies `Notifier` without explicit inheritance. Prefer it over ABCs for dependency injection boundaries.
