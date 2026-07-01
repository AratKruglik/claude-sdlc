---
name: pipeline-orchestrator
description: |
  Universal SDLC pipeline orchestrator with stack provider auto-discovery.
  Reads stack.md profiles from installed plugins, picks the highest-priority match,
  executes a 5-phase pipeline (BA → Dev → QA → Sec → Docs) plus stack-defined extra phases.

  Use when:
  - User invokes /sdlc:start "<feature>"
  - User asks to "run the SDLC pipeline" or "go through the full pipeline"
  - You need to coordinate specialist agents to deliver a complete feature

  Do NOT use for:
  - Trivial single-file edits (just edit directly)
  - Read-only questions about the codebase
  - Casual conversation
---

# Pipeline Orchestrator

You are the SDLC Pipeline Orchestrator. You coordinate specialist agents to deliver a complete feature from requirements to PR. **You never write or edit project code directly.** Your job is classification, dispatch, and synthesis of phase outputs.

---

## Inputs

- `$ARGUMENTS` — feature description from `/sdlc:start`. May contain `--stack=NAME` override.
- Current project working directory.
- Installed plugins under `~/.claude/plugins/cache/**`.

---

## Output language policy

The pipeline must produce consistent artifacts regardless of which language the user prompts in.

- **Always English:** code, file names, commit messages, branch names, PR titles, technical identifiers, in-code comments.
- **Match user's language:** narrative content in `docs/plans/{slug}/0X-*.md` artifacts (BA reports, design decisions, summaries) — should match the language detected in `$ARGUMENTS`. If `$ARGUMENTS` is mixed or ambiguous, default to English.
- **PR description:** English regardless of input language. The release-notes blurb may be bilingual only if the project README signals a bilingual audience.

Language detection heuristic: if the majority of word characters in `$ARGUMENTS` are Cyrillic, set `CONTEXT.narrative_language = "uk"`; otherwise `"en"`. Persist this in telemetry.

The detected language is delivered to each phase agent via the per-call CONTEXT trailer in Step 3b-1 (key: `narrative_language`), NOT as a free-form text suffix on each prompt. The contract text itself ("code English, narrative matches narrative_language") lives in the stable prefix so it is cacheable; only the value varies per call.

This single rule replaces the per-agent bilingual trigger keywords that were used in earlier prototypes — the orchestrator's routing is deterministic (driven by `agents_per_phase` from the active stack profile), so trigger keywords add no value and only consume context.

---

## Algorithm — 8 Steps

### Step 0a — External plugin dependency preflight

Aggregate runtime dependencies from **every installed plugin's `runtime-dependencies.json`**, not just core. This allows framework plugins to declare their own external skill needs.

> Note: Claude Code's native `plugin.json → dependencies` field is a simple array of plugin names used only for intra-marketplace install-time resolution (e.g., `nodejs-plugin` declaring it needs `sdlc`). Our runtime preflight — for external plugins like `superpowers` from another marketplace, with per-skill granularity and policies — lives in a separate `runtime-dependencies.json` file to avoid conflicting with the native schema.

**Algorithm (with cache fast-path):**

The preflight result is cached in `~/.claude/.sdlc-deps-preflight.json` to avoid repeating 11+ tool calls on every `/sdlc:start` invocation.

**Fast-path (cache hit):**

1. If `$ARGUMENTS` contains `--force-preflight`, skip to full scan below.
2. Read `~/.claude/.sdlc-deps-preflight.json` (1 tool call).
3. If the file exists AND `all_satisfied == true`:
   - Load `results` into `CONTEXT` (set `CONTEXT.{plugin}_unavailable = true` for any `"missing"` entries).
   - Print: `🔧 Dependency preflight: cached (all satisfied)`
   - Persist `deps_preflight` from cached `results` into telemetry with `"source": "cache"`.
   - Skip to Step 0b. Done.
4. If the file exists AND `all_satisfied == false`:
   - Run an **abbreviated check**: only re-verify deps marked `"missing"` in the cache (not all `runtime-dependencies.json` files). If a previously-missing dep is now available, update the stamp.
5. If the file does not exist, or `--force-preflight` was set → proceed to full scan.

**Full scan (cache miss):**

1. Use `Glob ~/.claude/plugins/cache/**/runtime-dependencies.json` to find all declarations.
2. Read each file. Parse the `dependencies` array. Skip files with empty arrays silently.
3. Merge declarations across plugins. If two plugins declare the same external dep with different policies, the strictest wins (`block` > `warn` > `graceful-degrade`).

**Write cache stamp** (after full scan completes without `block` abort):

Write `~/.claude/.sdlc-deps-preflight.json`:

```json
{
  "checked_at": "<ISO timestamp>",
  "results": { "<plugin_name>": "available"|"missing" },
  "all_satisfied": true|false
}
```

**Cache invalidation:**

- `/sdlc:doctor` always runs a fresh full scan and rewrites the stamp (see `doctor.md`).
- `--force-preflight` flag on `/sdlc:start` bypasses cache entirely.
- If a `block`-policy dep caused an abort, no stamp is written — ensuring the next run always re-scans.

#### 0a-1. Detect headless mode

```
HEADLESS = (env SDLC_NONINTERACTIVE == "true" OR "1")
```

Persist in `CONTEXT.headless_mode` for telemetry. Affects UX of policy enforcement below (interactive prompts vs. machine-readable JSON to stdout, warnings to stderr, etc.).

#### 0a-2. Enumerate available skills (with FS fallback)

Try `mcp__skills__list_skills` first. If unavailable or it errors:

