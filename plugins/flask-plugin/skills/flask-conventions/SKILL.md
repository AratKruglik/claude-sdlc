---
name: flask-conventions
description: |
  Flask web framework conventions: app factory pattern with create_app(), Blueprint registration with url_prefix, MethodView for class-based API views, Marshmallow schema validation, WTForms for HTML forms, Flask-Login for session auth, flask-jwt-extended for stateless API auth, Jinja2 template conventions, error handlers, and extension initialization. Activated automatically by flask-plugin/stack.md.

  Use this skill to:
  - Structure Flask applications with the app factory and per-feature Blueprints.
  - Validate JSON request data with Marshmallow and HTML forms with WTForms.
  - Implement session-based auth with Flask-Login or token auth with flask-jwt-extended.
  - Render Jinja2 templates safely or return JSON responses for API mode.
  - Register global error handlers for consistent error responses.

  Do NOT use this skill for:
  - SQLAlchemy ORM model patterns and Flask-Migrate — see flask-plugin:sqlalchemy-patterns.
  - Python language idioms — see python-foundation:python-conventions.
  - Testing patterns — see python-foundation:pytest-testing.
user-invocable: false
paths: ["**/*.py", "**/templates/**"]
---

# Flask Conventions

## Detection

Read `pyproject.toml` or `requirements.txt` before writing any Flask code:

```bash
grep -E "flask|Flask" requirements.txt pyproject.toml
```

Determine the installed extensions:

| Check | Meaning |
|---|---|
| `flask-login` present | Session-based auth — use `@login_required`, `login_user()`, `logout_user()` |
| `flask-jwt-extended` present | Token-based auth — use `@jwt_required()`, `create_access_token()` |
| `marshmallow` or `flask-marshmallow` present | JSON API validation — use `Schema.load()` / `Schema.dump()` |
| `flask-wtf` present | HTML form validation — use `FlaskForm` with `validate_on_submit()` |
| `flask-sqlalchemy` present | ORM — use `db.Model`, `db.session` |
| `flask-migrate` present | Migrations — `flask db migrate`, `flask db upgrade` |

---

## App factory

Define `create_app()` in `app/__init__.py`. Never instantiate `Flask` at module level in a way that creates side effects — the factory pattern allows multiple app instances for testing.

```python
# app/__init__.py
from flask import Flask

from app.config import config_by_name
from app.extensions import db, login_manager, migrate


def create_app(config_name: str = "development") -> Flask:
    app = Flask(__name__)
    app.config.from_object(config_by_name[config_name])

    _init_extensions(app)
    _register_blueprints(app)
    _register_error_handlers(app)

    return app


def _init_extensions(app: Flask) -> None:
    db.init_app(app)
    migrate.init_app(app, db)
    login_manager.init_app(app)


def _register_blueprints(app: Flask) -> None:
    from app.auth.views import auth_bp
    from app.users.views import users_bp
    from app.orders.views import orders_bp

    app.register_blueprint(auth_bp)
    app.register_blueprint(users_bp)
    app.register_blueprint(orders_bp)


def _register_error_handlers(app: Flask) -> None:
    from app.errors import register_error_handlers
    register_error_handlers(app)
```

Initialize extensions at **module level** in `app/extensions.py`, then call `.init_app(app)` in the factory. This avoids circular imports.

```python
# app/extensions.py
from flask_login import LoginManager
from flask_migrate import Migrate
from flask_sqlalchemy import SQLAlchemy

db = SQLAlchemy()
migrate = Migrate()
login_manager = LoginManager()
login_manager.login_view = "auth.login"
```

Config classes split per environment:

```python
# app/config.py
import os


class BaseConfig:
    SECRET_KEY = os.environ["SECRET_KEY"]
    SQLALCHEMY_TRACK_MODIFICATIONS = False


class DevelopmentConfig(BaseConfig):
    DEBUG = True
    SQLALCHEMY_DATABASE_URI = os.environ.get(
        "DATABASE_URL", "sqlite:///dev.db"
    )


class ProductionConfig(BaseConfig):
    DEBUG = False
    SQLALCHEMY_DATABASE_URI = os.environ["DATABASE_URL"]


class TestingConfig(BaseConfig):
    TESTING = True
    SQLALCHEMY_DATABASE_URI = "sqlite:///:memory:"
    WTF_CSRF_ENABLED = False


config_by_name = {
    "development": DevelopmentConfig,
    "production": ProductionConfig,
    "testing": TestingConfig,
}
```

Never hardcode `SECRET_KEY`. If the env var is missing, `os.environ["SECRET_KEY"]` raises `KeyError` at startup — fail fast rather than silently using a weak default.

---

## Blueprints

One Blueprint per feature with a `url_prefix`:

