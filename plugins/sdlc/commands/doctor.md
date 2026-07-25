---
description: Diagnose SDLC pipeline health — external plugin dependencies, runtime preflight status, model-routing overrides, and cost baseline. Read-only apart from seeding a cost-baseline scaffold when absent.
argument-hint: "[--json]"
---

# /sdlc:doctor

Snapshot of the pipeline's runtime environment. Reuses the same Step 0a preflight code-path that `/sdlc:start` runs on every invocation, but in a diagnostic mode that never aborts.

## What this command does

1. **Locate the runtime dependencies file.** Try these paths in order, take the first that exists:
   - `~/.claude/plugins/cache/sdlc/runtime-dependencies.json`
   - `<repo>/plugins/sdlc/runtime-dependencies.json` (development checkout)

   If neither exists, print `🔌 Dependency preflight: no runtime-dependencies.json found.` and skip step 2.

2. **Run the same preflight algorithm as Step 0a in `pipeline-orchestrator/SKILL.md`** (Step 0a-2 through 0a-3 — enumerate available skills via `mcp__skills__list_skills` with FS fallback to `~/.claude/plugins/cache/{plugin}/skills/{skill}/SKILL.md`, then compute per-dependency status). DO NOT enforce policy in `/sdlc:doctor` — `block` does NOT exit here. Just collect status.

3. **Locate active stack profiles.** Reuse Step 0b logic from the orchestrator: `Glob ~/.claude/plugins/cache/**/stack.md`, parse frontmatter, evaluate detect rules against the current project. Identify the primary profile that would be selected.

