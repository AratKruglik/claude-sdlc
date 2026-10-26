# Pipeline orchestrator — inline fallback for Steps 0a–1c

Read this only when no RUN PLAN is in context **and** `scripts/run-plan.sh` could not produce
one (no `jq`, or it printed an `error`). Each section continues the step of the same name in
`SKILL.md`; the fast-path paragraphs, and every rule that still applies with a plan, stay there.

## Step 0a — External plugin dependency preflight

Aggregate runtime dependencies from **every installed plugin's `runtime-dependencies.json`**, not just core. This allows framework plugins to declare their own external skill needs.

> Note: Claude Code's native `plugin.json → dependencies` field is a simple array of plugin names used only for intra-marketplace install-time resolution (e.g., `nodejs-plugin` declaring it needs `sdlc`). Our runtime preflight — for external plugins like `superpowers` from another marketplace, with per-skill granularity and policies — lives in a separate `runtime-dependencies.json` file to avoid conflicting with the native schema.

**Algorithm (with cache fast-path):**

The preflight result is cached in `${CLAUDE_PLUGIN_DATA}/deps-preflight.json` (the plugin data directory Claude Code provides; fall back to `~/.claude/.sdlc-deps-preflight.json` when the variable is unset, e.g. a dev checkout) to avoid repeating 11+ tool calls on every `/sdlc:start` invocation.

**Fast-path (cache hit):**

1. If `$ARGUMENTS` contains `--force-preflight`, skip to full scan below.
2. Read `${CLAUDE_PLUGIN_DATA}/deps-preflight.json` (1 tool call).
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

Write `${CLAUDE_PLUGIN_DATA}/deps-preflight.json`:

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

#### 0a-2. Enumerate available skills (with FS fallback)

Try `mcp__skills__list_skills` first. If unavailable or it errors:

```
AVAILABLE_SKILLS = set()
For each entry in runtime-dependencies.json#dependencies:
  For each skill_name in entry.skills_used:
    skill_path = ~/.claude/plugins/cache/*/{entry.name}/*/skills/{skill_name}/SKILL.md
    if Glob finds skill_path: AVAILABLE_SKILLS.add("{entry.name}:{skill_name}")
```

The installed layout is `cache/<marketplace>/<plugin>/<version>/`, hence both wildcards. A hit
proves the plugin is on disk, not that it is enabled in this project — a local-scope install
for another project leaves the same files — which is why `mcp__skills__list_skills` comes first.

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

#### 0a-7. Detect security-guidance plugin

Use `Glob ~/.claude/plugins/cache/**/security-guidance/.claude-plugin/plugin.json` (same detection as `/sdlc:security-init` Step 5). Set `CONTEXT.security_guidance_available = true` if found, `false` otherwise. The security-phase base prompt reads this flag directly.


## Step 0b — Detect stack profile

If `$ARGUMENTS` includes `--stack=NAME`, skip both the cache and the full scan below entirely:
restrict candidates to profiles whose `stack` matches `NAME` (still located via the Glob in the
full-scan path, since a forced stack still has to be read from *some* `stack.md`) and treat it
as the sole match for 0b-aspects.

Otherwise, resolve via a cache fast-path, same shape as Step 0a's dependency preflight —
`scripts/detect-stack.sh` is the exact same algorithm as the full scan below (it exists so a
`SessionStart` hook can precompute this once per session for free; see
`hooks/session-start-stack-cache.sh`), and this step is just choosing whether to read its
cached output or re-run the algorithm inline.

**Fast-path (cache hit):**

1. If `$ARGUMENTS` includes `--redetect-stack`, skip to the full scan below.
2. Compute the cache path: `sha1(realpath(project_root))[:16] + ".json"` under
   `${CLAUDE_PLUGIN_DATA}/stack-cache/` (fallback when the variable is unset: `~/.claude/.sdlc-stack-cache/`). `Read` it (1 tool call).
3. Trust it when **all** hold: `schema_version == 1`; `repo` field matches
   `realpath(project_root)`; `detected_at` is younger than `stack_cache_ttl_hours` (plugin option `CLAUDE_PLUGIN_OPTION_STACK_CACHE_TTL_HOURS`, default 6h — matching the run-marker
   staleness window elsewhere in this pipeline); `aspect_ties` is `{}` (a recorded tie must
   still reach the operator — see step 4).
4. If `aspect_ties` is non-empty, do **not** silently pick a winner — this is the one
   correctness trap in trusting a precomputed cache. HALT exactly as the inline algorithm
   would: `Aspect '{aspect}' has tie between {names}. Use --stack=NAME to disambiguate.`
