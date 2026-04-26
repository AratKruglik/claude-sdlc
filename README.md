# SDLC Marketplace for Claude Code

Multi-stack AI-assisted SDLC pipelines built on the **Stack Provider Pattern**: a single core orchestrator runs the pipeline, framework plugins register themselves via declarative `stack.md` profiles. No core overrides, no slot registries, no copy-paste between stacks.

> Architecture details: [`ARCHITECTURE.md`](./ARCHITECTURE.md)
> Implementation plan: [`IMPLEMENTATION_PLAN.md`](./IMPLEMENTATION_PLAN.md)
> External plugin dependencies (superpowers, etc.): [`DEPENDENCIES.md`](./DEPENDENCIES.md)

## Quickstart

```bash
# 1. Add this marketplace
/plugin marketplace add AratKruglik/claude-sdlc

# 2. Install a stack plugin (core comes as a dependency)
/plugin install laravel-plugin@sdlc-marketplace

# 3. Verify
/sdlc:list-stacks
# 🎯 vanilla   priority=0   (always matches)
# 🎯 laravel   priority=100 (matches: composer.json + laravel/framework)

# 4. Run the pipeline
/sdlc:sdlc-start "Add subscription billing with Stripe"
# → Detected stack: laravel
# → Phase 1/6: business_analysis (Opus)
# → Phase 2/6: development → laravel-architect (Sonnet)
# → Phase 3/6: database → artisan-specialist (Sonnet)
# → Phase 4/6: qa (Sonnet, max 3 fix attempts)
# → Phase 5/6: security (Opus)
# → Phase 6/6: documentation (Haiku)
# → Post-pipeline: pint --test, php artisan test, route:list
# → ✅ Completed in ~3 min, ~$1.40 spent, PR #142
```

## What you get

| Property | How it works |
|---|---|
| **Core never changes** | `pipeline-orchestrator` lives only in core. Framework plugins never edit it. |
| **DRY** | Pipeline logic written once. A bugfix in core lands for every framework. |
| **Composition without override** | Laravel uses core's BA / QA / Security / Docs unchanged; substitutes only the developer. |
| **Auto-detection** | Core scans `stack.md` files in installed plugins, evaluates `detect` rules, picks highest priority. Override with `--stack=name`. |
| **Cost-conscious by default** | Smart model tiering (Opus on BA + Sec, Sonnet on Dev + QA, Haiku on Docs), iteration caps, compact handoffs, skip-rules. Target: ~$1.40 per medium feature. |
| **Extensible** | New framework = new plugin with its own `stack.md` + specialized agents. No core changes needed. |

## Repository layout

```
sdlc-marketplace/
├── .claude-plugin/
│   └── marketplace.json
├── plugins/
│   ├── core-sdlc-plugin/          ← orchestrator + 5 default agents
│   │   ├── stack.md               ← vanilla profile (priority: 0)
│   │   ├── commands/
│   │   ├── skills/pipeline-orchestrator/
│   │   └── agents/
│   └── laravel-plugin/            ← first stack provider
│       ├── stack.md               ← Laravel profile (priority: 100)
│       ├── agents/
│       ├── skills/
│       ├── .mcp.json
│       └── hooks/
├── ARCHITECTURE.md
├── IMPLEMENTATION_PLAN.md
├── DEPENDENCIES.md
└── README.md (this file)
```

## Status

| Plugin | Version | Status |
|---|---|---|
| `core-sdlc-plugin` | 0.0.1 | Pre-release. Phase 1 (orchestrator + agents) complete. |
| `laravel-plugin` | 0.0.1 | Pre-release. Phase 2 (first stack provider) complete. |

v1.0 ships after Phase 4 (Polish: docs + `/sdlc:doctor` + GitHub Actions lint). See [`IMPLEMENTATION_PLAN.md`](./IMPLEMENTATION_PLAN.md).

## Adding your own framework

```bash
plugins/your-framework-plugin/
├── .claude-plugin/plugin.json     # dependencies: core-sdlc-plugin
├── stack.md                        # detect rules + agents_per_phase + injections
├── agents/your-architect.md        # replaces vanilla developer
└── skills/your-conventions/SKILL.md
```

Full guide: `docs/authoring-stack-plugin.md` (ships in Phase 4).

## Requirements

- Claude Code (latest)
- Recommended: API Tier 2+ or Claude Max — full pipeline runs ~445K input tokens per medium feature; Pro plan rate limits will throttle you.
- Optional: [`obra/superpowers`](https://github.com/obra/superpowers) — declared as `policy: warn` dependency. Pipeline runs without it in degraded mode.

## License

MIT — see [`LICENSE`](./LICENSE).
