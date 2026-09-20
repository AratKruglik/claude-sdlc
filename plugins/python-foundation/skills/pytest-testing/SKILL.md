---
name: pytest-testing
description: |
  pytest testing patterns for any Python project: test structure, fixtures, parametrize, conftest.py, monkeypatch, tmp_path, markers, unittest.mock (MagicMock, patch), pytest-cov coverage, and best practices. Stack-agnostic — referenced by every Python plugin in the marketplace.

  Use this skill to:
  - Organise tests with conftest.py shared fixtures and a clear test/src layout.
  - Write parametrized tests to cover multiple inputs without duplication.
  - Mock external dependencies (HTTP, DB, filesystem) with unittest.mock and monkeypatch.
  - Measure and enforce code coverage with pytest-cov.

  Do NOT use this skill for:
  - Framework-specific test types (Django TestCase / WebTestCase, FastAPI TestClient, Flask test client — see framework plugin skills).
  - Language idioms — see python-foundation:python-conventions.
user-invocable: false
paths: ["tests/**", "**/test_*.py", "**/*_test.py", "**/conftest.py"]
---

# pytest Testing Patterns (stack-agnostic)

pytest is the standard test runner for modern Python projects. These patterns apply to any Python 3.10+ codebase regardless of framework.

## Project layout

Keep tests outside the source tree so installed packages are tested rather than the raw source directory:

```
src/
  myapp/
    __init__.py
    service.py
    repository.py
tests/
  conftest.py
  test_service.py
  test_repository.py
  integration/
    conftest.py
    test_db.py
pyproject.toml
```

Configure pytest to find the source in `pyproject.toml`:

```toml
[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "--strict-markers -q"
```

Install the package in editable mode before running tests so `import myapp` resolves correctly:

```bash
pip install -e .        # or: poetry install / uv sync
pytest
```

## conftest.py — shared fixtures

`conftest.py` files are loaded automatically by pytest. Place shared fixtures there instead of importing them into every test module.

```python
# tests/conftest.py
from __future__ import annotations

import pytest

from myapp.database import Database, get_connection
from myapp.service import UserService


@pytest.fixture(scope="module")
def db() -> Database:
    """Module-scoped DB connection — created once per test module."""
    conn = get_connection(url="sqlite:///:memory:")
    conn.create_tables()
    yield conn
    conn.close()


@pytest.fixture
def user_service(db: Database) -> UserService:
    """Function-scoped service — fresh instance per test, shared DB."""
    return UserService(db)
```

Fixture scopes (from broadest to narrowest):

| Scope | Created | Destroyed |
|---|---|---|
| `session` | Once per `pytest` run | After all tests |
| `module` | Once per test module | After last test in module |
| `class` | Once per test class | After last test in class |
| `function` (default) | Once per test function | After the test returns |

Use the narrowest scope that avoids expensive re-creation. Use `session` scope only for truly global state (e.g., a Docker container started via `pytest-docker`).

## Basic test patterns

```python
# tests/test_service.py
from __future__ import annotations

import pytest

from myapp.service import UserService
from myapp.exceptions import NotFoundError


def test_create_user_returns_new_id(user_service: UserService) -> None:
    user_id = user_service.create(name="Alice", email="alice@example.com")
    assert user_id > 0


def test_find_user_by_id(user_service: UserService) -> None:
    user_id = user_service.create(name="Bob", email="bob@example.com")
    user = user_service.find(user_id)
    assert user.name == "Bob"
    assert user.email == "bob@example.com"


def test_find_missing_user_raises(user_service: UserService) -> None:
    with pytest.raises(NotFoundError):
        user_service.find(99999)


def test_find_missing_user_message(user_service: UserService) -> None:
    with pytest.raises(NotFoundError, match="User.*99999"):
        user_service.find(99999)
```

Use plain `assert` — pytest rewrites assertions to produce detailed failure messages. Do not use `assertEqual` / `assertTrue` / `assertRaises` (those are `unittest.TestCase` methods).

## Fixtures — yield, teardown, autouse

