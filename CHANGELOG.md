# Changelog

All notable changes to the SDLC marketplace are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/), versioning is [SemVer](https://semver.org/) per plugin.

## [Unreleased]

### Added
- Initial repository scaffold (`marketplace.json`, LICENSE, README).
- `core-sdlc-plugin@0.0.1` skeleton with vanilla stack profile.
- `core-sdlc-plugin` Phase 1 contents: `pipeline-orchestrator` skill, `/sdlc:sdlc-start` command, 5 cost-tiered default agents (business-analyst, developer, qa-engineer, security-analyst, document-writer).
- `laravel-plugin@0.0.1` first stack provider: `stack.md` profile, `laravel-architect` and `artisan-specialist` agents, `laravel-conventions` and `eloquent-patterns` skills, `.mcp.json` for laravel-boost, Pint Stop-hook.

### Notes
- v0.0.1 series is pre-release scaffolding. v1.0.0 will be tagged after Phase 4 (Polish) per `IMPLEMENTATION_PLAN.md`.
- External plugin dependencies (e.g. `superpowers`) are declared in plugin manifests but the runtime preflight (Step 0a in pipeline-orchestrator) is stubbed in v0.0.1; full implementation in Phase 3.