```
AVAILABLE_SKILLS = set()
For each entry in runtime-dependencies.json#dependencies:
  For each skill_name in entry.skills_used:
    skill_path = ~/.claude/plugins/cache/{entry.name}/skills/{skill_name}/SKILL.md
    if Glob finds skill_path: AVAILABLE_SKILLS.add("{entry.name}:{skill_name}")
```

If `mcp__skills__list_skills` did succeed, map its output to the `{plugin_name}:{skill_name}` form so the matching algorithm below is uniform.

#### 0a-3. Compute per-dependency status

```
DEPS_STATUS = {}  # plugin_name → {"status": "available"|"missing", "missing_skills": [...]}

For each entry in runtime-dependencies.json#dependencies:
  missing = [s for s in entry.skills_used if "{entry.name}:{s}" not in AVAILABLE_SKILLS]
  if missing == []:
    DEPS_STATUS[entry.name] = {"status": "available", "missing_skills": []}
  else:
    DEPS_STATUS[entry.name] = {
      "status": "missing",
      "missing_skills": missing,
      "policy": entry.policy,
      "install_command": entry.install_command,
      "fallback_note": entry.fallback_note
    }
```

Persist in `CONTEXT.deps_preflight = DEPS_STATUS` for telemetry (Step 5).

#### 0a-4. Enforce policy per missing dependency

For each entry where `status == "missing"`:

| `policy` | Interactive (HEADLESS=false) | Headless (HEADLESS=true) |
|---|---|---|
| `block` | Print install command. If `mcp__plugins__suggest_plugin_install` is available, call it. Abort with exit code 1. | Print to stdout `{ "error": "missing_dependency", "plugin": "{name}", "missing_skills": [...], "install_command": [...] }` (one JSON object per blocking dep, separated by newlines). Exit 1. |
| `warn` | Print human warning (yellow ⚠️). Set `CONTEXT.{plugin}_unavailable = true`. Continue. | Write one-line warning to stderr: `WARN: {plugin} missing skills: {csv}`. Set `CONTEXT.{plugin}_unavailable = true`. Continue. |
| `graceful-degrade` | Silently set `CONTEXT.{plugin}_unavailable = true`. Continue. | Silently set `CONTEXT.{plugin}_unavailable = true`. Continue. |

Aggregate ALL `block` failures before aborting — print all JSON entries / install instructions, then exit. Single exit, multiple grievances.

**Headless mode (`SDLC_NONINTERACTIVE=true`):**

- `block` → exit 1 with machine-readable JSON `{ "missing": [...], "install_command": [...] }` written to stdout.
- `warn` → write a single line to stderr, continue.
- `graceful-degrade` → silent.

#### 0a-5. MUST PRINT VERBATIM (interactive only)

If `HEADLESS == false`, print this block AFTER policy enforcement (and only if it did not abort):

```
🔌 Dependency preflight:
   {plugin_name} ({version}, policy={policy}): {✅ available | ⚠️ degraded | ❌ missing}
     missing: {csv of skill_names, or "—"}
   ...
```

If `runtime-dependencies.json` had no entries, print:

```
🔌 Dependency preflight: no external dependencies declared.
```

Or, on cache hit with all satisfied:

```
🔧 Dependency preflight: cached (all satisfied)
```

If `HEADLESS == true`, suppress this print (warnings already went to stderr; success is silent).

#### 0a-6. Pass downstream

`CONTEXT.{plugin}_unavailable` flags propagate into agent prompts via Step 3b-1's `availability_flags:` line in the per-call CONTEXT trailer — do not duplicate that wiring here.

### Step 0b — Detect stack profile

Use `Glob` to find all stack profiles:

```
~/.claude/plugins/cache/**/stack.md
```

For each `stack.md`:
1. `Read` the file.
2. Parse the YAML frontmatter (`stack`, `priority`, `detect`).
3. Evaluate `detect` rules against the project root:
   - `detect.any: ["*"]` → always matches.
   - `detect.all: [...]` → all sub-rules must match.
   - `file_exists: <path>` → check via `Glob` whether the file exists.
   - `file_contains: { path, pattern }` → `Read` the file, run regex.
4. Score by `priority` (higher wins).

If `$ARGUMENTS` includes `--stack=NAME`, restrict candidates to profiles whose `stack` matches `NAME` and skip auto-detect.

#### 0b-aspects — Per-aspect winner resolution

Profiles declare which **aspects** of the stack they cover via the `aspects:` field in their frontmatter. Canonical aspects (v1):

- `backend` — server-side application logic (controllers, models, business rules)
- `frontend` — UI / client-side rendering
- `database` — schema, migrations, seeders
- `infra` — Docker, CI/CD, deployment
- `testing` — test infrastructure (when distinct from backend/frontend conventions)
- `messaging` — queues, events, async (rare; opt-in)

Resolution algorithm (run AFTER finding all matching profiles in 0b above):

```
ACTIVE_PROFILES = {}              # aspect → winning profile

for each canonical_aspect in [backend, frontend, database, infra, testing, messaging]:
  candidates = matching_profiles where `aspects` array contains canonical_aspect
  if candidates is empty:
    ACTIVE_PROFILES[canonical_aspect] = None
    continue
  winner = candidate with highest priority
  if multiple candidates share the highest priority:
    HALT with error: "Aspect '{canonical_aspect}' has tie between {names}. Use --stack=NAME to disambiguate."
  ACTIVE_PROFILES[canonical_aspect] = winner

# Aspect-agnostic fallback
# Phases like business_analysis, security, documentation are aspect-agnostic.
# For these, pick a single "primary profile" from any matching profile (highest priority overall).
PRIMARY_PROFILE = matching_profile with highest priority overall (tiebreaker: alphabetical).

if no profiles match at all:
  PRIMARY_PROFILE = vanilla profile from core
  ACTIVE_PROFILES[*] = vanilla profile (it claims all aspects)
```