```python
# app/orders/views.py
from flask import Blueprint, jsonify, request
from flask_login import login_required

from app.orders.schemas import OrderSchema, OrderCreateSchema
from app.orders.service import get_order, create_order

orders_bp = Blueprint("orders", __name__, url_prefix="/orders")
order_schema = OrderSchema()
order_create_schema = OrderCreateSchema()


@orders_bp.route("/", methods=["GET"])
@login_required
def list_orders():
    orders = get_orders_for_current_user()
    return jsonify(order_schema.dump(orders, many=True))


@orders_bp.route("/", methods=["POST"])
@login_required
def create_order_view():
    data = order_create_schema.load(request.get_json())
    order = create_order(data)
    return jsonify(order_schema.dump(order)), 201
```

For class-based API views, use `MethodView`:

```python
from flask.views import MethodView


class OrderResource(MethodView):
    decorators = [login_required]

    def get(self, order_id: int):
        order = get_order(order_id)
        return jsonify(order_schema.dump(order))

    def put(self, order_id: int):
        data = order_schema.load(request.get_json(), partial=True)
        order = update_order(order_id, data)
        return jsonify(order_schema.dump(order))

    def delete(self, order_id: int):
        delete_order(order_id)
        return "", 204


orders_bp.add_url_rule(
    "/<int:order_id>",
    view_func=OrderResource.as_view("order_resource"),
)
```

---

## Marshmallow validation

Use Marshmallow for JSON API request validation and response serialization. Separate input and output schemas when field sets differ.

```python
# app/users/schemas.py
from marshmallow import Schema, ValidationError, fields, post_load, validates


class UserCreateSchema(Schema):
    email = fields.Email(required=True)
    password = fields.String(required=True, load_only=True)
    display_name = fields.String(required=True)

    @validates("password")
    def validate_password(self, value: str) -> None:
        if len(value) < 8:
            raise ValidationError("Password must be at least 8 characters.")

    @post_load
    def make_user_data(self, data: dict, **kwargs) -> dict:
        return data


class UserReadSchema(Schema):
    id = fields.Int(dump_only=True)
    email = fields.Email(dump_only=True)
    display_name = fields.String(dump_only=True)
    created_at = fields.DateTime(dump_only=True)
```

Usage in a view:

```python
user_create_schema = UserCreateSchema()
user_read_schema = UserReadSchema()


@users_bp.route("/", methods=["POST"])
def register():
    try:
        data = user_create_schema.load(request.get_json())
    except ValidationError as err:
        return jsonify({"errors": err.messages}), 422
    user = create_user(data)
    return jsonify(user_read_schema.dump(user)), 201
```

---

## WTForms

Use WTForms for **HTML form** validation (server-rendered Jinja2 mode). WTForms provides CSRF protection via Flask-WTF. Use `validate_on_submit()` which checks both `POST` and CSRF validity.

```python
# app/auth/forms.py
from flask_wtf import FlaskForm
from wtforms import PasswordField, StringField, SubmitField
from wtforms.validators import DataRequired, Email, Length


class LoginForm(FlaskForm):
    email = StringField("Email", validators=[DataRequired(), Email()])
    password = PasswordField("Password", validators=[DataRequired(), Length(min=8)])
    submit = SubmitField("Log In")
```

Usage in a view:

```python
@auth_bp.route("/login", methods=["GET", "POST"])
def login():
    form = LoginForm()
    if form.validate_on_submit():
        user = authenticate_user(form.email.data, form.password.data)
        if user:
            login_user(user)
            return redirect(url_for("users.profile"))
        form.email.errors.append("Invalid credentials.")
    return render_template("auth/login.html", form=form)
```

**When to use WTForms vs Marshmallow:**
- WTForms: HTML form submissions (`Content-Type: application/x-www-form-urlencoded`), Jinja2 templates, CSRF protection needed.
- Marshmallow: JSON request/response (`Content-Type: application/json`), API mode, SPA frontends.

---

## Flask-Login

Use Flask-Login for **session-based auth** (browser clients, Jinja2 mode).

```python
# app/extensions.py
from flask_login import LoginManager

login_manager = LoginManager()
login_manager.login_view = "auth.login"  # redirect for @login_required


@login_manager.user_loader
def load_user(user_id: str):
    from app.users.models import User
    return User.query.get(int(user_id))
```

The `User` model must implement `UserMixin`:

```python
# app/users/models.py
from flask_login import UserMixin
from app.extensions import db


class User(UserMixin, db.Model):
    __tablename__ = "users"
    id = db.Column(db.Integer, primary_key=True)
    email = db.Column(db.String(255), unique=True, nullable=False)
    hashed_password = db.Column(db.String(255), nullable=False)

    def get_id(self) -> str:
        return str(self.id)
```

