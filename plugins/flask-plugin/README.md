# flask-plugin

Flask backend + database stack provider for the `claude-sdlc` marketplace.

Flask is a minimalist Python microframework that supports **both** server-rendered Jinja2 templates **and** JSON APIs. This plugin handles whichever mode the project uses. SPA frontends (Vue, React) connect to the Flask application via the JSON API contract that `flask-architect` designs and documents. The frontend aspect is handled by whichever frontend plugin is active (`vue-plugin`, `react-plugin`, etc.).

---

## Agents

| Agent | Phase | Aspect | Model / Effort | Responsibilities |
|---|---|---|---|---|
| `flask-architect` | development | backend | Sonnet / medium | Application factory (`create_app()`), Blueprint registration with `url_prefix`, view functions and `MethodView` class-based views, Flask-Login (session auth) or flask-jwt-extended (token auth), Jinja2 template rendering (server-rendered mode) or JSON responses (API mode), Marshmallow schema validation or WTForms for HTML forms, SQLAlchemy model *definitions* (column stubs), error handlers, extension initialization, JSON API contract for SPA frontend architects |
| `flask-migrate-specialist` | database (extra) | database | Sonnet / low | SQLAlchemy model column finalization (types, nullable, indexes, unique constraints, relationships), `flask db migrate`, SQL review with `flask db upgrade --sql`, `flask db upgrade`, verification with `flask db check`, rollback test |

---

## Skills

| Skill | Registered as | Summary |
|---|---|---|
| `flask-conventions` | `flask-plugin:flask-conventions` | App factory pattern, Blueprint structure, Marshmallow/WTForms validation, Flask-Login session auth, flask-jwt-extended token auth, Jinja2 template conventions, error handlers, extension init with `init_app()` |
| `sqlalchemy-patterns` | `flask-plugin:sqlalchemy-patterns` | Flask-SQLAlchemy model definitions with `db.Model`, synchronous `db.session` queries, relationships with explicit lazy loading, Flask-Migrate integration |

Also reuses:

- `python-foundation:python-conventions`
- `python-foundation:python-tooling`
- `python-foundation:pytest-testing`

---

## Jinja2 and JSON API modes

Flask supports both rendering:

- **Server-rendered (Jinja2):** `flask-architect` creates templates, uses WTForms for form validation, and renders HTML responses. WTForms provides CSRF protection for HTML forms.
- **JSON API:** `flask-architect` returns JSON responses, uses Marshmallow for serialization/deserialization, and documents the endpoint contract for SPA frontend plugins.

Both modes can coexist in a single Flask application. `flask-architect` detects the project mode from its existing structure and the business analysis spec.

---

## Dependencies

| Dependency | Role |
|---|---|
| `sdlc` | Core pipeline orchestration |
| `python-foundation` | Python conventions, tooling, and pytest patterns |

---

## Installation

```bash
/plugin install flask-plugin@sdlc-marketplace
# sdlc and python-foundation install as dependencies
```

The plugin activates automatically when `Flask` or `flask` is found in `pyproject.toml`, `requirements.txt`, `Pipfile`, `setup.py`, or `setup.cfg`.
