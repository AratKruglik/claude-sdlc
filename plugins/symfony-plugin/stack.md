---
stack: symfony
aspects: [backend, database]
priority: 100
detect:
  all:
    - file_exists: composer.json
    - file_contains:
        path: composer.json
        pattern: '"symfony/framework-bundle"'
---

# Symfony Stack Profile (backend + database)

Registers Symfony projects with the SDLC pipeline. Auto-detected by presence of `composer.json` containing `"symfony/framework-bundle"`.

This plugin owns the **backend** and **database** aspects. The `symfony-architect` renders Twig server-side views as part of the backend aspect AND designs the Serializer / API contract (DTO + serialization groups) for when a SPA frontend plugin is active:

- Twig (server-rendered) → handled by `symfony-architect` (backend aspect)
- API Platform / JSON API → handled by `symfony-architect` (backend aspect, documents the contract)
- Vue / React SPA → a frontend-aspect plugin (`vue-plugin`, `react-plugin`) wins the frontend aspect; `symfony-architect` provides the API contract it consumes

## Agents per phase

```yaml
business_analysis: business-analyst         # core agent (aspect-agnostic)
development:
  backend: symfony-architect                # owned by this plugin
database: doctrine-specialist               # extra phase, aspect=database
qa: qa-engineer                             # core agent (aspect-agnostic in v1)
security: security-analyst                  # core agent
documentation: document-writer              # core agent
```

Note: this plugin does NOT declare `development.frontend`. That slot is filled by whichever frontend-aspect plugin is active in the project (for SPA frontends). Twig views are handled by `symfony-architect` under the backend aspect.

## Convention skills to apply

- php-foundation:php-conventions
- php-foundation:composer-tooling
- php-foundation:php-testing
- symfony-plugin:symfony-conventions
- symfony-plugin:doctrine-patterns

## Extra phases

- name: database
  after: development
  agent: doctrine-specialist
  aspect: database
  description: |
    Finalize Doctrine entity mappings, generate the migration via doctrine:migrations:diff,
    review the generated SQL, write/update fixtures, run the migration and verify the schema.
    Skip if the development phase made no entity/mapping changes.

## Phase prompts injection

For development phase (backend aspect), inject:
> You are working on the **backend** aspect of a **Symfony** project. Your scope:
> - Controllers (attribute routing), DTOs, services, Form types, Validation constraints, Voters (authorization), Doctrine entity *mappings* (doctrine-specialist generates migrations in the next phase), Messenger messages/handlers, the Serializer / API contract, and Twig templates.
> - For SPA frontends (Vue/React) the frontend-aspect agent runs separately and handles UI — you design and document the API / serialization contract (DTO shape + serialization groups) it consumes. For Twig projects, you render the views yourself.
>
> Use Symfony Maker where appropriate (if `symfony/maker-bundle` is installed):
> `php bin/console make:controller`, `make:entity`, `make:form`, `make:voter`, `make:validator`, `make:message`.
>
> Apply `symfony-plugin:symfony-conventions`:
> - **Attribute routing:** `#[Route('/path', name: '...', methods: ['GET'])]` on controller actions. No YAML/XML routing for new code.
> - **Controllers as services + constructor injection:** extend `AbstractController`; inject collaborators via the constructor (never `@required`/property injection). Action arguments are autowired (services, `Request`, route params, `#[MapRequestPayload]` DTOs).
> - **Validation:** Constraint attributes (`#[Assert\NotBlank]`, etc.) on DTOs/entities + `#[Valid]`. Never validate inline in the controller body.
> - **Authorization via Voters:** `#[IsGranted('...')]` / `$this->denyAccessUnlessGranted()` backed by a Voter or `security.yaml` `access_control`. Never inline `if (in_array('ROLE_ADMIN', $user->getRoles()))`.
> - **Serializer / DTOs:** expose data through DTOs or serialization groups — never serialize a raw entity with all fields.
> - **Configuration:** services autowired/autoconfigured in `config/services.yaml`; env values via `%env(...)%`, never hardcoded.
>
> Apply `symfony-plugin:doctrine-patterns` for entity mappings (the mapping is the source of truth; migrations are generated from it). Stub the entity attributes here; doctrine-specialist finalizes indexes/constraints and generates the migration next.
>
> Apply `php-foundation:php-conventions` (strict_types, readonly DTOs, enums, PSR-12) and `php-foundation:composer-tooling` (read composer.json for the PHP/Symfony version).
>
> After writing code:
> - `php bin/console lint:container` — validates the DI wiring; fix errors.
> - `vendor/bin/php-cs-fixer fix` (auto-formats; do not iterate on style).
> - `vendor/bin/phpstan analyse` if installed (treat warnings as advisory unless they block).
> - `php -l <changed-file>` if unsure about syntax.