4. **Read cost baseline.** Try `<repo>/docs/cost-baseline.md`. If it has a fenced JSON block tagged `summary` (e.g. ```` ```json summary ````) parse and extract `avg_cost_per_medium_run_usd`, `p90_cost_per_medium_run_usd`, `cache_hit_ratio`, `runs_aggregated`.

   If the file is absent, seed it by copying the template shipped with this plugin — `${CLAUDE_PLUGIN_ROOT}/templates/cost-baseline.md` — to `<repo>/docs/cost-baseline.md`, then report the "not yet baselined" state it contains. This is the one write `/sdlc:doctor` performs; it creates a scaffold and never overwrites an existing file. If the template cannot be located, fall back to reporting "no baseline file and no template found" and continue.

5. **Check model-routing integrity.** The pipeline's two enforcement layers (orchestrator Step 3b-3 and the `enforce-agent-model.sh` PreToolUse hook) are not the final word on which model a subagent runs. Claude Code resolves it in the order `CLAUDE_CODE_SUBAGENT_MODEL` → per-invocation parameter → frontmatter, so the environment variable silently overrides both. Report:

   - `CLAUDE_CODE_SUBAGENT_MODEL` — read from the environment. If set to anything other than `inherit`, this is a **routing override**: every phase runs on that model regardless of agent frontmatter, and all cost estimates in this repo become meaningless. Report the value and flag it.
   - **Declared tiers per active agent.** For each agent named by the active stack profile, read `model:` (and `model_plan:` where present) from its `.md` frontmatter and list them, so the operator sees the intended routing next to any override.

   This step reads the environment and agent files only — it changes nothing.

6. **Render output.** Default = human-readable table. With `--json` flag, emit a single valid JSON object to stdout and exit.

## Human output format

```
🩺 SDLC Doctor

Dependencies (from runtime-dependencies.json):
  superpowers >=1.0.0 [policy=warn]
    status: ✅ available
    skills: using-superpowers, verification-before-completion

  acme-internal >=2.0.0 [policy=block]
    status: ❌ missing
    missing skills: code-style, internal-api-style
    install:
      /plugin marketplace add acme/internal-tools
      /plugin install acme-internal@acme-internal-tools

Stack profiles:
  🎯 active: laravel (priority=100, from laravel-plugin/stack.md)
  also installed: vanilla (priority=0)

Cost baseline (docs/cost-baseline.md, last updated 2026-05-04, 22 runs):
  avg medium-run: $1.62
  p90 medium-run: $2.31
  cache hit ratio: 0.61
  note: subagent phases only — orchestrator overhead is not metered

Model routing:
  ⚠️  CLAUDE_CODE_SUBAGENT_MODEL=opus — OVERRIDES all model enforcement.
      Every phase will run on opus regardless of agent frontmatter.
      Cost estimates in README/telemetry do not apply while this is set.
  declared tiers for active profile (laravel):
    business-analyst    opus
    laravel-architect   opus (plan) / sonnet (implement)
    artisan-specialist  sonnet
    qa-engineer         sonnet
    security-analyst    opus
    document-writer     haiku

Heads-up:
  ❌ 1 blocking dependency missing — /sdlc:start would abort.
     Run the install commands above, then retry.
```

When `CLAUDE_CODE_SUBAGENT_MODEL` is unset (or `inherit`), print `✅ no routing override` in place of the warning.

If a section is absent (no baseline file, no missing deps, etc.) say so explicitly with one line — never silently omit a section.

## JSON output format (`--json`)

```json
{
  "deps_preflight": {
    "superpowers": {
      "status": "available",
      "policy": "warn",
      "missing_skills": []
    },
    "acme-internal": {
      "status": "missing",
      "policy": "block",
      "missing_skills": ["code-style", "internal-api-style"],
      "install_command": [
        "/plugin marketplace add acme/internal-tools",
        "/plugin install acme-internal@acme-internal-tools"
      ]
    }
  },
  "stack": {
    "active_profile": "laravel",
    "primary_priority": 100,
    "all_installed": ["vanilla", "laravel"]
  },
  "cost_baseline": {
    "available": true,
    "runs_aggregated": 22,
    "avg_cost_per_medium_run_usd": 1.62,
    "p90_cost_per_medium_run_usd": 2.31,
    "cache_hit_ratio": 0.61,
    "cost_scope": "subagent_phases_only",
    "last_updated": "2026-05-04"
  },
  "model_routing": {
    "subagent_model_override": "opus",
    "override_active": true,
    "declared_tiers": {
      "business-analyst": { "model": "opus" },
      "laravel-architect": { "model": "sonnet", "model_plan": "opus" },
      "qa-engineer": { "model": "sonnet" },
      "security-analyst": { "model": "opus" },
      "document-writer": { "model": "haiku" }
    }
  },
  "would_abort_pipeline": true
}
```

`would_abort_pipeline` is `true` iff any dependency with `policy=block` is missing. `model_routing.override_active` is `true` iff `CLAUDE_CODE_SUBAGENT_MODEL` is set to something other than `inherit`; `subagent_model_override` is `null` when unset.

## Hard rules

- **Effectively read-only.** Do NOT install plugins, run pipelines, or modify any existing file. The single exception is seeding `docs/cost-baseline.md` from the shipped template when that file does not exist (step 4) — a create-if-absent scaffold, never an overwrite.
- **Do not enforce policy.** A missing `block` dep here is just reported, not actioned.
- **Reuse, don't reimplement.** The dependency-status algorithm is described in `pipeline-orchestrator/SKILL.md` Step 0a-2 / 0a-3. If those steps change, this command's behavior must follow — this command is documentation that delegates to those steps, not a parallel implementation.
- **Exit code semantics with `--json`:** exit 0 normally; exit 1 only if the runtime-dependencies.json file itself is malformed JSON (parse error). Missing-but-blocking deps still exit 0 — report them in the JSON and let the caller decide.

## When to use

- After installing or updating a stack plugin — verify external dep wiring still resolves.
- Before kicking off a long pipeline run — confirm `/sdlc:start` won't abort at Step 0a.
- In CI / automation — `/sdlc:doctor --json` gives a machine-checkable health report.
- When a cost regression is suspected — compare current `cost_baseline` against historical values.
