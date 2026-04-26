---
stack: laravel
priority: 100
detect:
  all:
    - file_exists: composer.json
    - file_contains:
        path: composer.json
        pattern: '"laravel/framework"'
---

# Laravel Stack Profile

Registers Laravel + Inertia + Vue projects with the SDLC pipeline. Auto-detected by presence of `composer.json` containing `"laravel/framework"`.

## Agents per phase

- business_analysis: business-analyst        # core agent
- development: laravel-architect              # Laravel-specific
- database: artisan-specialist                # extra phase (see below)
- qa: qa-engineer                             # core agent
- security: security-analyst                  # core agent
- documentation: document-writer              # core agent

## Convention skills to apply

- laravel:laravel-conventions
- laravel:eloquent-patterns

## Extra phases

- name: database
  after: development
  agent: artisan-specialist
  description: |
    Run migrations, factories, and seeders. Verify schema integrity. Update model factories
    to reflect schema changes. Skip if the development phase made no DB-related changes.

## Phase prompts injection

For development phase, inject:
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
> Frontend (Inertia + Vue 3 Composition API):
> - Pages live in `resources/js/Pages/`
> - Forms use `useForm` from `@inertiajs/vue3`
> - Props typed via TypeScript when project uses TS, otherwise documented in PHPDoc on the controller
> - Layouts via `<script setup>` `defineOptions({ layout: AuthenticatedLayout })`
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
> - **Inertia data exposure:** Props passed to Inertia pages can leak sensitive data. Verify password hashes, internal IDs, etc., are not in `Inertia::render()` payloads.

## Post-pipeline checks

- `./vendor/bin/pint --test`
- `php artisan test`
- `php artisan route:list`

These run after the documentation phase. They are advisory — failures are reported but do not retry.
