---
stack: django
priority: 150
aspects: [backend, database]
detect:
  any:
    - file_exists: manage.py
    - file_contains:
        path: pyproject.toml
        pattern: "[Dd]jango"
    - file_contains:
        path: requirements.txt
        pattern: "[Dd]jango"
---

# Django Stack Profile (backend + database)

Registers Django projects with the SDLC pipeline. Auto-detected by presence of `manage.py`, or Django listed in `pyproject.toml` or `requirements.txt`.

This plugin owns the **backend** and **database** aspects. The `django-architect` renders Django templates (server-side views) as part of the backend aspect AND designs the DRF serializer / API contract when a SPA frontend plugin is active:

- Django templates (server-rendered) → handled by `django-architect` (backend aspect)
- DRF REST API → handled by `django-architect` (backend aspect, documents the contract)
- Vue / React SPA → a frontend-aspect plugin (`vue-plugin`, `react-plugin`) wins the frontend aspect; `django-architect` provides the DRF API contract it consumes

## Agents per phase

```yaml
business_analysis: business-analyst      # core agent (aspect-agnostic)
development:
  backend: django-architect              # owned by this plugin
database: django-migrations-specialist   # extra phase, aspect=database
qa: qa-engineer                          # core agent (aspect-agnostic in v1)
security: security-analyst               # core agent
documentation: document-writer           # core agent
```

Note: this plugin does NOT declare `development.frontend`. That slot is filled by whichever frontend-aspect plugin is active in the project (for SPA frontends). Django templates are handled by `django-architect` under the backend aspect.

## Convention skills to apply

- python-foundation:python-conventions
- python-foundation:python-tooling
- python-foundation:pytest-testing
- django-plugin:django-conventions
- django-plugin:django-orm-patterns

## Extra phases

- name: database
  after: development
  agent: django-migrations-specialist
  aspect: database
  description: |
    Finalize Django model field types, db_index/unique/db_constraint options, Meta indexes and constraints,
    run makemigrations, review with sqlmigrate, run migrate, verify with migrate --check.
    Skip if the development phase made no model changes.

## Phase prompts injection

For development phase (backend aspect), inject:
> You are working on the **backend** aspect of a **Django** project. Your scope:
> - Views (CBV and FBV), DRF ViewSets and serializers, forms, URLconf, middleware, signals, model *definitions* only (django-migrations-specialist finalizes field types, indexes, and runs migrations in the next phase), Django template rendering, and DRF API contract design.
> - For SPA frontends (Vue/React) the frontend-aspect agent runs separately and handles UI — you design and document the DRF API contract (serializer fields + endpoint shape) it consumes. For traditional Django template projects, you render the views yourself.
>
> Read `settings.py` or the `settings/` split (`base.py`, `local.py`, `production.py`) to learn the Django version, installed apps, and auth configuration before writing code.
>
> Available Django management commands via `python manage.py`:
> - `startapp <name>` — scaffold a new application
> - `shell` — open an interactive Django shell for quick verification
> - `check` — validate the Django configuration (runs system checks)
>
> Apply `django-plugin:django-conventions`:
> - **URLconf:** `path()`/`re_path()` with `include()` and `app_name` namespacing. Use DRF `DefaultRouter` for ViewSets. No hardcoded URL strings in view code.
> - **DRF ViewSets:** use `ModelViewSet` or `ReadOnlyModelViewSet` with explicit `queryset`, `serializer_class`, `permission_classes`, and `filterset_fields`. Default `permission_classes` to `[IsAuthenticated]`.
> - **Serializers:** `ModelSerializer` with explicit `fields` and `read_only_fields`. Write separate `CreateSerializer` vs `ListSerializer` when the exposed field sets differ. Validate in `validate_<field>` or `validate()` — never in view bodies.
> - **CBV:** use `LoginRequiredMixin` + `PermissionRequiredMixin`. Override `get_queryset()` for ownership scoping. Keep views thin — business logic in service functions or managers.
> - **Signals:** register via `AppConfig.ready()`. Keep signal handlers thin and side-effect-free.
> - **Auth:** `request.user`, `@login_required` / `LoginRequiredMixin` for session auth; DRF JWT or Token auth for APIs.
>
> Apply `django-plugin:django-orm-patterns` for model *definitions* — field types, `__str__`, choices, `class Meta` ordering. Leave `db_index`, constraints, and migrations to django-migrations-specialist.
>
> Apply `python-foundation:python-conventions` (type hints, dataclasses for value objects, enums for choices).
>
> After writing code:
> - `python manage.py check` — validates the Django configuration; fix all errors before continuing.
> - Formatting (`ruff format`, per file) and `ruff check .` (once, after you return) are hook-driven — do not run them yourself; lint findings reach the orchestrator as a retry hint.
>
> For SPA frontends (Vue/React): design and document the DRF API contract (endpoint URL, HTTP methods, serializer shape, authentication requirement); the frontend architect implements the UI. For traditional Django templates: render the views yourself.

