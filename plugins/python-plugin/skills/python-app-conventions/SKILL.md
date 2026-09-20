---
name: python-app-conventions
description: |
  Application and library conventions for plain Python projects (no web framework): src/ package layout, CLI tooling (argparse/click/typer), configuration management (pydantic-settings), logging setup, module design, entry points, and packaging conventions. Activated automatically by python-plugin/stack.md as a convention skill for the development phase.

  Use this skill to:
  - Organise Python application code in a src/ layout with proper package structure.
  - Build CLI tools with argparse, click, or typer and register them as console scripts.
  - Manage configuration from environment variables using pydantic-settings.
  - Set up structured logging for production-grade applications.
  - Package a Python project correctly with pyproject.toml.

  Do NOT use this skill for:
  - Language idioms (type hints, dataclasses, enums, match/case) — see python-foundation:python-conventions.
  - Package manager commands (ruff, mypy, pip/poetry/uv) — see python-foundation:python-tooling.
  - Testing patterns — see python-foundation:pytest-testing.
  - Web framework patterns (Django/FastAPI/Flask) — see those framework plugin skills.
user-invocable: false
paths: ["**/*.py"]
---

# Python Application Conventions

## Detection — understanding the project type

Before writing code, read `pyproject.toml` (or `setup.py` / `requirements.txt`) to understand what kind of project this is:

```toml
# pyproject.toml signals to look for:

[project.scripts]           # → CLI tool; entry points are registered here
myapp = "myapp.cli:main"

[project]
dependencies = [            # → check for framework deps (fastapi, django, flask)
  "pydantic-settings",      # → configuration via env vars
  "click",                  # → CLI framework in use
]

[build-system]
requires = ["poetry-core"]  # → Poetry project
requires = ["hatchling"]    # → Hatch project
requires = ["setuptools"]   # → setuptools / pip project
```

No `fastapi`, `django`, or `flask` in dependencies → plain Python project; this skill applies.

---

## Source layout

### Preferred: `src/` layout

```
myproject/
├── pyproject.toml
├── README.md
├── src/
│   └── mypackage/
│       ├── __init__.py        # expose public API only — not everything
│       ├── __main__.py        # enables: python -m mypackage
│       ├── py.typed           # PEP 561 marker — enables mypy type checking by consumers
│       ├── cli.py             # CLI entry point (argparse / click / typer)
│       ├── config.py          # pydantic-settings Settings class
│       ├── core.py            # core business logic
│       └── exporters/
│           ├── __init__.py
│           └── csv_exporter.py
└── tests/
    ├── conftest.py
    ├── test_core.py
    └── exporters/
        └── test_csv_exporter.py
```

`__init__.py` exposes the public API explicitly:

```python
# src/mypackage/__init__.py
from mypackage.core import Pipeline
from mypackage.exporters.csv_exporter import CsvExporter

__all__ = ["Pipeline", "CsvExporter"]
```

### Acceptable: flat layout (small projects / scripts)

```
myproject/
├── pyproject.toml
├── mypackage.py      # single-module library
└── tests/
    └── test_mypackage.py
```

Or a package without `src/`:

```
myproject/
├── pyproject.toml
├── mypackage/
│   ├── __init__.py
│   └── core.py
└── tests/
    └── conftest.py
```

Match whichever layout the project already uses. Never restructure an existing project unless the BA spec explicitly requires it.

---

## CLI with argparse (stdlib, no additional deps)

Use argparse when the project has no CLI framework in its dependencies and adding one is out of scope.

