# Changelog

All notable changes to the SDLC marketplace are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/), versioning is [SemVer](https://semver.org/) per plugin.

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
