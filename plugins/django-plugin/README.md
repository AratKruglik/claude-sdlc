# django-plugin

Django backend + database stack provider for the SDLC marketplace.

Registers Django projects (detected via a Django `manage.py`, or Django in `pyproject.toml`/`requirements.txt`/`Pipfile`/`setup.py`/`setup.cfg`) and substitutes specialized agents for the development and database phases. Provides two convention skills and reuses `python-foundation` for language idioms, tooling, and testing.

## Agents

| Agent | Phase | Aspect | Scope |
|---|---|---|---|
| `django-architect` | development | backend | Views (CBV/FBV), DRF ViewSets and serializers, forms, URLconf with app namespacing, middleware, signals, model *definitions*, Django template rendering, DRF API contract design for SPA frontends |
| `django-migrations-specialist` | database (extra) | database | Finalize model field types and Meta indexes/constraints, `makemigrations`, `sqlmigrate` review, `migrate`, verify with `migrate --check` |

## Skills

| Skill | Activated by | Scope |
|---|---|---|
| `django-plugin:django-conventions` | stack.md (auto) | App layout, settings split, URLconf, CBV/DRF ViewSets, serializers, permissions, forms, signals, Django admin |
| `django-plugin:django-orm-patterns` | stack.md (auto) | Model definitions, custom managers/QuerySets, N+1 prevention, F/Q expressions, transactions, Meta indexes and constraints |

Reused from `python-foundation`:

| Skill | Scope |
|---|---|
| `python-foundation:python-conventions` | Type hints, dataclasses, enums, PEP 8 |
| `python-foundation:python-tooling` | ruff, pyproject.toml, virtual environments |
| `python-foundation:pytest-testing` | pytest patterns, fixtures, coverage |

## Dependencies

| Dependency | Role |
|---|---|
| `sdlc` | Core pipeline orchestrator |
| `python-foundation` | Python language conventions, tooling, and testing skills |

## Install

```bash
/plugin install django-plugin@sdlc-marketplace
# sdlc and python-foundation install as dependencies
```