```python
# src/mypackage/cli.py
from __future__ import annotations

import argparse
import sys
from pathlib import Path

from mypackage.config import Settings
from mypackage.core import Pipeline


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="mypackage",
        description="Process data files and export results.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    run_cmd = sub.add_parser("run", help="Run the pipeline.")
    run_cmd.add_argument("input", type=Path, help="Input file path.")
    run_cmd.add_argument(
        "--output",
        type=Path,
        default=None,
        help="Output directory (default: from MYAPP_OUTPUT_DIR env var).",
    )
    run_cmd.add_argument(
        "--format",
        choices=["csv", "json"],
        default="csv",
        help="Output format.",
    )

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    settings = Settings()

    output_dir = args.output or settings.output_dir

    try:
        pipeline = Pipeline(settings=settings)
        pipeline.run(input_path=args.input, output_dir=output_dir, fmt=args.format)
    except FileNotFoundError as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
```

---

## CLI with click (feature-rich, composable commands)

Use click when it is already in the project's dependencies, or when the CLI has many subcommands, option validation, or prompt interactions.

```python
# src/mypackage/cli.py
from __future__ import annotations

from pathlib import Path

import click

from mypackage.config import Settings
from mypackage.core import Pipeline


@click.group()
def cli() -> None:
    """Process data files and export results."""


@cli.command()
@click.argument("input", type=click.Path(exists=True, path_type=Path))
@click.option(
    "--output",
    type=click.Path(path_type=Path),
    default=None,
    help="Output directory. Defaults to MYAPP_OUTPUT_DIR env var.",
)
@click.option(
    "--format",
    "fmt",
    type=click.Choice(["csv", "json"]),
    default="csv",
    show_default=True,
)
def run(input: Path, output: Path | None, fmt: str) -> None:
    """Run the pipeline on INPUT file."""
    settings = Settings()
    output_dir = output or settings.output_dir
    Pipeline(settings=settings).run(input_path=input, output_dir=output_dir, fmt=fmt)


def main() -> None:
    cli()
```

**When to prefer each CLI framework:**

| Framework | Choose when |
|---|---|
| `argparse` | No CLI deps allowed; stdlib only; simple, stable CLI |
| `click` | Feature-rich CLI (prompts, colors, progress bars); composable command groups; already in the project |
| `typer` | Type-annotated, FastAPI-style API; rapid prototyping; team already uses FastAPI/Pydantic |

Match what the project already uses. Do not introduce a new CLI framework without BA approval.

---

## CLI with typer

Use typer when it is already in the project's dependencies, or when the team prefers type-annotated CLI definitions.

```python
# src/mypackage/cli.py
from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer

from mypackage.config import Settings
from mypackage.core import Pipeline

app = typer.Typer(help="Process data files and export results.")


@app.command()
def run(
    input: Annotated[Path, typer.Argument(help="Input file path.", exists=True)],
    output: Annotated[
        Path | None,
        typer.Option(help="Output directory. Defaults to MYAPP_OUTPUT_DIR env var."),
    ] = None,
    fmt: Annotated[str, typer.Option("--format", help="Output format.")] = "csv",
) -> None:
    """Run the pipeline on INPUT."""
    settings = Settings()
    output_dir = output or settings.output_dir
    Pipeline(settings=settings).run(input_path=input, output_dir=output_dir, fmt=fmt)


def main() -> None:
    app()
```

---

## Configuration with pydantic-settings

Read all configuration from environment variables (and optionally a `.env` file). Never call `os.environ.get()` inline — consolidate all env var reads into a single `Settings` class.

```python
# src/mypackage/config.py
from __future__ import annotations

from pathlib import Path

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="MYAPP_",      # MYAPP_OUTPUT_DIR, MYAPP_LOG_LEVEL, etc.
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
    )

    output_dir: Path = Field(default=Path("/tmp/myapp-output"), description="Output directory for exported files.")
    log_level: str = Field(default="INFO", description="Logging level (DEBUG, INFO, WARNING, ERROR).")
    api_key: str = Field(description="External API key. Required. Set via MYAPP_API_KEY env var.")
    max_workers: int = Field(default=4, ge=1, le=32, description="Thread pool size for parallel processing.")


# Singleton — import this throughout the codebase instead of creating new instances
settings = Settings()
```