5. Otherwise, load `primary_profile` and `active_profiles` directly from the cache into
   `PRIMARY_PROFILE` / `ACTIVE_PROFILES`. Print `🔧 Stack detection: cached (session start
   hook, {age}m old)`. Skip to the 0b-aspects print. Done.
6. Cache absent, stale, schema mismatch, repo mismatch, or unreadable → fall through to the
   full scan. This is a supported, silent fallback — the hook not having run yet (first
   session after install, or a non-interactive harness that skips hooks) is normal, not an
   error.

**Full scan (cache miss):**

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

This is the same logic `scripts/detect-stack.sh` runs non-interactively; running it inline here
(rather than shelling out) is deliberate — a cache miss on `--stack=NAME` or a fresh repo is
already the exception path, and keeping one obviously-correct inline algorithm as the source of
truth is worth more than a hard dependency on `jq` being present for every session.

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

## Step 0c — Skip-rule analysis

#### 0c-1. Compute diff signals (single Bash invocation)

Run once and reuse across all rules:

`BASE` is `CONTEXT.base_branch` from Step 0b-git — **not** a hardcoded `origin/main`. On a
git-flow project a feature branch's base is `develop`, so measuring against `main` would count
every commit released since the last merge-back as part of this task's diff and make every
signal below wrong.

```bash
git diff --shortstat {BASE}...HEAD                # → SHORTSTAT
git diff --name-only {BASE}...HEAD                # → CHANGED_FILES
git diff --numstat {BASE}...HEAD | awk '{i+=$1; d+=$2} END{print i, d}'  # → ADDED, DELETED LOC
git rev-list --count {BASE}..HEAD                 # → COMMITS_AHEAD
```

Derive:

- `LOC_TOUCHED = ADDED + DELETED`
- `HAS_MIGRATIONS = any path in CHANGED_FILES matches /(database\/migrations|/migrations\/)/`
- `CONFIG_ONLY = every path in CHANGED_FILES matches /\.(env|env\..+|ya?ml|json|toml|ini)$/i`
- `WHITESPACE_ONLY = SHORTSTAT line equals "" OR `git diff --shortstat -w {BASE}...HEAD` produces zero "insertions/deletions" while non-`-w` produced > 0`

If `git` errors (no such base ref, detached HEAD, etc.) — log a one-line warning, set all signals to safe defaults (`LOC_TOUCHED=999999`, `HAS_MIGRATIONS=true`, `CONFIG_ONLY=false`, `WHITESPACE_ONLY=false`) so no skip fires. Conservative when uncertain.

**Nothing to measure — `COMMITS_AHEAD == 0` OR `CHANGED_FILES` is empty.** Every signal above is
*retrospective*: it measures work that already exists. When there is no diff, the raw values
invert the intent of every rule below — `SHORTSTAT` is empty so `WHITESPACE_ONLY` reads true,
`CONFIG_ONLY` is vacuously true over an empty file set ("every path matches" holds for zero
paths), and `LOC_TOUCHED` is 0. Left alone, that skips business analysis, QA **and** security.

Both halves of the condition are load-bearing:

- `COMMITS_AHEAD == 0` — Step 0b-git just created the branch. This is now the most common way
  to start a run, so the trimmed pipeline would become the default.
- `CHANGED_FILES` is empty **with** commits present — e.g. a commit reverted later in the same
  branch. `COMMITS_AHEAD` is 2, so the commit count alone does not catch this.

In either case take the same conservative path as a `git` error — the safe defaults above, no
rule fires — and set `CONTEXT.diff_scope = "prospective"` with the reason. Otherwise set
`CONTEXT.diff_scope = "retrospective"`.

Gate on the **diff**, not on the commit count: an empty diff is the thing that makes every
signal meaningless, and it has more than one cause.

`diff_scope` also gates recipe matching: a `loc_touched_max` / `loc_touched_min` constraint in
a workflow recipe counts as **not satisfied** when `diff_scope == "prospective"` (see
`RESOLVER.md` Step 1), so an unmeasurable diff cannot satisfy a ceiling by being empty.

#### 0c-2. Skip-rules table (Phase 3, ordered)

Apply rules in order. A phase already removed by an earlier rule cannot be re-removed. Log each fired rule into `CONTEXT.skip_rules_applied[]` as `{rule, phase_skipped, reason}`.

