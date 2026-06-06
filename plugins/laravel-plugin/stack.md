---
stack: laravel
aspects: [backend, database]
priority: 100
detect:
  all:
    - file_exists: composer.json
    - file_contains:
        path: composer.json
        pattern: '"laravel/framework"'
---

# Laravel Stack Profile (backend + database)

Registers Laravel projects with the SDLC pipeline. Auto-detected by presence of `composer.json` containing `"laravel/framework"`.

This plugin owns the **backend** and **database** aspects. Frontend is handled by a separate plugin matching the actual frontend stack:
- Inertia + Vue → `inertia-vue-plugin`
- Inertia + React → `inertia-react-plugin`
- Livewire → `laravel-livewire-plugin` (future)
- Alpine + Blade → `laravel-blade-plugin` (future)
- API-only (no frontend) → no frontend plugin needed

## Agents per phase

```yaml
business_analysis: business-analyst         # core agent (aspect-agnostic)
development:
  backend: laravel-architect                # owned by this plugin
database: artisan-specialist                # extra phase, aspect=database
qa: qa-engineer                             # core agent (aspect-agnostic in v1)
security: security-analyst                  # core agent
documentation: document-writer              # core agent
```

Note: this plugin does NOT declare `development.frontend`. That slot is filled by whichever frontend-aspect plugin is active in the project.

## Convention skills to apply

- php-foundation:php-conventions
- php-foundation:composer-tooling
- php-foundation:php-testing
- laravel:laravel-conventions
- laravel:eloquent-patterns

## Extra phases

- name: database
  after: development
  agent: artisan-specialist
  aspect: database
  description: |
    Run migrations, factories, and seeders. Verify schema integrity. Update model factories
    to reflect schema changes. Skip if the development phase made no DB-related changes.

## Phase prompts injection

For development phase (backend aspect), inject:
> You are working on the **backend** aspect. Your scope:
> - Eloquent models, migrations stubs (artisan-specialist elaborates), Form Requests, Policies, Actions, Controllers, routes, providers, jobs, observers.
> - You DO NOT write frontend code (Vue/React/Blade/Livewire). The frontend-aspect agent will run separately and handle UI.
> - You DO design the backend API contract that the frontend will consume — document it clearly in your output for the frontend agent.
>
> Use Artisan commands for code generation where appropriate:
> `php artisan make:model -mfsc`, `make:request`, `make:policy`, `make:action` (if Spatie laravel-actions installed).
>
> Follow PSR-12 and Laravel conventions:
> - Action pattern (single-action invokable classes when business logic is non-trivial)
> - Form Requests for validation, never inline `$request->validate()`
> - Policies for authorization, never inline `Gate::allows()` in controllers
> - Eloquent over raw SQL; if raw SQL is necessary, use parameterized bindings
> - Resource controllers with explicit `__invoke` methods for non-CRUD endpoints
>
> Apply skills: `laravel:laravel-conventions`, `laravel:eloquent-patterns`.
>
> If Laravel Boost MCP is available (`mcp__laravel-boost__artisan`), prefer it for `make:*` Artisan commands; otherwise use Bash.
>
> Run after writing code:
> - `./vendor/bin/pint` (auto-formats, do not iterate on style issues)
> - `./vendor/bin/phpstan analyse` (if installed; treat warnings as advisory unless they block compilation)

For qa phase, inject:
> Use Pest 4 (preferred) or PHPUnit. Use Laravel testing helpers:
> - `RefreshDatabase` trait for database state isolation
> - `actingAs($user)` for authenticated requests
> - `assertDatabaseHas` / `assertDatabaseMissing` for state verification
> - HTTP test helpers: `get()`, `post()`, `assertOk()`, `assertJsonStructure()`
>
> Test command: `php artisan test --coverage` (or `./vendor/bin/pest --coverage` if Pest installed directly).
>
> If using SQLite for tests (config/database.php `testing` connection), be aware some Postgres-specific behaviors won't catch. Note this in your QA report.

For security phase, inject:
> Check Laravel-specific issues in addition to OWASP Top 10:
> - **Mass assignment:** Every Eloquent model touched should have `$fillable` or `$guarded` set explicitly. Never `$guarded = []` in production code.
> - **Gates / Policies coverage:** Every authorization check should go through `Gate::authorize()` or a Policy method. No inline role checks like `if ($user->role === 'admin')`.
> - **Raw query usage:** Any `DB::raw`, `whereRaw`, `selectRaw`, or `\DB::statement` must use parameter bindings.
> - **`.env` exposure:** Verify no `.env` is committed (check `.gitignore`). Verify no env values leak into client-side bundles.
> - **`APP_DEBUG`:** Production config should have `APP_DEBUG=false`. If the changes touch `.env.example`, verify.
> - **Mail / Queue / Cache config:** Verify no credentials hardcoded; all from `config()` reading `env()`.
> - **CSRF on state-changing routes:** Any non-GET route in `routes/web.php` must be inside the default web middleware group (which includes `VerifyCsrfToken`).

## Post-pipeline checks

- `./vendor/bin/pint --test`
- `php artisan test`
- `php artisan route:list`

These run after the documentation phase. They are advisory — failures are reported but do not retry.

## MCP integration

The `laravel-boost` MCP server provides Artisan-aware tools (`mcp__laravel-boost__artisan`, `mcp__laravel-boost__schema`, `mcp__laravel-boost__route_list`, `mcp__laravel-boost__tinker`). When wired, agents use it instead of Bash for Artisan operations.

**Detection:** if `laravel/boost` appears in `composer.json` `require-dev`, the server is likely installed. Wiring is manual — see `mcp.json` for the fragment to merge into the project's `.mcp.json`.

**Graceful degradation:** agents fall back to `php artisan …` (or `docker compose exec -T app php artisan …`) when Boost MCP tools are unavailable.
