---
name: django-conventions
description: |
  Django web framework conventions: app layout, settings split (base/local/production), URLconf with app namespacing, CBV and DRF ViewSets, DRF serializers and permissions, form validation, signals, Django admin registration, and middleware. Activated automatically by django-plugin/stack.md. Works alongside python-foundation:python-conventions and django-plugin:django-orm-patterns.

  Use this skill to:
  - Structure a Django project with multiple apps and correct URLconf hierarchy.
  - Write CBVs and DRF ViewSets with appropriate permissions and serializers.
  - Configure settings correctly for different environments.
  - Use signals for decoupled event handling between apps.
  - Register models in Django admin with useful list_display and search_fields.

  Do NOT use this skill for:
  - Django ORM model field finalization and migration patterns — see django-plugin:django-orm-patterns.
  - Python language idioms (type hints, dataclasses, enums) — see python-foundation:python-conventions.
  - Testing patterns — see python-foundation:pytest-testing.
user-invocable: false
paths: ["**/*.py", "**/templates/**"]
---

# Django Conventions

This skill encodes the conventions used across modern Django projects (Django 4.x / 5.x). Apply alongside `python-foundation:python-conventions` (language idioms) and `django-plugin:django-orm-patterns` (model/query patterns) when implementing features.

## 1. Detection

Before writing code, read:
- `manage.py` — confirms this is a Django project.
- `settings.py` or `settings/base.py` — check `DJANGO_VERSION`, `INSTALLED_APPS`, `REST_FRAMEWORK` dict (DRF present?), `AUTH_USER_MODEL`.
- The project `urls.py` — understand the existing URL hierarchy and namespace conventions.
- `requirements.txt` or `pyproject.toml` — note the exact Django version and whether DRF, `django-environ`, `django-filter`, `pytest-django`, etc. are present.

## 2. Project and app layout

Prefer a dedicated `apps/` directory for application modules and a `config/` directory for project-level config. New apps are registered in `INSTALLED_APPS` using their `AppConfig` dotted path.

```
myproject/
  manage.py
  config/
    settings/
      base.py
      local.py
      production.py
    urls.py
    wsgi.py
    asgi.py
  apps/
    users/
      migrations/
      models.py
      views.py
      serializers.py
      urls.py
      admin.py
      apps.py
      signals.py
    orders/
      migrations/
      models.py
      views.py
      serializers.py
      urls.py
      admin.py
      apps.py
```

`apps.py` for each application:

```python
from django.apps import AppConfig

class OrdersConfig(AppConfig):
    default_auto_field = 'django.db.models.BigAutoField'
    name = 'apps.orders'
    verbose_name = 'Orders'

    def ready(self) -> None:
        import apps.orders.signals  # noqa: F401 — registers signal handlers
```

## 3. Settings split

Production settings must never contain `DEBUG = True` or a hardcoded `SECRET_KEY`.

```python
# config/settings/base.py
import environ

env = environ.Env()

SECRET_KEY = env('SECRET_KEY')
DEBUG = env.bool('DEBUG', default=False)
ALLOWED_HOSTS = env.list('ALLOWED_HOSTS')

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'rest_framework',
    'corsheaders',
    'apps.users',
    'apps.orders',
]

DATABASES = {
    'default': env.db('DATABASE_URL'),
}
```

```python
# config/settings/local.py
from .base import *  # noqa: F401, F403

DEBUG = True
ALLOWED_HOSTS = ['localhost', '127.0.0.1']
```

```python
# config/settings/production.py
from .base import *  # noqa: F401, F403

SECURE_SSL_REDIRECT = True
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
```

## 4. URLconf

Project `urls.py` uses `include()` with app namespaces. DRF ViewSets are registered on a `DefaultRouter` in the app's `urls.py`.

```python
# config/urls.py
from django.contrib import admin
from django.urls import path, include

urlpatterns = [
    path('admin/', admin.site.urls),
    path('api/', include('apps.orders.urls', namespace='orders')),
    path('', include('apps.users.urls', namespace='users')),
]
```

```python
# apps/orders/urls.py
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from . import views

app_name = 'orders'

router = DefaultRouter()
router.register(r'orders', views.OrderViewSet, basename='order')

urlpatterns = [
    path('', include(router.urls)),
    path('orders/<int:pk>/cancel/', views.OrderCancelView.as_view(), name='order-cancel'),
]
```

## 5. DRF ViewSets and serializers

### ModelViewSet

```python
from rest_framework import viewsets, permissions
from django_filters.rest_framework import DjangoFilterBackend
from .models import Order
from .serializers import OrderSerializer, OrderCreateSerializer

class OrderViewSet(viewsets.ModelViewSet):
    queryset = Order.objects.select_related('user').order_by('-created_at')
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [DjangoFilterBackend]
    filterset_fields = ['status']

    def get_serializer_class(self):
        if self.action == 'create':
            return OrderCreateSerializer
        return OrderSerializer

    def get_queryset(self):
        return super().get_queryset().filter(user=self.request.user)

    def perform_create(self, serializer):
        serializer.save(user=self.request.user)
```

### Serializers

Use separate serializers when the create/update payload differs from the list/retrieve shape.

```python
from rest_framework import serializers
from .models import Order

class OrderSerializer(serializers.ModelSerializer):
    class Meta:
        model = Order
        fields = ['id', 'status', 'product', 'qty', 'created_at']
        read_only_fields = ['id', 'status', 'created_at']


class OrderCreateSerializer(serializers.ModelSerializer):
    class Meta:
        model = Order
        fields = ['product', 'qty']

    def validate_qty(self, value: int) -> int:
        if value <= 0:
            raise serializers.ValidationError("Quantity must be positive.")
        return value

    def validate(self, attrs: dict) -> dict:
        # cross-field validation
        return attrs
```

