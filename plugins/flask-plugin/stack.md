---
stack: flask
priority: 150
aspects: [backend, database]
detect:
  any:
    - file_contains:
        path: pyproject.toml
        pattern: "[Ff]lask"
    - file_contains:
        path: requirements.txt
        pattern: "[Ff]lask"
---

# Flask Stack Profile (backend + database)

Registers Flask projects with the SDLC pipeline. Auto-detected by `Flask` or `flask` listed in `pyproject.toml` or `requirements.txt`.

Flask is a minimalist microframework supporting **both** server-rendered Jinja2 templates and JSON APIs. `flask-architect` handles both modes — it detects the project's rendering mode from the existing codebase and the business analysis spec. Database migrations use Flask-Migrate, which wraps Alembic and is managed via `flask db` commands.

This plugin owns the **backend** and **database** aspects. For SPA frontend projects, `flask-architect` documents the JSON API contract; frontend-aspect plugins (`vue-plugin`, `react-plugin`) implement the UI.

## Agents per phase

```yaml
business_analysis: business-analyst        # core agent
development:
  backend: flask-architect                  # owned by this plugin
database: flask-migrate-specialist          # extra phase, aspect=database
qa: qa-engineer                             # core agent
security: security-analyst                  # core agent
documentation: document-writer              # core agent
```

Note: this plugin does NOT declare `development.frontend` for SPA mode. That slot is filled by whichever frontend-aspect plugin is active in the project. For Jinja2 (server-rendered) mode, no separate frontend plugin is needed.

## Convention skills to apply

- python-foundation:python-conventions
- python-foundation:python-tooling
- python-foundation:pytest-testing
- flask-plugin:flask-conventions
- flask-plugin:sqlalchemy-patterns

## Extra phases

```yaml
- name: database
  after: development
  agent: flask-migrate-specialist
  aspect: database
  description: |
    Finalize SQLAlchemy model configurations (column types, indexes, unique constraints, relationships),
    run flask db migrate, review with flask db upgrade --sql, run flask db upgrade, verify with flask db check.
    Skip if the development phase made no model changes.
```

## Phase prompts injection

For development phase (backend aspect), inject:
> You are working on the **backend** aspect of a **Flask** project. Your scope:
> - Application factory (`create_app(config_name)`), Blueprint registration with `url_prefix`, view functions and `MethodView` class-based views, Flask-Login (session-based browser auth) or flask-jwt-extended (stateless API auth), Jinja2 template rendering (server-rendered mode) OR JSON responses (API mode), Marshmallow schema validation (for JSON APIs) or WTForms (for HTML forms with CSRF), error handlers, extension initialization, and SQLAlchemy ORM model *definitions* — flask-migrate-specialist finalizes column types, indexes, and runs migrations in the next phase.
> - For SPA frontends (Vue/React): the frontend-aspect agent runs separately and handles UI — you design and document the JSON API contract (endpoint path + method + Marshmallow schema shape) it consumes.
> - For Jinja2 mode: render templates from `templates/` directory and return `render_template()` responses.
>
> Read `pyproject.toml`/`requirements.txt` to determine:
> - Flask version.
> - Auth: `flask-login` (session-based) vs `flask-jwt-extended` (token/stateless).
> - Validation: `marshmallow`/`flask-marshmallow` (for JSON APIs) vs `flask-wtf` (for HTML forms).
> - ORM: `flask-sqlalchemy` version (3.x uses `db.Model` with `Mapped`/`mapped_column`; 2.x uses `db.Column`).
>
> Apply `flask-plugin:flask-conventions`:
> - **App factory:** `create_app(config_name="development")` in `app/__init__.py`. Initialize extensions with `init_app(app)`. Register Blueprints via a `register_blueprints(app)` helper.
> - **Blueprints:** one Blueprint per feature with `url_prefix`. Import and register in the factory.
> - **Views:** `@blueprint.route()` on functions; `MethodView` for class-based API views (define `get`, `post`, `put`, `delete` methods).
> - **Validation:** `Schema.load(request.get_json())` with Marshmallow for JSON APIs; `form.validate_on_submit()` with WTForms for HTML forms. Never validate inline in view functions with manual `if` checks.
> - **Auth:** `@login_required` and `login_user()`/`logout_user()` for Flask-Login; `@jwt_required()` and `create_access_token()` for flask-jwt-extended. Never hardcode `SECRET_KEY`.
> - **Config:** `class Config(BaseConfig)` split per environment. Secrets from `os.environ` or `python-decouple`. Never hardcode `SECRET_KEY` or database credentials.
> - **Templates:** `{{ var }}` is auto-escaped. Use `{{ var|safe }}` only for content pre-sanitized with bleach. Never pass `Markup()` on user-controlled data.
> - **Error handlers:** `@app.errorhandler(404)` returning JSON or HTML depending on mode. Detect mode from `request.accept_mimetypes`.
>
> Apply `flask-plugin:sqlalchemy-patterns` for model *definitions* — flask-migrate-specialist finalizes column types and indexes in the next phase.
>
> Apply `python-foundation:python-conventions` (type hints, dataclasses for value objects, enums for choices).
>
> After writing code:
> - `flask --app <module> check` — Flask app config check (if available in the project).
> - Formatting (`ruff format`, per file) and `ruff check .` (once, after you return) are hook-driven — do not run them yourself; lint findings reach the orchestrator as a retry hint.
>
> Note: for SPA frontends, provide an explicit **JSON API contract** (endpoint path + HTTP method + Marshmallow schema shape) in the development report for the SPA frontend architect.