Use `yield` in a fixture to run teardown code after the test:

```python
@pytest.fixture
def temp_user(user_service: UserService) -> int:
    user_id = user_service.create(name="Temp", email="temp@example.com")
    yield user_id
    user_service.delete(user_id)   # teardown: always runs even if test fails
```

Fixtures can depend on other fixtures — pytest resolves the dependency graph automatically:

```python
@pytest.fixture
def admin_user(user_service: UserService) -> User:
    user_id = user_service.create(name="Admin", email="admin@example.com")
    return user_service.promote_to_admin(user_id)
```

Use `autouse=True` for cross-cutting setup that every test in a module or package needs:

```python
# tests/integration/conftest.py
@pytest.fixture(autouse=True)
def rollback_after_test(db: Database) -> None:
    """Wrap every integration test in a transaction that rolls back."""
    db.begin()
    yield
    db.rollback()
```

## parametrize — data-driven tests

Drive many input/output combinations through a single test body:

```python
import pytest


@pytest.mark.parametrize("amount,currency,expected_str", [
    (100, "USD", "1.00 USD"),
    (0,   "EUR", "0.00 EUR"),
    (999, "GBP", "9.99 GBP"),
])
def test_money_format(amount: int, currency: str, expected_str: str) -> None:
    money = Money(amount, currency)
    assert str(money) == expected_str
```

Use `pytest.param` to give test cases readable IDs and to mark individual cases:

```python
@pytest.mark.parametrize("raw,expected", [
    pytest.param("draft",    Status.DRAFT,    id="draft"),
    pytest.param("active",   Status.ACTIVE,   id="active"),
    pytest.param("archived", Status.ARCHIVED, id="archived"),
])
def test_status_parsing(raw: str, expected: Status) -> None:
    assert Status(raw) == expected


@pytest.mark.parametrize("raw", [
    pytest.param("unknown", id="unknown-value"),
    pytest.param("",        id="empty-string"),
])
def test_status_invalid(raw: str) -> None:
    with pytest.raises(ValueError):
        Status(raw)
```

Multiple independent parameters are passed as separate arguments — pytest generates all combinations:

```python
@pytest.mark.parametrize("x", [0, 1, 2])
@pytest.mark.parametrize("y", [10, 20])
def test_add(x: int, y: int) -> None:
    assert add(x, y) == x + y   # 6 test cases generated
```

## monkeypatch — patching at test time

`monkeypatch` is a pytest fixture that temporarily modifies attributes, environment variables, or dictionary entries and automatically restores them after the test.

```python
import requests


def get_user_count(api_url: str) -> int:
    response = requests.get(f"{api_url}/users/count")
    response.raise_for_status()
    return response.json()["count"]


def test_get_user_count(monkeypatch: pytest.MonkeyPatch) -> None:
    class FakeResponse:
        def raise_for_status(self) -> None: ...
        def json(self) -> dict:
            return {"count": 42}

    monkeypatch.setattr(requests, "get", lambda url: FakeResponse())

    count = get_user_count("https://api.example.com")
    assert count == 42
```

Other common `monkeypatch` uses:

```python
def test_reads_env_var(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setenv("DATABASE_URL", "sqlite:///:memory:")
    assert get_database_url() == "sqlite:///:memory:"


def test_missing_env_var(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("DATABASE_URL", raising=False)
    with pytest.raises(EnvironmentError):
        get_database_url()


def test_patches_dict(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.setitem(config, "timeout", 5)
    assert effective_timeout() == 5
```

Prefer `monkeypatch` over `unittest.mock.patch` for patching attributes and environment variables in pytest — it integrates with pytest's fixture lifecycle and does not require a context manager or decorator.

## unittest.mock — mocking objects and calls

Use `unittest.mock` when you need to assert that a collaborator was called with specific arguments, or to make a mock raise an exception.

