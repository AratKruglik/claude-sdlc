# python-plugin

Plain Python backend stack provider. Auto-detects Python projects (presence of `pyproject.toml`, `requirements.txt`, `setup.py`, or `Pipfile`) and substitutes a Python-specific agent into the pipeline. Handles libraries, CLI tools, scripts, microservices, and data pipelines that do not use a recognized web framework.

> Requires [`sdlc`](../sdlc/README.md) and [`python-foundation`](../python-foundation/README.md) — installed automatically as dependencies.

When `django-plugin`, `fastapi-plugin`, or `flask-plugin` are also installed and their detection rules match the project (priority 150), they win the backend aspect instead and this plugin plays no role.

## What this plugin adds

| Component | Purpose |
|---|---|
| `stack.md` | Registers the `python` stack with `priority: 100`. Auto-detected by `pyproject.toml`, `requirements.txt`, `setup.py`, or `Pipfile`. |
| `agents/python-architect.md` | Replaces vanilla `developer` for the **backend aspect**. Application/library structure, module design, CLI entry points, core business logic, data processing, external API clients, configuration management, and packaging. (Sonnet/medium) |
| `skills/python-app-conventions/SKILL.md` | `src/` package layout, CLI tooling (argparse/click/typer), configuration management (pydantic-settings), structured logging, entry points, and packaging conventions. |
| `security-patterns.yaml` | Python application-level security regex rules (tempfile race, insecure random, path traversal, debug print). Language-level rules (eval/exec, subprocess shell=True, pickle, yaml.load) live in `python-foundation`. |
| `hooks/hooks.json` | PostToolUse hook that runs `ruff format` on each edited `.py` file, SubagentStop hook that runs `ruff check .` once after `python-architect` returns, and PreToolUse protection of the ruff/pyproject config during a run (Docker-aware, silent when ruff is absent). |

Language idioms (type hints, dataclasses, enums, match/case, pathlib), tooling (ruff, mypy, pip/poetry/uv), and testing (pytest) come from `python-foundation`.

## Agents

| Agent | Aspect | Phase | Model |
|---|---|---|---|
| `python-architect` | backend | development | Sonnet/medium |

## Skills

| Skill | Scope |
|---|---|
| `python-plugin:python-app-conventions` | src/ layout, CLI, pydantic-settings, logging, pyproject.toml packaging |
| `python-foundation:python-conventions` | Type hints, dataclasses, enums, match/case, pathlib, context managers |
| `python-foundation:python-tooling` | ruff, mypy, pip/poetry/uv package manager commands |
| `python-foundation:pytest-testing` | pytest, fixtures, parametrize, mocking, coverage |

## Pipeline shape on a plain Python project

```
business_analysis  → core's business-analyst   (Opus)
development        → python-architect           (Sonnet/medium)
qa                 → core's qa-engineer         (Sonnet)
security           → core's security-analyst    (Opus)   ← with Python-specific injection
documentation      → core's document-writer     (Haiku)

Post-pipeline:
  ruff check . --no-fix
  ruff format --check .
  mypy .                   (advisory — failures reported, no retry)
  python -m pytest
```

No extra database phase. No frontend aspect.

## Dependencies

- `sdlc` — core pipeline orchestration
- `python-foundation` — Python language conventions, tooling, and testing skills

## Prerequisites

- Python 3.10 or later.
- For the `ruff format` / `ruff check` hooks: `ruff` installed locally or in a running Docker Compose service.
- There is no Python MCP server — agents use the Python CLI via Bash (Docker-aware).

## Installation

```bash
/plugin marketplace add AratKruglik/claude-sdlc
/plugin install python-plugin@sdlc-marketplace
# sdlc and python-foundation install as dependencies
```

## Verifying

```bash
cd /path/to/your/python/project
/sdlc:list-stacks
# Expected output:
#   🎯 vanilla  priority=0   (always matches)
#   🎯 python   priority=100 (matches: pyproject.toml found)
```

## Running

```bash
/sdlc:start "Add CSV export feature to the data pipeline"
```

Auto-detects the Python stack, substitutes `python-architect` for the development phase, injects Python-specific guidance into the security review, and runs ruff/mypy/pytest checks at the end.

## Override stack manually

```bash
/sdlc:start --stack=vanilla "Quick prototype"
# Bypasses Python-specific agents and runs the vanilla pipeline.
```

## What this plugin does NOT include (yet)

- Django / FastAPI / Flask web application support — use their respective framework plugins (priority 150).
- Async task queue agents (Celery, ARQ, Dramatiq) — V2.
- Data science / ML pipeline agents (pandas, scikit-learn, PyTorch) — V2 capability plugin.
- Pure E2E browser tests — V2.

## License

MIT — see [`../../LICENSE`](../../LICENSE).
