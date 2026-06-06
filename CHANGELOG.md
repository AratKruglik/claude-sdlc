# Changelog

All notable changes to the SDLC marketplace are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/), versioning is [SemVer](https://semver.org/) per plugin.

## [0.5.0] — marketplace v0.5.0

### Added — C# shared foundation + ASP.NET Core stack (2 new plugins)

- **`csharp-foundation` v0.0.1** — Pure shared skill library for any .NET project. No agent, no stack profile. Mirrors `java-foundation` / `php-foundation` / `js-foundation`. Provides:
  - `csharp-conventions` — Modern C# (C# 10+ / .NET 6+) idioms: nullable reference types, `record` / `readonly record struct`, primary constructors, pattern matching (switch expressions, property patterns, list patterns), `async`/`await` + `CancellationToken`, `IDisposable`/`IAsyncDisposable` + `using`, file-scoped namespaces, naming conventions (PascalCase / `_camelCase` fields / `I`-prefixed interfaces), class design rules (sealed, composition over inheritance).
  - `dotnet-tooling` — `dotnet` CLI (build/run/test/publish/format/restore), NuGet `PackageReference` lifecycle, central package management (`Directory.Packages.props`), `global.json` SDK pinning, `Directory.Build.props` solution-wide properties, `packages.lock.json`, `.editorconfig` + `dotnet format`.
  - `dotnet-testing` — xUnit (`[Fact]`/`[Theory]`/`[InlineData]`/`[MemberData]`), Moq (`MockBehavior.Strict`, `VerifyAll`) and NSubstitute, FluentAssertions (collections, exceptions, numeric/date, `BeEquivalentTo`), coverlet coverage + threshold enforcement, `IClassFixture<T>` for shared resources, test project layout.
  - `security-patterns.yaml` — C# security rules for `security-guidance`: `Process.Start`, `BinaryFormatter`/`LosFormatter`/`JavaScriptSerializer` deserialization, SQL concatenation into `CommandText`, hardcoded secrets, XXE via `DtdProcessing.Parse`.

- **`aspnet-core-plugin` v0.0.1** — ASP.NET Core backend + database stack provider (priority=100). Detects ASP.NET Core projects via `appsettings.json` (glob-based). Adds two agents plus two convention skills:
  - `aspnet-core-architect` (Sonnet/medium) — Minimal API endpoint groups with `TypedResults`, MVC `[ApiController]`, DTOs as `record` types, FluentValidation `AbstractValidator<T>`, DI lifetimes, Options pattern (`IOptions<T>`), policy-based and resource-based authorization, `ProblemDetails` error handling (RFC 9457), structured logging, JWT Bearer authentication, HTTPS/HSTS pipeline, User Secrets / Key Vault for secrets management, EF Core entity stubs. Designs the API contract for SPA frontend plugins.
  - `efcore-specialist` (Sonnet/low) — finalizes EF Core entity configurations (`IEntityTypeConfiguration<T>`, Fluent API, column types with `HasPrecision`/`HasMaxLength`, `OnDelete` cascade/restrict/set-null), generates migrations via `dotnet ef migrations add`, reviews the generated SQL, runs `dotnet ef database update`, rollback test. Runs in the extra `database` phase.
  - `aspnet-conventions` — Program.cs composition order, Minimal API endpoint groups, DI lifetimes, Options pattern, FluentValidation, `ProblemDetails`, structured logging, JWT Bearer, HTTPS/HSTS, configuration layering (appsettings + env vars + User Secrets), health checks (`/health/live` + `/health/ready`).
  - `efcore-patterns` — DbContext design with `ApplyConfigurationsFromAssembly`, Fluent API column types, relations (`HasOne`/`HasMany`, `OnDelete`), `AsNoTracking` projections to DTOs, avoiding N+1 (`Include`/`AsSplitQuery`), transactions, parameterized raw SQL (`FromSql(FormattableString)` — never `FromSqlRaw` with interpolation).
  - Phase-prompt injection: ASP.NET Core-specific dev (Program.cs layers, DTOs, validation, authorization, middleware order, secrets), QA (`WebApplicationFactory<TProgram>`, xUnit `IClassFixture`, EF Core in-memory / Testcontainers), and security (authorization gaps, anti-forgery, HTTPS/HSTS, CORS misconfiguration, EF Core raw SQL, over-posting, Data Protection, CSP) guidance.
  - `dotnet format` Stop hook + post-pipeline checks (`dotnet build`, `dotnet test`, `dotnet format --verify-no-changes`, `dotnet ef database update`).
  - `security-patterns.yaml` — ASP.NET Core security rules: `[AllowAnonymous]` on controllers, `FromSqlRaw` with string interpolation, `IgnoreAntiforgeryToken`, `AllowAnyOrigin`+`AllowCredentials`, hardcoded connection strings, entity binding (over-posting), HSTS misconfiguration, Data Protection not configured for cookie auth.

### Added — security-patterns.yaml for existing plugins

- **`laravel-plugin`** — Added `security-patterns.yaml` with Laravel-specific security rules: `$guarded = []` (mass assignment disabled), `DB::statement`/`whereRaw`/`selectRaw` string concatenation (SQL injection), `APP_DEBUG=true` in production, `Route::any()`, CSRF `$except = ['*']`, `{!! $var !!}` unescaped Blade output, hardcoded secrets, `Gate::before()` unconditional bypass.

### Changed

- **`js-foundation` — `security-patterns.yaml` updated**: standardized all rules to use `regex` + `paths` keys (removed non-standard `substrings` key). Added two new rules: `js_hardcoded_secret` (credentials in JS/TS source) and `js_prototype_pollution` (`__proto__` / `constructor.prototype` assignment). Existing rules (`dom_injection_innerhtml`, `child_process_exec`, `dom_injection_document_write`, `js_dynamic_code_execution`) updated with explicit `paths` arrays and improved reminders.

### Architecture: C# layering

```
csharp-foundation  (no agent, no stack — pure skill library)
        ↑
aspnet-core-plugin (priority 100)
backend + database
```

Mirrors `java-foundation → {java-plugin, spring-boot-plugin}` and `php-foundation → {laravel-plugin, symfony-plugin}`. Future .NET plugins (Blazor, gRPC, plain console) can reference `csharp-foundation` skills without depending on `aspnet-core-plugin`.

### Installation

```
/plugin install aspnet-core-plugin@sdlc-marketplace   # pulls sdlc + csharp-foundation automatically
/plugin install csharp-foundation@sdlc-marketplace    # standalone, for C# skills without a stack provider
```

---

## [0.4.0] — marketplace v0.4.0

### Added — PHP shared foundation + Symfony stack (2 new plugins)

- **`php-foundation` v0.0.1** — Pure shared skill library for any PHP project. No agent, no stack profile. Mirrors `java-foundation` / `js-foundation`. Provides:
  - `php-conventions` — Modern PHP 8.x idioms: `declare(strict_types=1)`, constructor property promotion, `readonly` properties, backed enums, `match`, typed properties, named arguments, first-class callable syntax, nullsafe operator, PSR-12.
  - `composer-tooling` — `composer.json` vs `composer.lock` contract, version constraints (`^`/`~`), `require` vs `require-dev`, PSR-4 autoloading + `dump-autoload`, scripts, `config.platform.php`.
  - `php-testing` — PHPUnit + Pest structure (AAA), data providers / datasets, test doubles (stub vs mock discipline), fixtures, coverage targets.
  - `security-patterns.yaml` — PHP security rules (dynamic code execution, shell execution, unsafe deserialization, hardcoded secrets, SQL concatenation, path traversal, debug output) for `security-guidance`.

- **`symfony-plugin` v0.0.1** — Symfony backend + database stack provider (priority=100). Detects `symfony/framework-bundle` in `composer.json`. Adds two agents plus two convention skills:
  - `symfony-architect` (Sonnet/medium) — attribute routing, controllers-as-services + constructor injection, Form types, Validation constraints, Voters, Serializer/DTO contract, Messenger, Twig rendering. Designs the API/serialization contract for SPA frontend plugins.
  - `doctrine-specialist` (Sonnet/low) — finalizes Doctrine entity mappings, generates migrations via `doctrine:migrations:diff`, reviews the SQL, writes fixtures, runs `migrate` + `doctrine:schema:validate`. Runs in the extra `database` phase.
  - `symfony-conventions` — attribute routing, DI/autowiring, Form types, validation, Voters, Serializer, Messenger.
  - `doctrine-patterns` — entity mapping as source of truth, repositories, parameterized DQL, N+1/fetch joins, relations, batch processing, generated migrations.
  - Phase-prompt injection: Symfony-specific dev (layers, Voters, validation, lint:container), QA (`WebTestCase`/`KernelTestCase`, dama/doctrine-test-bundle), and security (Voters/access_control, CSRF, secrets, DQL injection, Serializer over-exposure) guidance.
  - PHP-CS-Fixer Stop hook + post-pipeline checks (`php-cs-fixer`, `phpunit`, `lint:container`, `debug:router`, `doctrine:schema:validate`).

### Changed

- **`laravel-plugin` v0.0.2 → v0.0.3** — now depends on `php-foundation`; `stack.md` applies `php-foundation:php-conventions`, `php-foundation:composer-tooling`, `php-foundation:php-testing` alongside its own skills; trimmed the duplicated general PHP "Code style" section from `laravel-conventions` (now lives in `php-foundation:php-conventions`).

### Architecture: PHP layering

```
php-foundation  (no agent, no stack — pure skill library)
     ↑                    ↑
laravel-plugin       symfony-plugin
(priority 100)       (priority 100)
backend + database   backend + database
```

Mirrors `java-foundation → {java-plugin, spring-boot-plugin}`. Laravel and Symfony markers in `composer.json` are mutually exclusive, so the two profiles never collide.

### Installation

```
/plugin install symfony-plugin@sdlc-marketplace   # pulls sdlc + php-foundation automatically
/plugin install laravel-plugin@sdlc-marketplace   # now also pulls php-foundation
```

---

## [0.3.0] — marketplace v0.3.0

### Added — Java stack (3 new plugins)

- **`java-foundation` v0.0.1** — Pure shared skill library for any JVM project. No agent, no stack profile. Provides:
  - `java-conventions` — Modern Java (17+) idioms: records, sealed types, pattern matching, `Optional`, streams, immutability, null discipline, `var`, package layout.
  - `build-tooling` — Maven vs Gradle detection, wrapper (`./mvnw` / `./gradlew`), BOM dependency management, version properties, multi-module projects.
  - `jvm-testing` — JUnit 5 (AAA structure, parameterised tests), Mockito (constructor injection, no `@InjectMocks`), AssertJ fluent assertions, Testcontainers integration tests, JaCoCo coverage.

- **`java-plugin` v0.0.1** — Plain Java backend stack provider (priority=100). Detects any Maven or Gradle project by build-file presence (`pom.xml` / `build.gradle` / `build.gradle.kts`). Adds `java-architect` agent (Sonnet/medium). Suitable for libraries, CLI tools, micro-services without a recognized web framework. Acts as a mid-tier fallback — `spring-boot-plugin` (priority 150) wins on Spring projects.

- **`spring-boot-plugin` v0.0.1** — Spring Boot backend stack provider (priority=150). Detects `spring-boot` marker in any build file. Adds `spring-boot-architect` agent (Sonnet/medium) plus two convention skills:
  - `spring-conventions` — REST controllers (`@RestController`, `@RequestMapping`), service layer (`@Service`, `@Transactional`), constructor injection, `@ConfigurationProperties` records, Bean Validation, `ProblemDetail` error handling (RFC 9457).
  - `spring-data-jpa` — JPA entities, `JpaRepository`, JPQL `@Query`, N+1 avoidance (`@EntityGraph` / `JOIN FETCH`), Flyway/Liquibase migration stubs, optimistic locking, pagination.
  - Phase-prompt injection: Spring-specific dev (layers, annotations, migrations), QA (`@SpringBootTest`, `@WebMvcTest`, `@DataJpaTest` slices, MockMvc), and security (Spring Security `HttpSecurity`, CSRF, `@PreAuthorize`, Actuator exposure, SpEL injection) guidance.

### Architecture: three-tier Java layering

```
java-foundation  (no agent, no stack — pure skill library)
     ↑
java-plugin (priority 100, backend aspect — any Maven/Gradle)
     ↑
spring-boot-plugin (priority 150, backend aspect — Spring Boot)
```

Mirrors the `js-foundation → nodejs-plugin → nestjs-plugin` layering. `java-foundation` skills are reused by both framework-level plugins.

### Priority resolution for Java projects

| Project type | Active profile | Backend agent |
|---|---|---|
| Spring Boot (`spring-boot` in build file) | `spring-boot` (150) | `spring-boot-architect` |
| Plain Java (Maven/Gradle, no Spring) | `java` (100) | `java-architect` |
| No build file | `vanilla` (0) | `developer` (fallback) |

### Installation

```
/plugin install spring-boot-plugin@sdlc-marketplace   # pulls sdlc + java-foundation automatically
/plugin install java-plugin@sdlc-marketplace          # for plain Java projects
```

---

## [0.1.4] — marketplace v0.1.4 / sdlc v0.1.2

### Changed

- **All agents — execution-first restructure**: renamed `## Your job` → `## Steps` across all 13 agents (matches official Claude Code agent convention). Extracted `## Hard rules` and `## Code quality bar` into a unified `## Constraints` block placed _before_ `## Steps` so the agent reads its limits before acting. For `laravel-architect`, `## What you do NOT do` also merged into `## Constraints`.

---

## [0.1.3] — marketplace v0.1.3 / sdlc v0.1.1

### Changed

- **All agents (12 files)**: removed `## Why [model]` sections — human rationale for model choice is already encoded in frontmatter `model` + `effort` fields and adds noise without execution value.

---

## [0.1.2] — marketplace v0.1.2 / sdlc v0.1.0

### Changed

- **`sdlc` plugin v0.0.2 → v0.1.0**: restructured `business-analyst.md` agent prompt for Claude execution — removed human-facing `## Why Opus` and role-play preamble, renamed `## Your job` → `## Steps` (matches official Claude Code agent convention), moved `## Constraints` block before steps, moved `## Output` schema before steps so the agent knows the target before reading the process.

---

## [0.1.1] — marketplace v0.1.1

### Fixed

- **`marketplace.json` source types**: replaced unsupported shorthand strings `"obra/superpowers"` and `"anthropics/claude-plugins-official"` with proper source objects — `{ "source": "url", "url": "https://github.com/obra/superpowers.git" }` and `{ "source": "git-subdir", "url": "https://github.com/anthropics/claude-plugins-official.git", "path": "plugins/security-guidance" }`. Fixes _"This plugin uses a source type your Claude Code version does not support"_ error on install.

---

## [0.1.0] — marketplace v0.1.0

### Added — marketplace port and cost optimization

- **8 нових стек-плагінів** (ported з Rolique/claude-plugins v0.1.1): `js-foundation`, `nodejs-plugin`, `nestjs-plugin`, `nextjs-plugin`, `react-plugin`, `vue-plugin`, `angular-plugin`, `react-native-plugin`. Маркетплейс з 2 → 10 локальних плагінів.

- **`schemas/`** — JSON-схеми для валідації `plugin.json` і frontmatter `stack.md` (`plugin.schema.json`, `stack.schema.json`).

- **`/sdlc:batch`** slash-команда — паралельне виконання SDLC-пайплайну для кількох задач, ізольовані worktree, detect конфліктів файлів.

- **`/sdlc:security-init`** slash-команда — матеріалізація стек-специфічного `security-patterns.yaml` і `claude-security-guidance.md` у поточний проєкт для `security-guidance` плагіна.

- **`superpowers` і `security-guidance`** як зовнішні залежності в `marketplace.json` (записи для external plugins від `obra/superpowers` і `anthropics/claude-plugins-official`).

- **`effort` поле** в frontmatter всіх 14 агентів — перший usage поля, яке перекриває session-рівень reasoning-бюджету.

### Changed — cost-optimization re-tier

- **`marketplace.json` v0.0.2 → v0.1.0**: додано 12 записів (2 зовнішніх + 8 нових плагінів), оновлено descriptions з model/effort тарифами.

- **Re-tier усіх агентів** — всі `model` поля перейшли на аліаси (більше ніяких застарілих пінувань `claude-opus-4-7`). Додано `effort` до кожного агента:
  - `business-analyst`, `security-analyst`: `opus` + `effort: high` (помилки тут каскадно дорогі, малий об'єм токенів)
  - усі 9 архітекторів + `developer` + `qa-engineer`: `sonnet` + `effort: medium` (виконавча фаза, специфікація задає обмеження)
  - `artisan-specialist`: `sonnet` + `effort: low` (механічна DB-робота: типи/індекси/factories)
  - `document-writer`: `haiku` + `effort: low` (структурований вивід із відомих фактів)

- **Rolique all-Opus mandate скасовано**: всі 7 Rolique-архітекторів знижено з `opus` → `sonnet` + `effort: medium`. Обґрунтування в тілі кожного агента оновлено.

- **Злиття `pipeline-orchestrator/SKILL.md`** (807 рядків → 955 рядків): інтегровано з Rolique-версії — multi-plugin runtime-dependencies aggregation, preflight cache fast-path, two-pass development approval gate, `--force-ba`/`--no-skip-rules` flag reservations; збережено наявні cost/skip-rule секції і prompt-caching discipline.

### Notes

- `temperature` не налаштовується per-subagent у Claude Code — в плані опускаємо. Reasoning-бюджет керується виключно полем `effort`.

- Аліаси (`opus`/`sonnet`/`haiku`) завжди беруть актуальну версію тіру; ручне оновлення при виходах нових моделей не потрібне.

---

## [Pre-release]

### Added

- Initial repository scaffold (`marketplace.json`, LICENSE, README).

- `sdlc@0.0.1` skeleton with vanilla stack profile.

- `sdlc` Phase 1 contents: `pipeline-orchestrator` skill, `/sdlc:start` command, 5 cost-tiered default agents (business-analyst, developer, qa-engineer, security-analyst, document-writer).

- `laravel-plugin@0.0.1` first stack provider: `stack.md` profile, `laravel-architect` and `artisan-specialist` agents, `laravel-conventions` and `eloquent-patterns` skills, `.mcp.json` for laravel-boost, Pint Stop-hook.

### Added — post-Phase 2 patches

- `docs/decisions/ADR-014-aspect-tagged-profiles.md` — architectural decision for multi-aspect project composition (Laravel + Inertia/Vue/React/Livewire). Plans aspect-tagged profile resolution + phase fan-out for Phase 4-5. Cross-referenced from `ARCHITECTURE.md` §10.5 and `PROJECT_INTEGRATION.md` §10.5.

- `<project>/.claude/sdlc.local.yaml` first-class override mechanism for `post_pipeline_checks`, `phase_command_overrides`, `extra_phase_prompts`, `skip_phases`, `convention_skills_extra` (was originally scoped to Phase 3, pulled forward). Implemented as Step 1b in `pipeline-orchestrator/SKILL.md`.

- `PROJECT_INTEGRATION.md` knowledge base: how plugins interact with project-local config (CLAUDE.md, `.claude/skills/`, `.mcp.json`, `sdlc.local.yaml`). Documents auto-respected channels, current limitations, recommended scenarios (Herd vs Docker, monorepo, PHPUnit vs Pest, external SAST).

- `/sdlc:list-stacks` slash command for verifying stack profile detection (Glob installed plugins, parse frontmatter, evaluate detect rules against current project).

- MUST-print announcement protocol in orchestrator (verbatim Step 0b stack detection, Step 3b phase boundaries, Step 5 final summary). Replaces softer "Announce" instructions that were collapsing silently.

### Added — Phase 3 cost optimizations and dependency preflight

- **Step 0a real implementation** in `pipeline-orchestrator/SKILL.md`: reads `runtime-dependencies.json`, enumerates skills via `mcp__skills__list_skills` with FS fallback, enforces `block` / `warn` / `graceful-degrade` policies. Replaces the v0.0.1 stub. Persists per-dependency status in `CONTEXT.deps_preflight` for telemetry.

- **Headless mode** (`SDLC_NONINTERACTIVE=true`): `block` emits machine-readable JSON to stdout and exits 1; `warn` writes one-line to stderr; `graceful-degrade` stays silent. Documented in `commands/start.md`.

- **Three additional skip-rules** in Step 0c: `whitespace-only` (skip BA + QA), `config-only` (skip QA), `lightweight-no-db` (skip Security with inline secret-leak check injected into Dev). Original `typo-fix` rule retained. Each fired rule logs `{rule, phase_skipped, reason}` to `CONTEXT.skip_rules_applied[]`.

- **Per-phase telemetry instrumentation** (Step 3d-1 / 3d-2 / Step 5 schema): captures `input_tokens`, `output_tokens`, `cached_input_tokens`, `cost_usd` per phase from the Agent tool's usage envelope (with char/4 fallback when absent); adds `compact_summary_chars` + `compact_handoff_violation` flag (warns when compact summary exceeds 3K chars); adds `qa_iterations_used` + `qa_status` parsed from QA agent output; adds top-level aggregates `total_input_tokens`, `total_output_tokens`, `total_cached_input_tokens`, `cache_hit_ratio`; adds `headless_mode` flag.

- **Inline per-model pricing table** in Step 3d-1 (opus / sonnet / haiku, separate input / cached / output rates) so cost computation is transparent and auditable.

- `/sdlc:doctor` slash command (read-only). Runs the same Step 0a preflight as `/sdlc:start` but never aborts; reports stack profile detection and a parsed summary block from `docs/cost-baseline.md` if present. Supports `--json` for CI consumption.

- `docs/cost-baseline.md` schema and aggregation methodology (machine-readable `summary` JSON block consumed by `/sdlc:doctor`; `jq` aggregation procedure for ingesting `_telemetry.json` files; done-criteria for v1.0 from IMPLEMENTATION_PLAN §5.3). Real numbers fill in once ≥20 production runs are executed against a Laravel testbed.

### Changed — Phase 3

- **Prompt-caching discipline**: Step 3b-1 prompt template restructured into a STABLE PREFIX (cacheable across runs) + PER-CALL CONTEXT trailer (task_slug, aspect, narrative_language, availability_flags, phase_command_overrides). Stable prefix is now byte-identical for repeated phase invocations on the same agent. The standalone `Output language:` injection block is removed; the language contract lives in the stable prefix and the per-call value travels in the CONTEXT trailer's `narrative_language` key.

- New "Prompt-caching discipline" subsection under "Hard rules for the orchestrator" in `pipeline-orchestrator/SKILL.md`: forbids per-call values, timestamps, UUIDs, or raw `$ARGUMENTS` in the stable prefix; mandates deterministic ordering of `convention_skills` and multi-plugin `phase_prompts_injection` concat.

### Changed — post-Phase 2 patches

- Renamed plugin `core-sdlc-plugin` → `sdlc`. Slash command went from `/core-sdlc-plugin:sdlc-start` to `/sdlc:start`. Cleaner UX in plugin namespace.

- `plugin.json` `dependencies` switched from object form to native array (`["sdlc"]`) per Claude Code schema; runtime plugin checks moved to `runtime-dependencies.json`.

- License switched from MIT to GPL-3.0.

### Notes

- v0.0.1 series is pre-release scaffolding. v1.0.0 will be tagged after Phase 4 (Polish) per `IMPLEMENTATION_PLAN.md`.

- External plugin dependencies (e.g. `superpowers`) are declared in `runtime-dependencies.json` but the orchestrator preflight (Step 0a) is stubbed in v0.0.1; full implementation in Phase 3.