For qa phase, inject:
> Apply `php-foundation:php-testing` plus Symfony-specific test types:
> - `KernelTestCase` for service/integration tests with the real container (boot the kernel, fetch services from `self::getContainer()`).
> - `WebTestCase` for functional/HTTP tests (`$client = static::createClient(); $client->request(...)`; assert via `$this->assertResponseIsSuccessful()`).
> - Pure unit tests (`PHPUnit\Framework\TestCase`) for logic with no container — fastest, prefer these.
> - For database isolation use `dama/doctrine-test-bundle` (wraps each test in a transaction that rolls back) and `doctrine/doctrine-fixtures-bundle` for seed data.
>
> ```php
> final class UserControllerTest extends WebTestCase
> {
>     public function test_it_shows_a_user(): void
>     {
>         $client = static::createClient();
>         $client->request('GET', '/users/1');
>
>         $this->assertResponseIsSuccessful();
>         $this->assertSelectorTextContains('h1', 'Alice');
>     }
> }
> ```
>
> Run: `php bin/phpunit` (or `vendor/bin/phpunit`).

For security phase, inject:
> Check Symfony-specific issues in addition to OWASP Top 10:
> - **Authorization via Voters / access_control:** every protected action goes through `#[IsGranted]`, `denyAccessUnlessGranted()`, or `security.yaml` `access_control`. No inline `$user->getRoles()` / `in_array('ROLE_...')` checks. No `PUBLIC_ACCESS` on `^/`.
> - **CSRF:** browser-facing forms keep `csrf_protection` enabled. Stateless token/JWT APIs may disable it — verify the decision is intentional and documented.
> - **Secrets:** no hardcoded credentials in `config/**` or PHP. All sensitive values via `%env(...)%` or the Secrets Vault. Verify `.env` is gitignored and `.env.local`/secrets are not committed.
> - **DQL injection:** any `createQuery` / `->where()` with string concatenation must be rewritten with `setParameter()` and named/positional placeholders.
> - **Over-exposure via Serializer:** entities serialized without groups can leak internal fields (password hashes, tokens). Verify serialization groups or DTOs are used.
> - **Mass assignment / binding:** Form types and `#[MapRequestPayload]` DTOs should bind only allowed fields; separate Create vs Update DTOs where the field sets differ.
> - **Debug surface:** no `dd()`/`dump()` left in code; `APP_ENV=prod` disables the profiler/debug toolbar; `APP_DEBUG=0` in production.

## Post-pipeline checks

- `vendor/bin/php-cs-fixer fix --dry-run --diff`
- `php bin/phpunit`
- `php bin/console lint:container`
- `php bin/console debug:router`
- `php bin/console doctrine:schema:validate`

These run after the documentation phase. They are advisory — failures are reported but do not retry.

## MCP integration

Symfony has no standard MCP server equivalent to Laravel Boost. Agents use `php bin/console` via Bash (or `docker compose exec -T php bin/console …` in Dockerized setups) for code generation, schema inspection, and routing/container introspection. The pipeline runs fully without any MCP server.