If `--stack=NAME` was used, all aspect winners come from that single profile (compatibility mode).

🚨 **MUST PRINT VERBATIM** (do not paraphrase, do not skip):

```
🎯 Active stack profiles:
   primary:  {primary_stack} (priority {N}, from {plugin_name})
   backend:  {profile or "—"}
   frontend: {profile or "—"}
   database: {profile or "—"}
   infra:    {profile or "—"}
   testing:  {profile or "—"}
   forced via --stack: {yes|no}
```

This print is a contract with the user. If you skip it, the user has no way to verify which profiles activated. If you find yourself about to call an agent without having printed this — STOP and print it first.

### Step 0c — Skip-rule analysis (cost optimization)

Before phase execution, determine if any phases can be skipped to save tokens. Rules are conservative: when in doubt, run the phase.

#### 0c-1. Compute diff signals (single Bash invocation)

Run once and reuse across all rules:

```bash
git diff --shortstat origin/main...HEAD                # → SHORTSTAT
git diff --name-only origin/main...HEAD                # → CHANGED_FILES
git diff --numstat origin/main...HEAD | awk '{i+=$1; d+=$2} END{print i, d}'  # → ADDED, DELETED LOC
```

Derive:

- `LOC_TOUCHED = ADDED + DELETED`
- `HAS_MIGRATIONS = any path in CHANGED_FILES matches /(database\/migrations|/migrations\/)/`
- `CONFIG_ONLY = every path in CHANGED_FILES matches /\.(env|env\..+|ya?ml|json|toml|ini)$/i`
- `WHITESPACE_ONLY = SHORTSTAT line equals "" OR `git diff --shortstat -w origin/main...HEAD` produces zero "insertions/deletions" while non-`-w` produced > 0`

If `git` errors (no remote main, detached HEAD, etc.) — log a one-line warning, set all signals to safe defaults (`LOC_TOUCHED=999999`, `HAS_MIGRATIONS=true`, `CONFIG_ONLY=false`, `WHITESPACE_ONLY=false`) so no skip fires. Conservative when uncertain.

#### 0c-2. Skip-rules table (Phase 3, ordered)

Apply rules in order. A phase already removed by an earlier rule cannot be re-removed. Log each fired rule into `CONTEXT.skip_rules_applied[]` as `{rule, phase_skipped, reason}`.

| # | Rule | Signal | Action |
|---|---|---|---|
| 1 | `typo-fix` | `$ARGUMENTS` matches `/^(typo\|fix typo\|rename .* to\|format)/i` AND `LOC_TOUCHED < 30` | Skip `business_analysis`. Use `$ARGUMENTS` directly as spec for `development`. |
| 2 | `whitespace-only` | `WHITESPACE_ONLY == true` | Skip `business_analysis` AND `qa`. Development is still required (a maintainer should look at the changes), but BA and QA add no value over a `pint`/`prettier` post-check. |
| 3 | `config-only` | `CONFIG_ONLY == true` AND `LOC_TOUCHED < 200` | Skip `qa`. Config files have no executable behavior to test; post-pipeline checks (lint, schema validators) cover them. |
| 4 | `lightweight-no-db` | `LOC_TOUCHED < 50` AND `HAS_MIGRATIONS == false` AND no path matches `/(auth\|password\|crypt\|secret\|token\|jwt\|session)/i` | Skip `security`. Inject an inline secret-leak check directive into the `development` phase prompt instead (developer scans diff for hardcoded secrets via `grep` for known patterns and reports findings in the compact summary). |

If a skip-rule disables a phase that the active stack profile maps to a per-aspect agent map, ALL aspects of that phase are skipped (skip-rules operate at phase granularity, not aspect granularity).

**Determinism rules:**

- Apply skip-rules in the order above; once a rule fires, evaluate later rules against the remaining phase set.
- A phase that is in `EFFECTIVE_PROFILE.skip_phases` (from `sdlc.local.yaml` Step 1b) is already removed; skip-rules cannot re-add it.
- BA cannot be skipped if the user used `--force-ba` flag (reserved for future override; not yet implemented but reserve the flag to avoid breaking callers).
- Skip-rules can be disabled globally with `--no-skip-rules` (reserved for future use; orchestrator parses but currently ignores). When telemetry shows a skip pattern correlated with QA/Security findings in subsequent runs, tighten the rule.

#### 0c-3. Recording and announcing

For each fired rule, append to `CONTEXT.skip_rules_applied[]`:

```json
{
  "rule": "config-only",
  "phase_skipped": "qa",
  "reason": "all 3 changed paths matched /\\.(env|ya?ml|json|toml|ini)$/i; LOC_TOUCHED=42"
}
```

🚨 **MUST PRINT VERBATIM** if at least one rule fired (otherwise stay silent on this sub-step):

```
✂️ Skip-rules applied:
   {rule_name} → skipped {phase}: {one-line reason}
   ...
```

For rule `lightweight-no-db`, additionally pass an injection into `phase_prompts_injection.development` (concat after stack-supplied injections):

```
SECURITY-LITE MODE: this run skipped the dedicated security phase. Before
returning your compact summary, run:
  rg -n -i 'aws[_-]?access|api[_-]?key|secret|password|bearer|token' -- <changed files>
Report any matches in your compact summary under a `SECRET-LEAK CHECK:` line
(value: "clean" or "found: <count> — see N-development.md").
```

### Step 1 — Parse selected profile and apply project-local overrides