### Nested serializer

```python
class OrderWithUserSerializer(serializers.ModelSerializer):
    user = UserSummarySerializer(read_only=True)

    class Meta:
        model = Order
        fields = ['id', 'user', 'status', 'created_at']
```

## 6. DRF permissions

Always declare `permission_classes` explicitly on every ViewSet and `APIView`. Do not rely on global defaults alone.

```python
from rest_framework.permissions import BasePermission, IsAuthenticated, IsAuthenticatedOrReadOnly

# Default: require authentication for all methods
permission_classes = [IsAuthenticated]

# Public read, authenticated write
permission_classes = [IsAuthenticatedOrReadOnly]

# Custom permission
class IsOwner(BasePermission):
    def has_object_permission(self, request, view, obj) -> bool:
        return obj.user == request.user
```

Combine permissions with a list: `permission_classes = [IsAuthenticated, IsOwner]`.

## 7. Class-based views (CBV)

Use `LoginRequiredMixin` and `PermissionRequiredMixin` for access control. Override `get_queryset()` to scope results to the requesting user. Keep views thin — delegate business logic to service functions.

```python
from django.contrib.auth.mixins import LoginRequiredMixin, PermissionRequiredMixin
from django.views.generic import ListView, CreateView
from django.urls import reverse_lazy
from .models import Order
from .forms import OrderForm

class OrderListView(LoginRequiredMixin, ListView):
    model = Order
    template_name = 'orders/list.html'
    context_object_name = 'orders'
    paginate_by = 20

    def get_queryset(self):
        return Order.objects.filter(user=self.request.user).order_by('-created_at')

    def get_context_data(self, **kwargs):
        context = super().get_context_data(**kwargs)
        context['total'] = self.get_queryset().count()
        return context


class OrderCreateView(LoginRequiredMixin, CreateView):
    model = Order
    form_class = OrderForm
    template_name = 'orders/create.html'
    success_url = reverse_lazy('orders:list')

    def form_valid(self, form):
        form.instance.user = self.request.user
        return super().form_valid(form)
```

## 8. Forms

Use `ModelForm` for model-backed forms. Validate in `clean_<field>` or `clean()` — never in the view.

```python
from django import forms
from .models import Order

class OrderForm(forms.ModelForm):
    class Meta:
        model = Order
        fields = ['product', 'qty', 'notes']
        widgets = {
            'notes': forms.Textarea(attrs={'rows': 3}),
        }

    def clean_qty(self) -> int:
        qty = self.cleaned_data['qty']
        if qty <= 0:
            raise forms.ValidationError("Quantity must be positive.")
        return qty

    def clean(self) -> dict:
        cleaned_data = super().clean()
        product = cleaned_data.get('product')
        qty = cleaned_data.get('qty')
        # cross-field validation example
        if product and qty and qty > 100:
            raise forms.ValidationError("Cannot order more than 100 units of a single product.")
        return cleaned_data
```

## 9. Signals

Register signal handlers in `signals.py` and connect them in `AppConfig.ready()`. Keep handlers thin — for heavy work, dispatch to a background task (Celery, Django Q, etc.).

```python
# apps/orders/signals.py
from django.db.models.signals import post_save
from django.dispatch import receiver
from .models import Order

@receiver(post_save, sender=Order)
def notify_on_status_change(sender, instance: Order, created: bool, **kwargs) -> None:
    if not created and instance.tracker.has_changed('status'):
        # thin: just enqueue a notification task
        send_status_notification.delay(order_id=instance.pk, new_status=instance.status)
```

```python
# apps/orders/apps.py
class OrdersConfig(AppConfig):
    name = 'apps.orders'

    def ready(self) -> None:
        import apps.orders.signals  # noqa: F401
```

Best practices:
- Never do database writes in `post_save` handlers without `update_fields` guards — it can cause infinite loops.
- Use `transaction.on_commit()` to enqueue async tasks only after the DB transaction commits.
- Prefer custom model methods or service functions over signals for logic that must be tested directly.

## 10. Django admin

Register models with `@admin.register` and provide useful `list_display`, `list_filter`, and `search_fields`.

```python
from django.contrib import admin
from .models import Order

@admin.register(Order)
class OrderAdmin(admin.ModelAdmin):
    list_display = ['id', 'user', 'product', 'status', 'qty', 'created_at']
    list_filter = ['status', 'created_at']
    search_fields = ['user__email', 'product']
    readonly_fields = ['created_at', 'updated_at']
    ordering = ['-created_at']
```

## 11. Checklist before completing development phase

- [ ] All new ViewSets and `APIView` subclasses have explicit `permission_classes`
- [ ] Serializer validation uses `validate_<field>` / `validate()` — not view bodies
- [ ] CBVs use `LoginRequiredMixin` or `permission_classes` — no unprotected views
- [ ] `get_queryset()` scopes results to `request.user` where ownership applies
- [ ] Signal handlers are thin and registered in `AppConfig.ready()`
- [ ] Settings read secrets from env — no hardcoded `SECRET_KEY` or `DATABASE_URL`
- [ ] No `makemigrations` or `migrate` called — that is django-migrations-specialist
- [ ] `python manage.py check` passes with no errors
- [ ] `ruff format .` clean