For qa phase, inject:
> Apply `python-foundation:pytest-testing` plus Flask-specific test patterns:
> - **Flask test client:** `app.test_client()` for HTTP requests in tests. Use `with app.test_request_context()` when you need to call view helpers outside of a request.
> - **pytest-flask:** use the `@pytest.fixture` pattern for the test client:
>   ```python
>   import pytest
>   from myapp import create_app
>
>   @pytest.fixture
>   def app():
>       app = create_app("testing")
>       yield app
>
>   @pytest.fixture
>   def client(app):
>       return app.test_client()
>
>   def test_index(client):
>       response = client.get("/")
>       assert response.status_code == 200
>
>   def test_create_user(client):
>       response = client.post("/users/", json={"email": "a@b.com", "password": "secret"})
>       assert response.status_code == 201
>       assert response.get_json()["email"] == "a@b.com"
>   ```
> - **HTML endpoints:** check `response.status_code`, `response.data` (bytes), `b"expected text" in response.data`.
> - **JSON endpoints:** check `response.status_code`, `response.get_json()` dict.
> - **Database isolation:** configure a separate test DB in the `testing` config (SQLite in-memory is common: `SQLALCHEMY_DATABASE_URI = "sqlite:///:memory:"`). Use transaction rollback per test or recreate tables per test session.
>
> Run: `pytest` or `python -m pytest`

For security phase, inject:
> Check Flask-specific issues in addition to OWASP Top 10:
> - **Hardcoded SECRET_KEY:** `SECRET_KEY = "..."` or `app.secret_key = "..."` as a literal string is a critical risk. Flask sessions are signed with `SECRET_KEY`; a known or weak key allows session forgery. Always read from environment: `SECRET_KEY = os.environ["SECRET_KEY"]` or via python-decouple.
> - **Debug mode:** `app.run(debug=True)` in non-development context exposes the Werkzeug interactive debugger — full remote code execution risk. Control via env var: `DEBUG = os.environ.get("FLASK_DEBUG", "0") == "1"`. Never set `debug=True` in production.
> - **Jinja2 `|safe` filter:** `{{ x|safe }}` bypasses Jinja2 auto-escaping. Any user-controlled content passed through `|safe` without prior sanitization is a stored XSS risk. Only use `|safe` for content sanitized with bleach or similar. Audit all `|safe` usages in template files.
> - **`Markup()` on user input:** `Markup(user_data)` marks a string as HTML-safe and bypasses Jinja2 escaping. Never call `Markup()` on user-controlled data. Use only for static, developer-controlled HTML strings.
> - **CSRF disabled:** `WTF_CSRF_ENABLED = False` disables CSRF protection for all WTForms. Only disable for stateless token-auth APIs (flask-jwt-extended). Never disable for session-based HTML form endpoints.
> - **SQL injection via `text()`:** `db.session.execute(text(f"... WHERE id = {user_id}"))` or `text("..." % values)` is a SQL injection risk. Use parameterized `text()` with bound params: `db.session.execute(text("... WHERE id = :id"), {"id": user_id})`.
> - **CORS misconfiguration:** if using flask-cors, `CORS(app)` with default `origins="*"` allows any origin. Use `CORS(app, origins=settings.CORS_ALLOWED_ORIGINS)` with an explicit list.

## Post-pipeline checks

- `ruff format --check .`
- `pytest`
- `flask db check`
- `mypy .` (advisory)

These run after the documentation phase. They are advisory — failures are reported but do not retry.

## MCP integration

Flask has no standard MCP server. Agents use the Flask CLI and Python via Bash (or `docker compose exec -T app …` in Dockerized setups) for running the server, migrations, and tests. The pipeline runs fully without any MCP server.