Auth view functions:

```python
from flask_login import login_required, login_user, logout_user


@auth_bp.route("/login", methods=["POST"])
def login():
    user = authenticate_user(email, password)
    if user:
        login_user(user, remember=form.remember.data)
        return redirect(url_for("users.profile"))
    return jsonify({"error": "Invalid credentials"}), 401


@auth_bp.route("/logout", methods=["POST"])
@login_required
def logout():
    logout_user()
    return redirect(url_for("auth.login"))
```

---

## flask-jwt-extended

Use flask-jwt-extended for **token-based auth** (JSON API mode, SPA frontends).

```python
# app/extensions.py
from flask_jwt_extended import JWTManager

jwt = JWTManager()
```

Initialize in the factory:

```python
jwt.init_app(app)
```

Token creation in the login view:

```python
from flask_jwt_extended import create_access_token, create_refresh_token


@auth_bp.route("/login", methods=["POST"])
def login():
    data = login_schema.load(request.get_json())
    user = authenticate_user(data["email"], data["password"])
    if not user:
        return jsonify({"error": "Invalid credentials"}), 401
    access_token = create_access_token(identity=str(user.id))
    refresh_token = create_refresh_token(identity=str(user.id))
    return jsonify({"access_token": access_token, "refresh_token": refresh_token})
```

Protecting routes and getting the current identity:

```python
from flask_jwt_extended import get_jwt_identity, jwt_required


@users_bp.route("/me", methods=["GET"])
@jwt_required()
def get_current_user():
    user_id = get_jwt_identity()
    user = User.query.get(int(user_id))
    return jsonify(user_read_schema.dump(user))


@auth_bp.route("/refresh", methods=["POST"])
@jwt_required(refresh=True)
def refresh_token():
    user_id = get_jwt_identity()
    new_access_token = create_access_token(identity=user_id)
    return jsonify({"access_token": new_access_token})
```

---

## Jinja2 conventions

Organize templates under `app/templates/`. Use a base template with blocks:

```html
{# app/templates/base.html #}
<!DOCTYPE html>
<html>
<head>
    <title>{% block title %}My App{% endblock %}</title>
</head>
<body>
    <nav>
        {% if current_user.is_authenticated %}
            <a href="{{ url_for('auth.logout') }}">Log out</a>
        {% else %}
            <a href="{{ url_for('auth.login') }}">Log in</a>
        {% endif %}
    </nav>
    {% block content %}{% endblock %}
</body>
</html>
```

```html
{# app/templates/users/profile.html #}
{% extends "base.html" %}
{% block title %}Profile — {{ user.display_name }}{% endblock %}
{% block content %}
<h1>{{ user.display_name }}</h1>
<p>{{ user.email }}</p>
{% endblock %}
```

Key Jinja2 rules:
- `{{ user.name }}` — auto-escaped. Safe for all user-controlled strings.
- `{{ content|safe }}` — bypasses auto-escaping. Only use for content sanitized with `bleach.clean()`.
- `{{ url_for('orders.list_orders') }}` — always use `url_for()` for URLs, never hardcode paths.
- Never use `Markup(user_input)` — only use `Markup()` for static, developer-controlled HTML fragments.

---

## Error handlers

Register error handlers in the factory. Detect the request's preferred response format from `request.accept_mimetypes`:

```python
# app/errors.py
from flask import Flask, jsonify, render_template, request


def register_error_handlers(app: Flask) -> None:
    @app.errorhandler(404)
    def not_found(error):
        if request.accept_mimetypes.best == "application/json":
            return jsonify({"error": "not found", "status": 404}), 404
        return render_template("errors/404.html"), 404

    @app.errorhandler(422)
    def unprocessable(error):
        return jsonify({"error": "unprocessable entity", "status": 422}), 422

    @app.errorhandler(500)
    def internal_error(error):
        if request.accept_mimetypes.best == "application/json":
            return jsonify({"error": "internal server error", "status": 500}), 500
        return render_template("errors/500.html"), 500
```

---

## Checklist

Before handing off to flask-migrate-specialist:

- [ ] All Blueprints registered via `app.register_blueprint()` in the factory?
- [ ] All extensions initialized with `init_app(app)`?
- [ ] `SECRET_KEY` read from `os.environ`, never hardcoded?
- [ ] No `flask db migrate` or `flask db upgrade` called?
- [ ] No `{{ var|safe }}` on user-controlled data in templates?
- [ ] No `Markup(user_input)` calls?
- [ ] Every state-changing route protected by `@login_required` or `@jwt_required()` (or explicitly BA-approved for anonymous access)?
- [ ] `ruff format .` run and output is clean?
