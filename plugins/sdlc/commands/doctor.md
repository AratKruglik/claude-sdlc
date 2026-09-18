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

3. **Locate active stack profiles.** Doctor always computes this **fresh** — same discipline as its git-flow check below ("a doctor that echoes a stale cache cannot diagnose a stale cache"): run `scripts/detect-stack.py --repo .` (resolve the path the same three-way way as every other script: `${CLAUDE_PLUGIN_ROOT}/scripts/detect-stack.py`, then the installed cache copy, then `<repo>/plugins/sdlc/scripts/detect-stack.py` in a development checkout). This is the exact same algorithm `pipeline-orchestrator/SKILL.md` Step 0b runs — reusing the script instead of re-deriving the Glob+Read+parse sequence by hand keeps this command from silently drifting out of sync with it.

   If `python3` is unavailable, fall back to the inline algorithm (Glob `~/.claude/plugins/cache/**/stack.md`, parse frontmatter, evaluate detect rules) — the same fallback Step 0b's full scan uses.

   Separately, check whether `~/.claude/.sdlc-stack-cache/{sha1(realpath(cwd))[:16]}.json` exists (the file the `SessionStart` hook writes) and report its age. If it disagrees with the fresh detection above (different `primary_profile.stack`, or different `aspect_ties`), flag it exactly like the git-flow cache-disagreement check — that is a repo whose installed-plugin set or detectable files changed since the hook last ran. Doctor reports the disagreement; it does not decide which one `/sdlc:start` will trust (Step 0b's own trust rules do that).

4. **Read cost baseline.** Try `<repo>/docs/cost-baseline.md`. If it has a fenced JSON block tagged `summary` (e.g. ```` ```json summary ````) parse and extract `avg_cost_per_medium_run_usd`, `p90_cost_per_medium_run_usd`, `cache_hit_ratio`, `runs_aggregated`.

   If the file is absent, seed it by copying the template shipped with this plugin — `${CLAUDE_PLUGIN_ROOT}/templates/cost-baseline.md` — to `<repo>/docs/cost-baseline.md`, then report the "not yet baselined" state it contains. This is the one write `/sdlc:doctor` performs; it creates a scaffold and never overwrites an existing file. If the template cannot be located, fall back to reporting "no baseline file and no template found" and continue.

5. **Check model-routing integrity.** The pipeline's two enforcement layers (orchestrator Step 3b-3 and the `enforce-agent-model.sh` PreToolUse hook) are not the final word on which model a subagent runs. Claude Code resolves it in the order `CLAUDE_CODE_SUBAGENT_MODEL` → per-invocation parameter → frontmatter, so the environment variable silently overrides both. Report:

   - `CLAUDE_CODE_SUBAGENT_MODEL` — read from the environment. If set to anything other than `inherit`, this is a **routing override**: every phase runs on that model regardless of agent frontmatter, and all cost estimates in this repo become meaningless. Report the value and flag it.
   - **Declared tiers per active agent.** For each agent named by the active stack profile, read `model:` (and `model_plan:` where present) from its `.md` frontmatter and list them, so the operator sees the intended routing next to any override.

   This step reads the environment and agent files only — it changes nothing.

6. **Check for local-agent shadowing and the run state file.**

   - **Shadowing.** `Glob <repo>/.claude/agents/*.md` and `~/.claude/agents/*.md`. For
     each file whose basename (minus `.md`) matches the bare name of any agent in the
     active stack profile's `agents_per_phase` (e.g. a local `developer.md` alongside
     the profile's `laravel-architect`/`developer` fallback, or `qa.md`/`tester.md`
     next to `qa-engineer`), report it as a collision — that name would win the
     model's agent-selection over the qualified plugin agent if the orchestrator ever
     dispatched an unqualified `subagent_type`. See `pipeline-orchestrator/SKILL.md`
     Step 3c for the qualified-dispatch fix and Step 2 for the run-marker enforcement
     this collision is normally caught by.
   - **Run state file.** Check `<repo>/.claude/.sdlc-run-active.json`. If present, read
     `schema_version` (absent = v1 marker), `task_slug`, `started_at`, `updated_at`,
     `resume_count` and `phase_status`, and compare `updated_at // started_at` to now — the
     same rule `enforce-agent-model.sh` and the telemetry hooks use. Report:
     - **fresh (< 6h)** → an apparently active run: print the phase-status summary
       (`N completed / M`) and note that `/sdlc:start` will offer to resume it. Informational.
     - **stale (≥ 6h), v2** → a crashed or force-quit run that is **resumable**: print the
       summary and suggest `/sdlc:start --resume` (or `rm .claude/.sdlc-run-active.json` to
       discard it).
     - **stale, v1** (no `schema_version`) → a pre-2.0 leftover; not resumable; suggest `rm`.
     Doctor never deletes or edits the file.

   This step reads the filesystem only — it changes nothing.

7. **Check dispatch telemetry.** Two read-only observations:

   - **Hook wiring.** Confirm the plugin's `hooks/hooks.json` registers `SubagentStart` and
     `SubagentStop` entries pointing at `dispatch-log.sh` / `subagent-usage.sh`, and that the
     scripts resolve at `${CLAUDE_PLUGIN_ROOT}/hooks/` (or the dev-checkout path). Report which
     JSON tool they will use (`jq`, else `python3`, else "neither — telemetry disabled, every
     run will be `estimated`").
   - **Last run.** Find the newest `docs/plans/*/_usage.jsonl` in the project. Run
     `scripts/usage-report.sh {slug} --project-root .` on it and report
     `usage_source_summary` (measured / unmeasured / not_started), `total_cost_usd`,
     `nested_cost_usd`, and any dispatch with `pricing_note: "unknown model"` (a model id
     missing from `references/pricing.json` — the one case where a maintainer must act). If
     no log exists, say so; a project that has never run `/sdlc:start` has none.

8. **Check the git branching model.** Run `${CLAUDE_PLUGIN_ROOT}/scripts/detect-git-flow.sh` (falling back to `<repo>/plugins/sdlc/scripts/detect-git-flow.sh` in a development checkout) and report what `/sdlc:start` would decide. Always run it **fresh** — never read the cache for this report. A doctor that echoes a stale cache cannot diagnose a stale cache.

   Report:

   - **Effective source** — whether an explicit `git:` block in `<project>/.claude/sdlc.local.yaml` overrides detection, and which keys it sets. An override means the detected values below are informational only.
   - **Detected model** — model, confidence, and the `sources[]` provenance.
   - **Branches** — default branch, develop branch (or "—"), any `release/*` branches.
   - **Naming convention** — separator, word separator, ticket pattern, and the observed prefix histogram.
   - **Documented conventions** — which of the files in `references/GIT-FLOW.md` Step B exist and whether any states a branch convention. Read them; do not assume.
   - **Cache state** — `<project>/.claude/.sdlc-git-flow.json`: absent, fresh (younger than 30 days and `user_confirmed`), unconfirmed, or stale. When it is present and its `model` disagrees with the fresh detection, flag it — that is a repo whose branching model changed under a cached answer.
   - **Branch creation method** — per `references/GIT-FLOW.md` Step F-2a: `git flow {subcommand} start` when the model is `git-flow` and `git_flow_cli_available` and `git_flow_initialized` both hold, else raw `git checkout -b`. When the model is `git-flow` but the CLI is unavailable or uninitialized, say so — that is the one case where the operator can change the outcome (install `git flow`, or run `git flow init`) by acting outside the pipeline.

   This step reads the filesystem and runs read-only git plumbing. It creates no branch and writes no cache.

9. **Render output.** Default = human-readable table. With `--json` flag, emit a single valid JSON object to stdout and exit.

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
  session cache: fresh (written 4m ago by SessionStart hook) — /sdlc:start will use it
  (or: session cache: absent — /sdlc:start will run a full scan)
  (or: ⚠️  session cache disagrees with fresh detection: cached=vanilla, detected=laravel — run /sdlc:start --redetect-stack)

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

Local-agent shadowing:
  ⚠️  .claude/agents/developer.md shadows profile agent 'laravel-architect' (as fallback role 'developer')
  ⚠️  .claude/agents/qa.md shadows profile agent 'qa-engineer'
  (dispatch already qualifies subagent_type as "{plugin}:{agent}" — these are informational
   unless something dispatches the bare name)

Run marker:
  ✅ no .claude/.sdlc-run-active.json present

Dispatch telemetry:
  hooks: ✅ SubagentStart + SubagentStop registered (jq available)
  last run: add-subscription-billing — 6 dispatches, measured=6 unmeasured=0 not_started=0
    total $1.42 (phases) + $0.04 nested; no unknown model ids
  (or: last run: none — no docs/plans/*/_usage.jsonl in this project)
  (or: ⚠️  2 dispatches priced null — model id 'claude-foo-6' missing from references/pricing.json)

Git flow:
  source: detection (no `git:` block in .claude/sdlc.local.yaml)
  🎯 model: github-flow (confidence=high) — topology:no-develop-branch, topology:prefix-histogram
  branches: default=main, develop=—, release=—
  convention: {prefix}/{kebab-slug}  separator=/  word_separator=-  ticket=—
    observed prefixes: feature=7, fix=4  (singletons discarded)
  documented conventions: CONTRIBUTING.md (no branch statement), CLAUDE.md (absent)
  cache: .claude/.sdlc-git-flow.json absent — next /sdlc:start will detect and ask
  would branch: feature/<slug> from main → PR base main
  creation method: git checkout -b (model=github-flow — git-flow CLI path does not apply)

Heads-up:
  ❌ 1 blocking dependency missing — /sdlc:start would abort.
     Run the install commands above, then retry.
```

When `CLAUDE_CODE_SUBAGENT_MODEL` is unset (or `inherit`), print `✅ no routing override` in place of the warning.

In the Git flow section, flag these conditions instead of the plain `🎯` line when they apply:

- `⚠️  config overrides detection: model={model} (keys: {list})` — the `git:` block wins, so the detected values are informational.
- `⚠️  cache disagrees with fresh detection: cached={cached_model}, detected={detected_model} — run /sdlc:start --redetect-git-flow`
- `⚠️  rules/topology conflict: {one line}` — a documented convention that the branch topology does not corroborate.
- `⚠️  model=unknown — no commits or branches; /sdlc:start will not create a branch`
- `⚠️  model=git-flow but git-flow CLI unavailable — falling back to git checkout -b. Install git-flow (AVH edition) to use "git flow {subcommand} start".`
- `⚠️  model=git-flow but repo not initialized (no gitflow.branch.master/develop) — falling back to git checkout -b. Run "git flow init" to use the CLI path.`

When no local-agent name collides with the active profile, print `✅ no local-agent shadowing detected` in place of the warning list. For the run state file:

- fresh (< 6h): `🏃 run "{task_slug}" active (started {N}m ago, last update {M}m ago, {done}/{total} phase steps) — /sdlc:start will offer to resume it`
- stale (≥ 6h), v2: `⚠️  interrupted run "{task_slug}" (last update {N}h ago, {done}/{total} phase steps) — resumable with: /sdlc:start --resume   (or discard: rm .claude/.sdlc-run-active.json)`
- stale, v1 marker (no `schema_version`): `⚠️  stale pre-2.0 run marker (started {N}h ago, task_slug={task_slug}) — not resumable. Remove with: rm .claude/.sdlc-run-active.json`

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
    "all_installed": ["vanilla", "laravel"],
    "session_cache": {
      "present": true,
      "age_seconds": 240,
      "cached_primary": "laravel",
      "agrees_with_fresh_detection": true
    }
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
  "local_agent_shadowing": [
    { "path": ".claude/agents/developer.md", "shadows": "laravel-architect", "profile_role": "developer" },
    { "path": ".claude/agents/qa.md", "shadows": "qa-engineer", "profile_role": "qa" }
  ],
  "run_marker": {
    "present": false,
    "schema_version": null,
    "stale": null,
    "resumable": null,
    "task_slug": null,
    "started_at": null,
    "updated_at": null,
    "age_seconds": null,
    "resume_count": null,
    "phase_status": null
  },
  "dispatch_telemetry": {
    "hooks_registered": true,
    "json_tool": "jq",
    "last_run": {
      "task_slug": "add-subscription-billing",
      "dispatches": 6,
      "usage_source_summary": { "measured": 6, "unmeasured": 0, "not_started": 0, "running": 0 },
      "total_cost_usd": 1.42,
      "nested_cost_usd": 0.04,
      "unknown_model_ids": []
    }
  },
  "git_flow": {
    "source": "detection",
    "config_override_keys": [],
    "detected": {
      "model": "github-flow",
      "confidence": "high",
      "sources": ["topology:no-develop-branch", "topology:prefix-histogram"],
      "default_branch": "main",
      "develop_branch": null,
      "release_branches": [],
      "prefix_style": "conventional",
      "prefix_histogram": { "feature": 7, "fix": 4 },
      "naming": {
        "separator": "/",
        "word_separator": "-",
        "ticket_pattern": null,
        "ticket_position": null,
        "observed_max_length": 42
      },
      "git_flow_cli_available": false,
      "git_flow_initialized": false
    },
    "branch_creation_method": "checkout-b",
    "documented_conventions": [
      { "path": "CONTRIBUTING.md", "states_convention": false }
    ],
    "topology_conflict": null,
    "cache": {
      "present": false,
      "user_confirmed": null,
      "stale": null,
      "disagrees_with_detection": null,
      "detected_at": null
    }
  },
  "would_abort_pipeline": true
}
```

`stack.session_cache.present` is `false` (with `age_seconds`, `cached_primary`, and `agrees_with_fresh_detection` all `null`) when `~/.claude/.sdlc-stack-cache/{hash}.json` does not exist — this is the normal state before the `SessionStart` hook has run once, or when it is disabled. `active_profile`/`primary_priority`/`all_installed` always reflect the **fresh** scan, never the cache.

`git_flow.source` is `"config"` when a `git:` block exists in `.claude/sdlc.local.yaml` (with the overridden keys listed in `config_override_keys`), otherwise `"detection"`. `git_flow.detected` is the verbatim `detect-git-flow.sh` output, always freshly computed. Every `cache.*` field is `null` when `cache.present` is `false`. `git_flow.branch_creation_method` mirrors `references/GIT-FLOW.md` Step F-2a: `"git-flow-cli"` only when `detected.model == "git-flow"` and both `detected.git_flow_cli_available` and `detected.git_flow_initialized` are `true`, else `"checkout-b"` — this field does not account for the task-type restriction in F-2a-4 (bugfix/fix/refactor/docs/chore always use `checkout-b` even when the other three conditions hold), since doctor has no task description to classify.

`local_agent_shadowing` is `[]` when no collision exists. `run_marker.stale` is `null` when `present` is `false`; otherwise `true` when `age_seconds >= 21600` (6h, matching `enforce-agent-model.sh`'s `MARKER_MAX_AGE_SECONDS`), else `false`. `age_seconds` is measured from `updated_at` when present, else `started_at` — the same rule the hooks apply. `resumable` is `true` iff `schema_version >= 2`; `phase_status` is the file's object verbatim (`null` for a v1 marker).

`would_abort_pipeline` is `true` iff any dependency with `policy=block` is missing. `model_routing.override_active` is `true` iff `CLAUDE_CODE_SUBAGENT_MODEL` is set to something other than `inherit`; `subagent_model_override` is `null` when unset.

## Hard rules

- **Effectively read-only.** Do NOT install plugins, run pipelines, or modify any existing file. The single exception is seeding `docs/cost-baseline.md` from the shipped template when that file does not exist (step 4) — a create-if-absent scaffold, never an overwrite. Step 6 (shadowing check, run-marker staleness) never deletes the marker itself — it only reports and suggests the `rm` command; the operator runs it. Step 7 only reads `_usage.jsonl` through `usage-report.sh`. Step 8 never creates a branch, never fetches, and never writes the git-flow cache.
- **Do not enforce policy.** A missing `block` dep here is just reported, not actioned.
- **Reuse, don't reimplement.** The dependency-status algorithm is described in `pipeline-orchestrator/SKILL.md` Step 0a-2 / 0a-3. If those steps change, this command's behavior must follow — this command is documentation that delegates to those steps, not a parallel implementation.
- **Exit code semantics with `--json`:** exit 0 normally; exit 1 only if the runtime-dependencies.json file itself is malformed JSON (parse error). Missing-but-blocking deps still exit 0 — report them in the JSON and let the caller decide.

## When to use

- After installing or updating a stack plugin — verify external dep wiring still resolves.
- Before kicking off a long pipeline run — confirm `/sdlc:start` won't abort at Step 0a.
- In CI / automation — `/sdlc:doctor --json` gives a machine-checkable health report.
- When a cost regression is suspected — compare current `cost_baseline` against historical values.
- After a project changes its branching model (adds or drops `develop`) — confirm the cached detection has not gone stale, and see which base branch PRs would target.