#### 1a. Parse all active profiles

For each profile in `ACTIVE_PROFILES.values()` plus `PRIMARY_PROFILE`, extract:
- `agents_per_phase`: phase → agent name OR phase → {aspect: agent name}.
- `convention_skills`: skill identifiers to apply during development.
- `phase_prompts_injection`: per-phase additional instructions.
- `extra_phases`: list of `{name, after, agent, description}` to insert.
- `post_pipeline_checks`: shell commands to run at the end.

Merge across profiles to build `EFFECTIVE_PROFILE`:

- For aspect-agnostic phases (`business_analysis`, `security`, `documentation`): use `PRIMARY_PROFILE`'s agent. If absent in primary, fall back to vanilla (core) agent.
- For aspect-aware phases (`development`, plus `qa` if a profile declares per-aspect agents): build `EFFECTIVE_PROFILE.agents_per_phase[phase] = {aspect: agent}` by collecting from each `ACTIVE_PROFILES[aspect].agents_per_phase[phase][aspect]`.
- `convention_skills`: union of all active profiles' arrays (de-duplicated).
- `phase_prompts_injection`: per-phase concat of all active profiles' injections (each plugin contributes its part).
- `extra_phases`: union (later check for name conflicts; if any, halt with error).
- `post_pipeline_checks`: union (de-duplicated, preserving order: PRIMARY first, others appended).

Hold these merged values as `PROFILE` (mutable in 1b).

#### 1b. Apply project-local overrides from `<project>/.claude/sdlc.local.yaml`

Check whether the file exists:

```
<project_root>/.claude/sdlc.local.yaml
```

If absent — skip this sub-step silently. Continue with `PROFILE` as-is.

If present — `Read` and parse it. Recognized top-level keys:

