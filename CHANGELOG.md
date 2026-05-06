# Changelog

All notable changes to the SDLC marketplace are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/), versioning is [SemVer](https://semver.org/) per plugin.

## [Unreleased]

### Added
- Initial repository scaffold (`marketplace.json`, LICENSE, README).
- `sdlc@0.0.1` skeleton with vanilla stack profile.
- `sdlc` Phase 1 contents: `pipeline-orchestrator` skill, `/sdlc:start` command, 5 cost-tiered default agents (business-analyst, developer, qa-engineer, security-analyst, document-writer).
- `laravel-plugin@0.0.1` first stack provider: `stack.md` profile, `laravel-architect` and `artisan-specialist` agents, `laravel-conventions` and `eloquent-patterns` skills, `.mcp.json` for laravel-boost, Pint Stop-hook.

### Added (post-Phase 2 patches)
- `docs/decisions/ADR-014-aspect-tagged-profiles.md` — architectural decision for multi-aspect project composition (Laravel + Inertia/Vue/React/Livewire). Plans aspect-tagged profile resolution + phase fan-out for Phase 4-5. Cross-referenced from `ARCHITECTURE.md` §10.5 and `PROJECT_INTEGRATION.md` §10.5.
- `<project>/.claude/sdlc.local.yaml` first-class override mechanism for `post_pipeline_checks`, `phase_command_overrides`, `extra_phase_prompts`, `skip_phases`, `convention_skills_extra` (was originally scoped to Phase 3, pulled forward). Implemented as Step 1b in `pipeline-orchestrator/SKILL.md`.
- `PROJECT_INTEGRATION.md` knowledge base: how plugins interact with project-local config (CLAUDE.md, `.claude/skills/`, `.mcp.json`, `sdlc.local.yaml`). Documents auto-respected channels, current limitations, recommended scenarios (Herd vs Docker, monorepo, PHPUnit vs Pest, external SAST).
- `/sdlc:list-stacks` slash command for verifying stack profile detection (Glob installed plugins, parse frontmatter, evaluate detect rules against current project).
- MUST-print announcement protocol in orchestrator (verbatim Step 0b stack detection, Step 3b phase boundaries, Step 5 final summary). Replaces softer "Announce" instructions that were collapsing silently.

### Added (Phase 3 — cost optimizations + dependency preflight)
- **Step 0a real implementation** in `pipeline-orchestrator/SKILL.md`: reads `runtime-dependencies.json`, enumerates skills via `mcp__skills__list_skills` with FS fallback, enforces `block` / `warn` / `graceful-degrade` policies. Replaces the v0.0.1 stub. Persists per-dependency status in `CONTEXT.deps_preflight` for telemetry.
- **Headless mode** (`SDLC_NONINTERACTIVE=true`): `block` emits machine-readable JSON to stdout and exits 1; `warn` writes one-line to stderr; `graceful-degrade` stays silent. Documented in `commands/start.md`.
- **Three additional skip-rules** in Step 0c: `whitespace-only` (skip BA + QA), `config-only` (skip QA), `lightweight-no-db` (skip Security with inline secret-leak check injected into Dev). Original `typo-fix` rule retained. Each fired rule logs `{rule, phase_skipped, reason}` to `CONTEXT.skip_rules_applied[]`.
- **Per-phase telemetry instrumentation** (Step 3d-1 / 3d-2 / Step 5 schema): captures `input_tokens`, `output_tokens`, `cached_input_tokens`, `cost_usd` per phase from the Agent tool's usage envelope (with char/4 fallback when absent); adds `compact_summary_chars` + `compact_handoff_violation` flag (warns when compact summary exceeds 3K chars); adds `qa_iterations_used` + `qa_status` parsed from QA agent output; adds top-level aggregates `total_input_tokens`, `total_output_tokens`, `total_cached_input_tokens`, `cache_hit_ratio`; adds `headless_mode` flag.
- **Inline per-model pricing table** in Step 3d-1 (opus / sonnet / haiku, separate input / cached / output rates) so cost computation is transparent and auditable.
- `/sdlc:doctor` slash command (read-only). Runs the same Step 0a preflight as `/sdlc:start` but never aborts; reports stack profile detection and a parsed summary block from `docs/cost-baseline.md` if present. Supports `--json` for CI consumption.
- `docs/cost-baseline.md` schema and aggregation methodology (machine-readable `summary` JSON block consumed by `/sdlc:doctor`; `jq` aggregation procedure for ingesting `_telemetry.json` files; done-criteria for v1.0 from IMPLEMENTATION_PLAN §5.3). Real numbers fill in once ≥20 production runs are executed against a Laravel testbed.

### Changed (Phase 3)
- **Prompt-caching discipline**: Step 3b-1 prompt template restructured into a STABLE PREFIX (cacheable across runs) + PER-CALL CONTEXT trailer (task_slug, aspect, narrative_language, availability_flags, phase_command_overrides). Stable prefix is now byte-identical for repeated phase invocations on the same agent. The standalone `Output language:` injection block is removed; the language contract lives in the stable prefix and the per-call value travels in the CONTEXT trailer's `narrative_language` key.
- New "Prompt-caching discipline" subsection under "Hard rules for the orchestrator" in `pipeline-orchestrator/SKILL.md`: forbids per-call values, timestamps, UUIDs, or raw `$ARGUMENTS` in the stable prefix; mandates deterministic ordering of `convention_skills` and multi-plugin `phase_prompts_injection` concat.

### Changed (post-Phase 2 patches)
- Renamed plugin `core-sdlc-plugin` → `sdlc`. Slash command went from `/core-sdlc-plugin:sdlc-start` to `/sdlc:start`. Cleaner UX in plugin namespace.
- `plugin.json` `dependencies` switched from object form to native array (`["sdlc"]`) per Claude Code schema; runtime plugin checks moved to `runtime-dependencies.json`.
- License switched from MIT to GPL-3.0.

### Notes
- v0.0.1 series is pre-release scaffolding. v1.0.0 will be tagged after Phase 4 (Polish) per `IMPLEMENTATION_PLAN.md`.
- External plugin dependencies (e.g. `superpowers`) are declared in `runtime-dependencies.json` but the orchestrator preflight (Step 0a) is stubbed in v0.0.1; full implementation in Phase 3.