**Nested settings** for complex configuration:

```python
from pydantic import BaseModel
from pydantic_settings import BaseSettings, SettingsConfigDict


class DatabaseSettings(BaseModel):
    host: str = "localhost"
    port: int = 5432
    name: str = "myapp"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="MYAPP_", env_nested_delimiter="__")

    database: DatabaseSettings = DatabaseSettings()
    # Set via: MYAPP_DATABASE__HOST=db.prod.example.com
```

**Rules:**
- Always use `env_prefix` to namespace your application's env vars.
- Mark required fields (no default) — pydantic-settings raises `ValidationError` at startup if they are missing, giving a clear error message.
- Never read `os.environ` directly in business logic — always go through `Settings`.

---

## Structured logging

Use Python's standard `logging` module. Configure it once at the application entry point. Never use `print()` for diagnostics.

```python
# src/mypackage/logging_config.py
from __future__ import annotations

import logging
import sys


def configure_logging(level: str = "INFO") -> None:
    """Configure root logger for the application. Call once at startup."""
    logging.basicConfig(
        level=level.upper(),
        format="%(asctime)s %(levelname)-8s %(name)s  %(message)s",
        datefmt="%Y-%m-%dT%H:%M:%S",
        stream=sys.stderr,
    )
```

**In every module**, get a module-scoped logger:

```python
# src/mypackage/core.py
from __future__ import annotations

import logging

logger = logging.getLogger(__name__)


class Pipeline:
    def run(self, input_path: Path, ...) -> None:
        logger.info("Starting pipeline run", extra={"input": str(input_path)})
        try:
            result = self._process(input_path)
            logger.debug("Processing complete, %d records produced", len(result))
        except OSError as exc:
            logger.error("Failed to read input file: %s", exc)
            raise
```

**JSON logging for production** (use `python-json-logger` or `structlog` when already in the project):

```python
# with python-json-logger
import logging
from pythonjsonlogger.json import JsonFormatter

handler = logging.StreamHandler()
handler.setFormatter(JsonFormatter("%(asctime)s %(levelname)s %(name)s %(message)s"))
logging.root.addHandler(handler)
logging.root.setLevel("INFO")
```

**Rule:** never use `print()` for diagnostics outside of `__main__.py` / `cli.py` (where printing to stdout is intentional CLI output, not debug noise).

---

## Entry points and pyproject.toml packaging

Register CLI commands as console scripts so they are available after `pip install` / `poetry install`:

```toml
# pyproject.toml

[project]
name = "mypackage"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = [
    "pydantic-settings>=2.0",
    "click>=8.0",
]

[project.scripts]
myapp = "mypackage.cli:main"          # installs `myapp` command
myapp-admin = "mypackage.admin_cli:main"  # second entry point if needed

[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-cov",
    "ruff",
    "mypy",
]
```

`__main__.py` allows `python -m mypackage` without installing the package:

```python
# src/mypackage/__main__.py
import sys

from mypackage.cli import main

sys.exit(main())
```

---

## Module design anti-patterns

| Do NOT | Do instead |
|---|---|
| Import everything in `__init__.py` | Expose only the public API (`__all__`) — lazy imports or explicit imports of public symbols only |
| Use mutable default arguments (`def f(items=[])`) | Use `None` as default and initialise inside the function (`if items is None: items = []`) |
| Use global mutable state (`_cache = {}` at module level) | Inject dependencies via constructor or function argument; use `functools.lru_cache` for pure memoisation |
| Use `print()` for diagnostics in library code | Use `logging.getLogger(__name__)` — callers control the log level and destination |
| Catch bare `except:` | Catch specific exceptions (`except ValueError:`, `except OSError as e:`) |
| Inline `os.environ.get("API_KEY")` throughout codebase | Centralise all env-var reads in a `Settings` class (pydantic-settings or python-decouple) |
