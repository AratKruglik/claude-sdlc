---
name: python-tooling
description: |
  Python project tooling: pyproject.toml as the single source of truth, package managers (pip, Poetry, uv, pipenv), virtual environments, lockfiles, ruff (lint + format), mypy (type checking), and console scripts / entry points. Stack-agnostic — referenced by every Python plugin in the marketplace.

  Use this skill to:
  - Read pyproject.toml (or requirements.txt / Pipfile) to learn which package manager and Python version the project uses.
  - Install, add, and remove dependencies with the project's package manager.
  - Run ruff for formatting and linting, mypy for type checking.
  - Define console scripts and entry points for CLI applications.

  Do NOT use this skill for:
  - Language idioms — see python-foundation:python-conventions.
  - Testing patterns — see python-foundation:pytest-testing.
  - Framework-specific tooling (django management commands, flask CLI) — see framework plugin skills.
user-invocable: false
paths: ["pyproject.toml", "ruff.toml", "setup.cfg", "requirements*.txt", "tox.ini"]
---

# Python Tooling (stack-agnostic)

`pyproject.toml` is the single source of truth for a modern Python project. Read it before doing anything else — it tells you the Python version, the package manager, the linting config, and the test settings.

## Detection — which package manager is active

Check for lockfiles in this order:

```bash
test -f poetry.lock   && echo "Poetry"
test -f uv.lock       && echo "uv"
test -f Pipfile.lock  && echo "Pipenv"
test -f requirements.txt && echo "pip"
```

| Signal | Package manager | Install command |
|---|---|---|
| `poetry.lock` | Poetry | `poetry install` |
| `uv.lock` | uv | `uv sync` |
| `Pipfile.lock` | Pipenv | `pipenv install` |
| `requirements.txt` only | pip | `pip install -r requirements.txt` |

When only a `pyproject.toml` with a `[build-system]` section exists but no lockfile, check `[build-system].requires` to identify the build backend (setuptools, hatch, flit) and fall back to `pip install -e .`.

Always use the project's existing package manager. Do not mix managers (e.g., do not run `pip install` in a Poetry project).

## pyproject.toml — canonical structure

A fully configured `pyproject.toml` for a PEP 621 project:

```toml
[project]
name = "myapp"
version = "0.1.0"
description = "Short project description"
requires-python = ">=3.10"
dependencies = [
    "httpx>=0.27",
    "pydantic>=2.6",
]

[project.optional-dependencies]
dev = [
    "pytest>=8.0",
    "pytest-cov>=5.0",
    "ruff>=0.4",
    "mypy>=1.10",
]

[project.scripts]
myapp = "myapp.cli:main"

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.ruff]
line-length = 88
target-version = "py310"

[tool.ruff.lint]
select = ["E", "F", "I", "UP", "B", "SIM"]
ignore = ["E501"]

[tool.mypy]
python_version = "3.10"
strict = true
ignore_missing_imports = true

[tool.pytest.ini_options]
testpaths = ["tests"]
addopts = "--strict-markers -q"

[tool.coverage.run]
source = ["src"]
branch = true

[tool.coverage.report]
fail_under = 80
show_missing = true
```

For Poetry projects the structure differs slightly — dependencies live under `[tool.poetry.dependencies]` and scripts under `[tool.poetry.scripts]`. The `[tool.ruff]`, `[tool.mypy]`, and `[tool.pytest.ini_options]` sections are identical regardless of build backend.

## ruff — lint and format

ruff replaces flake8, isort, pyupgrade, and black in a single fast tool. Configure it in `pyproject.toml`:

```toml
[tool.ruff]
line-length = 88
target-version = "py310"

[tool.ruff.lint]
# E/F = pycodestyle + pyflakes, I = isort, UP = pyupgrade, B = bugbear, SIM = simplify
select = ["E", "F", "I", "UP", "B", "SIM"]
ignore = ["E501"]  # line-too-long — formatter handles this

[tool.ruff.lint.isort]
known-first-party = ["myapp"]
```

Key commands:

```bash
ruff check .            # lint — report issues
ruff check --fix .      # lint — auto-fix safe issues
ruff format .           # format — applies opinionated style (like black)
ruff format --check .   # format — exit non-zero if files would change (CI mode)
```