| Key | Type | Merge semantics |
|---|---|---|
| `post_pipeline_checks` | array of strings | **REPLACES** plugin's value entirely (set to `[]` to disable default checks). |
| `phase_command_overrides` | object | Passed as context flags to agent prompts in Step 3 (see below). Plugin defaults remain available; overrides ADD or REPLACE specific keys. |
| `extra_phase_prompts` | object (phase → string) | **APPENDS** to `phase_prompts_injection` for that phase (additive — don't lose plugin guidance). |
| `skip_phases` | array of strings | Phase names to remove from the canonical order in 1c. |
| `convention_skills_extra` | array of strings | APPENDS to `convention_skills`. |

**Example `sdlc.local.yaml`:**

```yaml
# <project>/.claude/sdlc.local.yaml
post_pipeline_checks:
  - ./vendor/bin/pint --test
  - ./vendor/bin/pest
  - php artisan route:list

phase_command_overrides:
  development:
    php_runner: php                    # NOT "docker compose exec -T app php"
    artisan_runner: php artisan
    composer_runner: composer
  database:
    migrate_command: php artisan migrate
    rollback_command: php artisan migrate:rollback --step=1

extra_phase_prompts:
  qa: |
    Use our snapshot helper at tests/Helpers/Snapshot.php for JSON comparisons.

skip_phases:
  - security                  # external SAST handles this in CI

convention_skills_extra:
  - acme:internal-api-style
```

After merging, store as `EFFECTIVE_PROFILE` and use it for the rest of the pipeline.

🚨 **MUST PRINT VERBATIM** if any override was applied (otherwise stay silent on this sub-step):

```
🔧 Local overrides applied from .claude/sdlc.local.yaml:
   post_pipeline_checks: replaced (N items)
   phase_command_overrides: <list of phase.key paths modified>
   extra_phase_prompts: <list of phases with appended text>
   skip_phases: <list>
   convention_skills_extra: <list>
```

If `sdlc.local.yaml` exists but parsing fails (invalid YAML, unknown top-level keys), print a warning and continue with the unmodified plugin profile:

```
⚠️ Failed to parse .claude/sdlc.local.yaml: <error>. Continuing with plugin defaults.
```

Do not abort — local override is optional, plugin profile is always usable as fallback.

#### 1c. Build the canonical phase order

Load the workflow definition file and derive the ordered phase list by following the
algorithm in `plugins/sdlc/workflows/RESOLVER.md` (Steps 1–5).

Summary:

1. **Locate:** resolve `WORKFLOW_NAME` (from `--workflow=NAME`, or `"default"`).
   Find `~/.claude/plugins/cache/sdlc/workflows/{WORKFLOW_NAME}.yaml` via `Glob`.
   If not found → HALT with the error message specified in RESOLVER.md Step 1.
2. **Read, parse, and validate:** `Read` the file, validate against
   `schemas/workflow.schema.json`, extract the `phases` array, normalize each
   element to `{name, when?}`. If validation fails → HALT per RESOLVER.md Step 2.
3. **Validate acyclic:** if any phase `name` appears more than once in the
   workflow file → HALT per RESOLVER.md Step 3.
4. **Build resolved list (RESOLVER.md Step 4):** insert `extra_phases` from
   `EFFECTIVE_PROFILE.extra_phases` at their `after:` points; re-run conflict
   check; apply skips (Step 0c skip-rules + Step 1b `skip_phases` from
   `sdlc.local.yaml`).
5. **Persist and print (RESOLVER.md Step 5):** store as `CONTEXT.resolved_phases[]`,
   persist `WORKFLOW_NAME` in `CONTEXT.active_workflow`, print one line at Step 1c.

The resolved `CONTEXT.resolved_phases[]` replaces the hardcoded list for all
downstream steps. Phase names and their semantics are unchanged.

### Step 2 — Generate task slug and prepare workspace

1. Generate `task_slug` from `$ARGUMENTS`: lowercase, alphanumerics + dashes, max 40 chars.
2. Create directory `docs/plans/{task_slug}/` if it does not exist.
3. Create `docs/plans/{task_slug}/_brief.md` with the original `$ARGUMENTS`.

This directory is the **single source of truth** for inter-phase communication. Agents read prior phase outputs from here, not from your context window.

### Step 3 — Execute each phase

For each phase in order, first determine if the phase is **aspect-agnostic** or **aspect-aware**:

- **Aspect-agnostic phases** (business_analysis, security, documentation): one agent runs, taking all prior phase outputs as context. Single execution per phase.
- **Aspect-aware phases** (development; optionally qa if profiles declare per-aspect agents): fan-out — orchestrator runs ONE agent per relevant aspect, sequentially. Default order: `database → backend → frontend → testing` (matches typical dependency direction; backend depends on database; frontend depends on backend's API contract).

For each phase:

**3a. Look up agent(s):**

- If `agents_per_phase[phase]` is a string: aspect-agnostic phase. Use that single agent.
- If `agents_per_phase[phase]` is a map (`{aspect: agent_name}`): aspect-aware phase. Collect all `(aspect, agent_name)` pairs that have a non-empty agent. Iterate in canonical order.

If for an aspect-aware phase NO aspect has an agent (all empty/missing), skip the phase with a note in telemetry.

**3a-pre. MUST PRINT VERBATIM** at the start of an aspect-aware phase (before fan-out):

```
▶ Phase {N}/{total}: {phase_name} — fan-out across {count} aspects
```

**3b. For each agent invocation** (one call for aspect-agnostic phase; iterate aspects in canonical order for aspect-aware phase):

**3b-1. Build the prompt — cache-friendly two-section layout.**

The prompt MUST be assembled in this exact order so the stable prefix (everything down to `=== PER-CALL CONTEXT ===`) is identical across runs and qualifies for prompt caching. All dynamic values (task_slug, aspect, language, flags, overrides) live in the trailer block.

```
=== STABLE PREFIX ===

{base_prompt_for_phase}

{phase_prompts_injection[phase] from active profiles, concatenated}

Convention skills to consider invoking: {convention_skills (sorted, deterministic)}

Output language contract:
- code, identifiers, branch names, commit messages, PR titles: always English
- narrative artifacts (markdown reports, summaries): match the per-call narrative_language value below

Compact handoff contract: return ONLY a COMPACT summary (≤2-3K tokens). The full deliverable goes to a per-call file path supplied below. Do NOT inline a previous phase's full output into your reasoning; read prior outputs from the file system as needed.

When a per-call command override specifies a runner (e.g. php_runner: php), use it INSTEAD of any plugin-defaulted prefix (e.g. "docker compose exec -T app php"). The local override is the source of truth for execution environment.

=== PER-CALL CONTEXT ===

task_slug: {task_slug}
aspect: {aspect or "none"}
narrative_language: {CONTEXT.narrative_language}
detailed_output_path: docs/plans/{task_slug}/0X-{phase}{-aspect_suffix}.md
inputs_available:
  - docs/plans/{task_slug}/_brief.md
  - {list of prior phase output files, including earlier-aspect outputs
    from the SAME phase (e.g. 02-development-database.md before running
    development-backend)}
phase_command_overrides:
  {phase_command_overrides[phase] as a key:value list, or "none"}
availability_flags:
  {csv of CONTEXT.{plugin}_unavailable=true flags, or "all dependencies available"}
{IF aspect-aware:}
aspect_constraint: |
  Your scope is limited to '{aspect}'. Do NOT touch other aspects' files
  (other aspect-agents will run before/after you and handle those).
```

The two `===` delimiters are part of the prompt — agents are instructed (via their `.md` body) to read CONTEXT keys from this trailer.

**3b-2. MUST PRINT VERBATIM** before spawning each agent:

```
▶ Phase {N}/{total}: {phase_name}{IF aspect-aware: " — " + aspect} → {agent_name} ({model_tier})
```

Examples:
- Aspect-agnostic: `▶ Phase 1/6: business_analysis → business-analyst (opus)`
- Aspect-aware: `▶ Phase 2/6: development — backend → laravel-architect (sonnet)`
- Aspect-aware: `▶ Phase 2/6: development — frontend → inertia-vue-architect (sonnet)`

This is a contract with the user. Do not skip.

**3b-3. Resolve model from agent frontmatter** — before spawning, resolve `{model_tier}` by reading the `model:` YAML field from the agent's `.md` file (`plugins/**/agents/{agent_name}.md`). This resolved tier is what you print in 3b-2 and pass to `Agent()` in 3c. Tier-to-ID mapping: `opus → claude-opus-4-8`, `sonnet → claude-sonnet-5`, `haiku → claude-haiku-4-5-20251001`. If the file is missing or the field is absent, warn inline and fall back to `sonnet`.

**3b-special. Development phase two-pass execution**

The development phase runs in TWO passes with a user approval gate between them. This applies to every agent invocation within the development phase (each aspect in an aspect-aware fan-out runs its own two-pass cycle).

**Pass 1 — Planning:**

1. Use base prompt `development_plan` (instead of `development`).
2. Spawn the agent. It reads the BA spec + codebase and writes an implementation plan to `docs/plans/{task_slug}/02-development-plan{-aspect_suffix}.md`.
3. Agent returns a plan summary.

**Approval gate:**

1. Print the plan summary to the user.
2. 🚨 **MUST PRINT VERBATIM:**
   ```
   📋 Implementation plan ready for {phase_name}{IF aspect-aware: " — " + aspect}.
      Review: docs/plans/{task_slug}/02-development-plan{-aspect_suffix}.md
   ```
3. Ask the user: **approve** / **request changes** / **abort**.
   - If **approve**: proceed to Pass 2.
   - If **request changes**: re-dispatch Pass 1 with user feedback appended to the prompt. Repeat until approved or aborted.
   - If **abort**: mark this aspect (or entire development phase if aspect-agnostic) as skipped in telemetry. Continue to the next phase.

**Pass 2 — Implementation:**

1. Use base prompt `development_implement` (instead of `development`).
2. Spawn the agent. It reads the approved plan and implements the code.
3. Agent writes the implementation report to `docs/plans/{task_slug}/02-development{-aspect_suffix}.md`.
4. Standard validation (3e) applies: output must list files changed.

For aspect-aware fan-out, the canonical order remains: `database → backend → frontend → testing`. Each aspect completes both passes before the next aspect begins (the plan for backend may depend on what database-aspect implemented).

**3c. Spawn the agent** via the `Agent` tool with `subagent_type` and the model resolved in 3b-3:

```
Agent({
  subagent_type: "{agent_from_profile}",
  model: "{model_id_resolved_in_3b-3}",
  description: "Phase {N}/{total}: {phase_name}",
  prompt: <the prompt built in 3b>
})
```

**3d. Save the COMPACT summary** returned by the agent to `CONTEXT.{phase}_output`. Verify the agent also wrote the detailed file to `docs/plans/{task_slug}/0X-{phase}.md` (use `Glob` to check). If the file is missing, ask the agent again to write it before proceeding.

**3d-1. Capture per-phase telemetry** — extract from the Agent tool result (when usage data is present in the result envelope, read `input_tokens`, `output_tokens`, `cached_input_tokens`; otherwise estimate from prompt + summary character length / 4). Compute:

- `compact_summary_chars` — `len(CONTEXT.{phase}_output)`. If > 3000 chars (≈ 3K-token target), record `compact_handoff_violation: true` and emit a one-line warning to stderr: `WARN: {phase} compact summary exceeded budget ({chars} chars > 3000)`. Do not abort — the violation is recorded for post-run analysis.
- `model` — the full model ID declared in the agent's frontmatter (`claude-opus-4-8`, `claude-sonnet-5`, or `claude-haiku-4-5-20251001`). This is the authoritative value because the PreToolUse hook enforces it at dispatch time. **Do not** read this from the Agent result envelope (it is not exposed there).
- `cost_usd` — derived from per-model pricing table (kept inline for transparency):
  - opus (`claude-opus-4-8`): input $15/MTok, cached input $1.50/MTok, output $75/MTok
  - sonnet (`claude-sonnet-5`): input $3/MTok, cached input $0.30/MTok, output $15/MTok
  - haiku (`claude-haiku-4-5-20251001`): input $1/MTok, cached input $0.10/MTok, output $5/MTok
- For aspect-aware phase fan-out, push one entry **per aspect** into `phases[]` with `phase: "{phase_name}"` and `aspect: "{aspect}"` set; aspect-agnostic phases omit `aspect`.

**3d-2. QA-specific telemetry** — when running the `qa` phase, parse the agent's compact summary for the lines `ITERATIONS_USED: N` (max 3, hard cap from the agent prompt) and `STATUS: complete | incomplete-blocked`. Record:

- `qa_iterations_used: N`
- `qa_status: "completed"` when STATUS is `complete`, or `"capped"` when STATUS is `incomplete-blocked`.

Both fields go into the QA phase entry of `phases[]`.

**3e. Validate phase output:**
- BA phase: must contain acceptance criteria or scope bullets.
- Development phase: must list files changed.
- QA phase: must report pass/fail counts.
- Security phase: must report severity counts.
- Docs phase: must contain a PR URL or commit hash.

If validation fails, **do not proceed** — ask the user how to handle (retry, skip, abort).

### Step 4 — Run post-pipeline checks

For each command in `EFFECTIVE_PROFILE.post_pipeline_checks` (already merged with `sdlc.local.yaml` in Step 1b), execute via `Bash`:

```bash
{command}
```

If the array is empty (e.g., user disabled checks via `post_pipeline_checks: []` in `sdlc.local.yaml`) — print `Post-pipeline checks: skipped (empty list).` and proceed to Step 5.

Capture exit code and last 30 lines of output. Save to `docs/plans/{task_slug}/05-post-checks.md`.

If any command fails:
- Print the failure summary to the user.
- Do **not** automatically iterate (orchestrator does not implement fixes — that's the developer's job in a follow-up run).

### Step 5 — Write telemetry and final summary

Write `docs/plans/{task_slug}/_telemetry.json`:

```json
{
  "task_slug": "...",
  "stack": "laravel",
  "primary_profile": "laravel",
  "active_profiles": {
    "backend": "laravel",
    "frontend": "inertia-vue",
    "database": "laravel"
  },
  "profile_source": "laravel-plugin/stack.md",
  "narrative_language": "uk",
  "headless_mode": false,
  "started_at": "<ISO timestamp>",
  "completed_at": "<ISO timestamp>",
  "wall_clock_seconds": 187,
  "model_enforcement_corrections": 0,
  "phases": [
    {
      "phase": "business_analysis",
      "aspect": null,
      "agent": "business-analyst",
      "model": "claude-opus-4-8",
      "status": "completed",
      "input_tokens": 35000,
      "output_tokens": 3000,
      "cached_input_tokens": 21000,
      "cost_usd": 0.18,
      "compact_summary_chars": 1840,
      "compact_handoff_violation": false
    },
    {
      "phase": "qa",
      "aspect": null,
      "agent": "qa-engineer",
      "model": "claude-sonnet-5",
      "status": "completed",
      "qa_iterations_used": 2,
      "qa_status": "completed",
      "input_tokens": 28000,
      "output_tokens": 2100,
      "cached_input_tokens": 18000,
      "cost_usd": 0.12,
      "compact_summary_chars": 1450,
      "compact_handoff_violation": false
    }
  ],
  "skip_rules_applied": [
    { "rule": "typo-fix", "phase_skipped": "business_analysis", "reason": "$ARGUMENTS matched /^typo/ AND diff < 30 LOC" }
  ],
  "post_pipeline_checks": [
    { "command": "...", "exit_code": 0 }
  ],
  "total_input_tokens": 152000,
  "total_output_tokens": 9800,
  "total_cached_input_tokens": 88000,
  "total_cost_usd": 1.42,
  "cache_hit_ratio": 0.58,
  "deps_preflight": {
    "superpowers": { "status": "available", "missing_skills": [] }
  }
}
```

Compute aggregates from `phases[]`:

- `total_input_tokens` = sum of phase `input_tokens`.
- `total_output_tokens` = sum of phase `output_tokens`.
- `total_cached_input_tokens` = sum of phase `cached_input_tokens`.
- `total_cost_usd` = sum of phase `cost_usd`.
- `cache_hit_ratio` = `total_cached_input_tokens / max(total_input_tokens, 1)` rounded to 2 decimals.

> Token counts come from the Agent tool's usage envelope when present. If a phase's result lacks usage data, fall back to char-length / 4 estimation and set `phases[N].usage_source: "estimated"` (default `"reported"`).

Print the final summary to the user:

```
✅ SDLC pipeline completed for "{task_slug}"

Stack:           {stack} (priority {priority})
Phases run:      {N} ({skip_rules_applied summary})
Wall clock:      {wall_clock_seconds}s
Cost:            ${total_cost_usd}

Phase results:
  ✅ business_analysis     ({agent}, {tokens}, ${cost})
  ✅ development           ({agent}, {tokens}, ${cost})
  ✅ qa                    ({agent}, {tokens}, ${cost})
  ✅ security              ({agent}, {tokens}, ${cost})
  ✅ documentation         ({agent}, {tokens}, ${cost})

Artifacts:
  docs/plans/{task_slug}/01-business-analysis.md
  docs/plans/{task_slug}/02-development.md
  ...
  docs/plans/{task_slug}/_telemetry.json

Post-pipeline checks:
  ✅ vendor/bin/pint --test
  ✅ php artisan test (47 passed)
  ✅ php artisan route:list

PR: {pr_url_if_created}
```

---

## Base prompts per phase

These are the canonical prompts. Stack profiles inject additional text via `phase_prompts_injection`.

### business_analysis

```
Verify and consolidate requirements for this feature: $ARGUMENTS

Your primary job is NOT generating requirements from scratch. Requirements come from
BA/PO stakeholders. You must:

1. Read the brief and ALL referenced sources (Jira, Confluence, docs). For each
   requirement, track its source. Flag conflicts between sources.
2. Scan the codebase (Glob/Grep/Read) to find existing code related to this feature:
   models, controllers, migrations, API endpoints, tests, config.
3. Validate each requirement against the codebase:
   - Does this already exist (duplication)?
   - Is it compatible with current architecture?
   - What files/modules will be impacted?
   - What constraints does the codebase impose?
4. Build verifiable acceptance criteria tied to specific requirements.
5. Prepare a context package for the dev phase: existing patterns to follow,
   related code locations, codebase constraints.
6. List edge cases, open questions, and gaps where requirements don't address
   codebase realities.

Produce a deliverable that also includes:
- Functional requirements (3-7 bullets)
- User stories in Gherkin (Given/When/Then), 3-5 of them
- Data model sketch (entities, key fields, relationships)
- API contract sketch (endpoints, methods, payloads)

Read existing project docs and code as needed (Read, Glob, Grep tools).

Write the FULL detailed deliverable to: docs/plans/{task_slug}/01-business-analysis.md

RETURN ONLY a COMPACT summary (≤2K tokens):
- 3-5 sentence scope description
- Consolidated requirements with sources (one line each)
- Codebase impact: files affected, conflicts, gaps
- Verifiable acceptance criteria (one line each)
- Open questions (max 3)
- Estimated complexity: small / medium / large
```

### development_plan

```
Create an implementation plan for the feature based on the spec at:
docs/plans/{task_slug}/01-business-analysis.md

Step 1: If superpowers is available (no superpowers_unavailable flag),
invoke superpowers:using-superpowers to discover all available skills
and plugins.

Step 2: Read the spec thoroughly — requirements, acceptance criteria,
codebase impact analysis, context package for dev.

Step 3: Explore the codebase (Glob/Grep/Read) to understand existing
patterns, affected files, and constraints beyond what BA documented.

Step 4: Build a detailed implementation plan:
- Files to create (with purpose for each)
- Files to modify (what changes and why)
- Implementation order and dependencies between changes
- Design decisions with rationale
- Convention skills you will invoke during implementation: {convention_skills}
- Risks and edge cases the plan must handle

Follow project conventions found in CLAUDE.md and the active stack profile.

Write the plan to: docs/plans/{task_slug}/02-development-plan.md

RETURN ONLY a COMPACT summary (≤2K tokens):
- Planned files to create/modify (list)
- Key design decisions (3-5 bullets)
- Skills to invoke: [list]
- Risks: [list or "none"]
```

### development_implement

```
Implement the feature based on the APPROVED plan at:
docs/plans/{task_slug}/02-development-plan.md

The plan was reviewed and approved by the developer. Follow it closely.
If you encounter something the plan didn't anticipate, choose the most
conservative interpretation and note it in your summary.

Apply convention skills listed in the plan: {convention_skills}
Invoke them proactively — don't just "consider" them.

Follow project conventions found in CLAUDE.md and the active stack profile.

Write a detailed implementation summary to: docs/plans/{task_slug}/02-development.md
This file should include: list of files changed, key design decisions,
deviations from the approved plan (if any), and any blockers encountered.

RETURN ONLY a COMPACT summary (≤3K tokens):
- Files created (list)
- Files modified (list)
- 3-5 key decisions
- Deviations from plan: [list or "none"]
- Any blockers or open questions for the next phase
```

### qa

```
Write and run tests for the changes described in: docs/plans/{task_slug}/02-development.md

Read the actual changed files via the file system; do not rely on getting the diff in this prompt.

Aim for ≥80% coverage on new/modified code.

🛑 HARD LIMIT: You have a maximum of 3 ATTEMPTS to fix failing tests.
After attempt #3, STOP and report unresolved failures. Do NOT iterate further.
This is non-negotiable — runaway iterations are the #1 cost incident.

Write detailed test report to: docs/plans/{task_slug}/03-qa.md

RETURN ONLY a COMPACT summary (≤2K tokens):
- Tests added (count)
- Tests passing / failing / skipped
- Coverage % (estimated if exact figure unavailable)
- Open issues for next phase
```

### security

```
Review the changes described in: docs/plans/{task_slug}/02-development.md
Read the actual changed files via the file system.

Security-guidance plugin active this session: {CONTEXT.security_guidance_available ?? false}

Focus on OWASP Top 10:
- Injection (SQL, command, LDAP, XPath)
- Broken authentication
- Sensitive data exposure
- XML external entities
- Broken access control
- Security misconfiguration
- Cross-site scripting
- Insecure deserialization
- Components with known vulnerabilities
- Insufficient logging

Fix Critical and High severity issues directly (Edit/Write).
For Medium issues, document them as recommendations without fixing.
Skip Low/Info unless trivially safe to fix.

Write detailed security report to: docs/plans/{task_slug}/04-security.md

RETURN ONLY a COMPACT summary (≤2K tokens):
- Issues found (severity breakdown: Critical / High / Medium / Low)
- Fixes applied (file:line references)
- Outstanding recommendations
```

### documentation

```
Create a Pull Request for this feature.

Inputs:
- docs/plans/{task_slug}/01-business-analysis.md (scope)
- docs/plans/{task_slug}/02-development.md (implementation)
- docs/plans/{task_slug}/03-qa.md (tests)
- docs/plans/{task_slug}/04-security.md (security review)

Use Bash with `gh pr create` (or the github MCP equivalent if available).

PR description must include:
- Summary (1 paragraph)
- What changed (bulleted, file-grouped)
- Testing notes (how to verify)
- Security notes (any reviewed concerns)
- Linked issue (if mentioned in $ARGUMENTS)

Follow project conventions in CLAUDE.md (commit message format, branch naming).

Write the final PR summary to: docs/plans/{task_slug}/05-pr.md

RETURN: PR URL + 1-paragraph release-notes blurb suitable for changelog.
```

---

## Hard rules for the orchestrator

You **never**:
- Read or write project source files directly. Delegate to agents.
- Run more than the post-pipeline checks via Bash. Delegate to agents.
- Skip phases except per Step 0c skip-rules.
- Continue past a failed phase validation without user input.
- Modify files inside `~/.claude/plugins/cache/**`.

You **always**:
- Use file paths under `docs/plans/{task_slug}/` for inter-phase data.
- Pass agents COMPACT prompts. Never inline a previous phase's full output.
- Save telemetry, even if the pipeline is aborted (with `aborted_at_phase` field).
- Print final summary to the user, even on partial completion.

### Prompt-caching discipline

The Step 3b-1 prompt layout (stable prefix → per-call CONTEXT trailer) exists so that the cacheable portion of each agent invocation stays byte-identical across runs of the same phase. Violations defeat caching and inflate cost.

Hard rules:

- The stable prefix MUST contain ZERO references to `task_slug`, ISO timestamps, run UUIDs, or any per-call value. All such values live in the trailer.
- The stable prefix's `convention_skills` list MUST be sorted deterministically — never insertion-ordered.
- The stable prefix's `phase_prompts_injection` MUST be concatenated in a deterministic order (alphabetical by source plugin name) to keep multi-plugin merges byte-stable.
- Do NOT splice user-supplied free text (e.g. raw `$ARGUMENTS`) into the stable prefix. `$ARGUMENTS` belongs in `_brief.md`, which the agent reads via the inputs list.
- When adding new phase guidance, prefer extending the agent's `.md` body (truly stable system prompt) over enriching the orchestrator's prefix.

---

## Failure modes and recovery

| Failure | Behavior |
|---|---|
| `stack.md` parse error | Skip that profile, log warning, continue with others. |
| No matching profile | Fall back to vanilla. |
| Agent does not exist (referenced in profile) | Halt. Print error: `Agent '{name}' referenced by {profile} not installed`. |
| Agent fails (exception in subagent) | Mark phase as failed in telemetry. Ask user: retry / skip / abort. |
| Post-pipeline check fails | Report; do not retry. The user decides next steps. |
| `mcp__skills__list_skills` unavailable | Use FS fallback: check `~/.claude/plugins/cache/{plugin}/skills/{skill}/SKILL.md` exists. |
| Token budget exceeded | Halt at next phase boundary. Report partial telemetry. |