```python
from unittest.mock import MagicMock, patch

from myapp.service import OrderService


def test_sends_confirmation_email() -> None:
    mailer = MagicMock()
    gateway = MagicMock()
    gateway.charge.return_value = Receipt(id="rcpt_1", amount=500)

    service = OrderService(payment_gateway=gateway, mailer=mailer)
    service.checkout(order=make_order(total_cents=500))

    gateway.charge.assert_called_once_with(500)
    mailer.send.assert_called_once()


def test_checkout_raises_on_payment_failure() -> None:
    gateway = MagicMock()
    gateway.charge.side_effect = PaymentDeclinedError("insufficient funds")

    service = OrderService(payment_gateway=gateway, mailer=MagicMock())

    with pytest.raises(PaymentDeclinedError, match="insufficient funds"):
        service.checkout(order=make_order(total_cents=500))
```

Use `patch` as a context manager when you need to replace a name in a module's namespace:

```python
from unittest.mock import patch


def test_sends_welcome_email() -> None:
    with patch("myapp.service.send_email") as mock_send:
        create_user(name="Alice", email="alice@example.com")
        mock_send.assert_called_once_with(
            to="alice@example.com",
            subject="Welcome",
        )
```

Or as a decorator:

```python
@patch("myapp.service.send_email")
def test_email_on_signup(mock_send: MagicMock) -> None:
    create_user(name="Bob", email="bob@example.com")
    assert mock_send.call_count == 1
```

Patch the name where it is **used**, not where it is defined. If `myapp.service` imports `send_email` from `myapp.email`, patch `myapp.service.send_email`, not `myapp.email.send_email`.

## tmp_path — tests that write files

Use the built-in `tmp_path` fixture (a `pathlib.Path` pointing to a unique temporary directory) for tests that need to read or write files. pytest cleans it up after the session.

```python
from pathlib import Path
import pytest

from myapp.export import write_csv


def test_write_csv_creates_file(tmp_path: Path) -> None:
    output = tmp_path / "report.csv"
    rows = [{"name": "Alice", "score": "95"}, {"name": "Bob", "score": "87"}]

    write_csv(output, rows)

    assert output.exists()
    lines = output.read_text(encoding="utf-8").splitlines()
    assert lines[0] == "name,score"
    assert len(lines) == 3   # header + 2 data rows


def test_load_config_from_file(tmp_path: Path) -> None:
    config_file = tmp_path / "config.toml"
    config_file.write_text('[app]\nport = 8080\n', encoding="utf-8")

    config = load_config(config_file)

    assert config.port == 8080
```

`tmp_path` is function-scoped by default. Use `tmp_path_factory` (session fixture) if multiple fixtures or tests need to share the same temporary directory.

## Coverage — measuring and enforcing

Run pytest with `pytest-cov`:

```bash
pytest --cov=src --cov-report=term-missing
```

Configure coverage in `pyproject.toml`:

```toml
[tool.coverage.run]
source = ["src"]
branch = true               # track branch coverage, not just line coverage

[tool.coverage.report]
fail_under = 80
show_missing = true
omit = ["src/myapp/migrations/*", "src/myapp/__main__.py"]
```

With `fail_under = 80`, `pytest --cov=src` exits non-zero if coverage drops below 80% — useful as a CI gate.

Generate an HTML report for local inspection:

```bash
pytest --cov=src --cov-report=html
open htmlcov/index.html
```

Coverage is a floor, not a goal. A covered line is not necessarily an asserted behaviour — 100% coverage does not mean 0 bugs. Focus on asserting meaningful behaviours; the coverage number confirms you did not miss entire code paths.

## Running tests

```bash
pytest                          # run all tests
pytest -x                       # stop on first failure
pytest -v                       # verbose: show each test name
pytest -q                       # quiet: summary only
pytest -k "test_create"         # run tests whose name matches the expression
pytest tests/test_service.py    # run a specific module
pytest tests/integration/       # run a subdirectory
pytest --tb=short               # shorter tracebacks
pytest --lf                     # run only tests that failed last time
pytest -n auto                  # parallel execution (requires pytest-xdist)
```

Run the full quality pipeline before committing:

```bash
ruff format --check . && ruff check . && mypy src/ && pytest --cov=src
```
