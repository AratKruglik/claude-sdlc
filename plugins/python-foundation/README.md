# Python Foundation

Shared Python foundation skills for the [SDLC Marketplace](../../README.md).

**Pure skill library — no agent, no stack profile.** Framework plugins reference these skills; they are never auto-detected on their own.

## Skills

| Skill | Description |
|---|---|
| `python-foundation:python-conventions` | Modern Python 3.10+ idioms: PEP 8 style, type hints on every signature, dataclasses, pathlib, enums, f-strings, structural pattern matching (match/case), context managers, exception handling, and null discipline |
| `python-foundation:python-tooling` | pyproject.toml as single source of truth, package managers (pip, Poetry, uv, pipenv), virtual environments, lockfiles, ruff (lint + format), mypy (type checking), and console scripts / entry points |
| `python-foundation:sqlalchemy-patterns` | Framework-agnostic SQLAlchemy 2.0 core: `Mapped`/`mapped_column` models, column types, relationships with explicit lazy loading, `select()` querying, migration metadata rules. Shared by `fastapi-plugin` and `flask-plugin` |
| `python-foundation:pytest-testing` | pytest patterns: fixtures, parametrize, conftest.py, monkeypatch, tmp_path, markers, unittest.mock (MagicMock, patch), pytest-cov coverage, and best practices |

## Dependencies

- [`sdlc`](../sdlc) — core pipeline (auto-pulled on install)

## Installation

Auto-pulled when you install any Python framework plugin. To use standalone:

```
/plugin install python-foundation@sdlc-marketplace
```