Run both in CI:

```bash
ruff format --check . && ruff check .
```

ruff's formatter is intentionally compatible with black's output — switching a black project to ruff format requires no manual changes.

## mypy — type checking

Configure mypy in `pyproject.toml`:

```toml
[tool.mypy]
python_version = "3.10"
strict = true
ignore_missing_imports = true
```

`strict = true` enables a comprehensive set of checks including `disallow_untyped_defs`, `warn_return_any`, `warn_unused_ignores`, and others. Start with `strict` on new projects; on legacy projects enable checks incrementally.

Per-module overrides for third-party packages that ship without stubs:

```toml
[[tool.mypy.overrides]]
module = ["boto3.*", "botocore.*"]
ignore_missing_imports = true
```

Add a `py.typed` marker file to signal that your package ships inline type information:

```bash
touch src/myapp/py.typed
```

Then declare it in `pyproject.toml`:

```toml
[tool.hatch.build.targets.wheel]
include = ["src/myapp/py.typed"]
```

Run mypy:

```bash
mypy src/          # check all source files
mypy src/myapp/service.py   # check a single file
```

## Virtual environments

Each package manager manages its own virtual environment:

```bash
# pip — manual venv
python -m venv .venv
source .venv/bin/activate      # Linux/macOS
.venv\Scripts\activate         # Windows
pip install -e ".[dev]"

# Poetry — automatic venv
poetry install                 # creates .venv in project root (or in cache)
poetry shell                   # activate
poetry run pytest              # run without activating

# uv — automatic venv
uv sync                        # creates .venv and installs from uv.lock
uv run pytest                  # run without activating

# Pipenv — automatic venv
pipenv install --dev
pipenv shell
pipenv run pytest
```

Never commit the virtual environment. Add to `.gitignore`:

```
.venv/
__pycache__/
*.pyc
*.pyo
.mypy_cache/
.ruff_cache/
.pytest_cache/
dist/
*.egg-info/
```

## Common commands — pip / Poetry / uv

| Task | pip | Poetry | uv |
|---|---|---|---|
| Install all deps | `pip install -r requirements.txt` | `poetry install` | `uv sync` |
| Install dev deps | `pip install -e ".[dev]"` | `poetry install --with dev` | `uv sync --extra dev` |
| Add runtime dep | `pip install X` then freeze | `poetry add X` | `uv add X` |
| Add dev dep | `pip install X` then freeze | `poetry add --group dev X` | `uv add --dev X` |
| Remove dep | `pip uninstall X` then freeze | `poetry remove X` | `uv remove X` |
| Update dep | `pip install -U X` then freeze | `poetry update X` | `uv lock --upgrade-package X && uv sync` |
| Run script | `python -m mymodule` | `poetry run python -m mymodule` | `uv run python -m mymodule` |
| Run tool | `ruff check .` | `poetry run ruff check .` | `uv run ruff check .` |
| Show dep tree | `pip list` | `poetry show --tree` | `uv tree` |

For pip projects, always regenerate the lockfile after adding or changing a dependency:

```bash
pip freeze > requirements.txt
```

Consider splitting into `requirements.txt` (runtime) and `requirements-dev.txt` (dev/test) to keep production images lean.

## Console scripts

Define CLI entry points in `pyproject.toml` so users can run your tool by name after installation:

```toml
# PEP 621 / hatch / setuptools
[project.scripts]
myapp = "myapp.cli:main"
myapp-worker = "myapp.worker:run"
```

```toml
# Poetry
[tool.poetry.scripts]
myapp = "myapp.cli:main"
```

The value is `"package.module:callable"`. The callable must accept no arguments (or parse `sys.argv` internally):

```python
# src/myapp/cli.py
import argparse
import sys


def main() -> None:
    parser = argparse.ArgumentParser(description="myapp CLI")
    parser.add_argument("command", choices=["serve", "migrate"])
    args = parser.parse_args()
    match args.command:
        case "serve":
            from myapp.server import serve
            serve()
        case "migrate":
            from myapp.db import migrate
            migrate()
        case _:
            parser.print_help()
            sys.exit(1)
```

After installation (`pip install -e .` / `poetry install` / `uv sync`), the script is available on `$PATH`:

```bash
myapp serve
myapp migrate
```