| # | Rule | Signal | Action |
|---|---|---|---|
| 1 | `typo-fix` | `$ARGUMENTS` matches any pattern in `references/task-type-patterns.json` → `skip_rules.typo_fix.patterns` (compiled with that file's `flags`) AND `LOC_TOUCHED < 30` | Skip `business_analysis`. Use `$ARGUMENTS` directly as spec for `development`. |
| 2 | `whitespace-only` | `WHITESPACE_ONLY == true` | Skip `business_analysis` AND `qa`. Development is still required (a maintainer should look at the changes), but BA and QA add no value over a `pint`/`prettier` post-check. |
| 3 | `config-only` | `CONFIG_ONLY == true` AND `LOC_TOUCHED < 200` | Skip `qa`. Config files have no executable behavior to test; post-pipeline checks (lint, schema validators) cover them. |
| 4 | `lightweight-no-db` | `LOC_TOUCHED < 50` AND `HAS_MIGRATIONS == false` AND **neither** the path check nor the content check below finds anything | Skip `security`. Inject an inline secret-leak check directive into the `development` phase prompt instead (developer scans diff for hardcoded secrets via `grep` for known patterns and reports findings in the compact summary). |


**Rule 4's two checks.** Skipping the security phase is the most consequential skip in the
table — a missed vulnerability is silent, unlike a missed test. So rule 4 fires only when
**both** checks come back empty, and either one finding anything is enough to keep security in
the pipeline.

*Path check* — any changed path matching, case-insensitively:

```
auth|password|crypt|secret|token|jwt|session|upload|exec|shell|raw|query|fetch|http|storage|serializ
```

*Content check* — the **added** lines of the diff, so that deleting a dangerous call does not
keep the phase alive for no reason:

```bash
git diff {BASE}...HEAD | grep '^+' | grep -nE 'DB::raw|eval\(|exec\(|shell_exec|child_process|subprocess|pickle|unserialize'
```

A hit in either check means the rule **does not fire** and security runs. Record which check
fired and the matching path or pattern in `skip_rules_applied[]`'s reason field for the rule
that did fire, so a reader can tell "no risk signal" from "not checked".

Both lists are deliberately broad. The cost of a false negative here is a shipped
vulnerability; the cost of a false positive is one extra security phase on a small diff.

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

## Step 1a — Parse all active profiles


For each profile in `ACTIVE_PROFILES.values()` plus `PRIMARY_PROFILE`, extract:
- `agents_per_phase`: phase → agent name OR phase → {aspect: agent name}.
- `convention_skills`: skill identifiers to apply during development.
- `phase_prompts_injection`: per-phase additional instructions.
- `extra_phases`: list of `{name, after, agent, description}` to insert.
- `post_pipeline_checks`: shell commands to run at the end.

Merge across profiles to build `EFFECTIVE_PROFILE`:

- For aspect-agnostic phases (`business_analysis`, `security`, `documentation`): use `PRIMARY_PROFILE`'s agent. If absent in primary, fall back to vanilla (core) agent.
- For aspect-aware phases (`development`, plus `qa` per the rule below): build `EFFECTIVE_PROFILE.agents_per_phase[phase] = {aspect: agent}` by collecting from each `ACTIVE_PROFILES[aspect].agents_per_phase[phase][aspect]`.
- **`qa` fan-out rule:** if MORE than one distinct profile is active across aspects (full-stack run, e.g. Laravel backend + Inertia frontend), build `EFFECTIVE_PROFILE.agents_per_phase.qa = {aspect: qa_agent}` where `qa_agent` is that aspect profile's declared `qa` agent (a per-aspect map entry if declared, else its plain `qa` value, else `qa-engineer`). Each aspect then gets its own QA pass with that aspect's `phase_prompts_injection` — one sonnet pass per codebase language instead of a single pass over a mixed PHP+TS diff. If only one profile is active, keep the single aspect-agnostic QA pass (backward compatible).
- `convention_skills`: union of all active profiles' arrays (de-duplicated).
- `phase_prompts_injection`: per-phase concat of all active profiles' injections (each plugin contributes its part).
- `extra_phases`: union (later check for name conflicts; if any, halt with error).
- `post_pipeline_checks`: union (de-duplicated, preserving order: PRIMARY first, others appended).

Hold these merged values as `PROFILE` (mutable in 1b).

## Step 1b — Example `sdlc.local.yaml`


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


## Step 1c — Build the canonical phase order

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
6. **Persist the cost cap:** store `caps.max_total_cost_usd` (when the recipe declares
   one) in `CONTEXT.max_total_cost_usd`. When the recipe declares none, use the plugin option
   `CLAUDE_PLUGIN_OPTION_DEFAULT_COST_CAP_USD` if it is set and greater than 0, otherwise `null`.
   The recipe value always wins over the option. Enforced in Step 3d-3.

The resolved `CONTEXT.resolved_phases[]` replaces the hardcoded list for all
downstream steps. Phase names and their semantics are unchanged.