For qa phase, inject:
> Apply `python-foundation:pytest-testing` plus Django-specific test types:
> - **`django.test.TestCase`** for unit/integration tests that touch the database — each test method runs inside a transaction that is rolled back after the method, giving DB isolation without truncation overhead.
> - **`django.test.Client`** for functional/HTTP tests: `self.client.get('/url/')`, assert via `self.assertEqual(response.status_code, 200)` or `self.assertContains(response, 'text')`.
> - **`rest_framework.test.APIClient`** for DRF API endpoint tests: `self.client.post('/api/orders/', data, format='json')`, assert `response.status_code` and `response.data`.
> - Use `pytest-django` for pytest integration: `@pytest.mark.django_db` on test functions/classes; use `django_db_setup` and `db` fixtures for database access.
>
> ```python
> # Django TestCase + Client example
> from django.test import TestCase
>
> class OrderViewTest(TestCase):
>     def test_list_returns_200(self):
>         self.client.force_login(self.user)
>         response = self.client.get('/orders/')
>         self.assertEqual(response.status_code, 200)
>
> # DRF APIClient example
> from rest_framework.test import APITestCase
>
> class OrderAPITest(APITestCase):
>     def test_create_order(self):
>         self.client.force_authenticate(user=self.user)
>         response = self.client.post('/api/orders/', {'product': 'widget', 'qty': 2}, format='json')
>         self.assertEqual(response.status_code, 201)
>         self.assertEqual(response.data['qty'], 2)
> ```
>
> Run: `python manage.py test` (Django test runner) or `pytest` (with `pytest-django` configured in `pytest.ini` / `pyproject.toml`).

For security phase, inject:
> Check Django-specific issues in addition to OWASP Top 10:
> - **`DEBUG = True` in production:** `settings.py` or `settings/production.py` must have `DEBUG = False`. Read the value from env: `DEBUG = env.bool('DEBUG', default=False)`. `DEBUG = True` exposes full stack traces and the interactive debugger to end users.
> - **Hardcoded `SECRET_KEY`:** any literal `SECRET_KEY = 'abc...'` in settings not excluded as local/dev/test is a critical risk — session forgery, CSRF bypass. Use `SECRET_KEY = env('SECRET_KEY')`.
> - **`ALLOWED_HOSTS = ['*']`:** enables Host header injection attacks. Set to explicit hostnames in production: `ALLOWED_HOSTS = ['myapp.example.com']`.
> - **`mark_safe()` / `{{ x|safe }}` in templates:** bypasses Django's auto-escaping — XSS risk if content is user-controlled. Only use on output that has been explicitly sanitized (e.g., via `bleach`). Never pass user-supplied text directly.
> - **`QuerySet.raw()` / `.extra()` with f-strings or `%` formatting:** SQL injection. Use parameterized forms: `.raw('SELECT ... WHERE id = %s', [id])`, or prefer ORM methods (`.filter()` is always parameterized).
> - **`@csrf_exempt`:** disables CSRF protection. Acceptable only for stateless token/JWT-authenticated API endpoints. Verify the view is not also reachable via browser session authentication.
> - **Missing `permission_classes` on DRF ViewSets:** DRF default is `IsAuthenticated` if `DEFAULT_PERMISSION_CLASSES` is set in `settings.py`, but this must be verified. Explicitly declare `permission_classes = [IsAuthenticated]` (or `[IsAuthenticatedOrReadOnly]` for public-read endpoints) on every ViewSet.
> - **CORS headers (`django-cors-headers`):** verify `CORS_ALLOW_ALL_ORIGINS = False` in production. Use an explicit `CORS_ALLOWED_ORIGINS` list.

## Post-pipeline checks

- `ruff format --check .`
- `python manage.py test` or `pytest`
- `python manage.py migrate --check`
- `python manage.py check --deploy`

These run after the documentation phase. They are advisory — failures are reported but do not retry.

## MCP integration

Django has no standard MCP server. Agents use `python manage.py` via Bash (or `docker compose exec -T app python manage.py …` in Dockerized setups) for code generation, configuration validation, and shell introspection. The pipeline runs fully without any MCP server.
