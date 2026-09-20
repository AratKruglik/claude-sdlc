# Changelog

All notable changes to the SDLC marketplace are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/), versioning is [SemVer](https://semver.org/) per plugin.

## [2.0.0] — marketplace v2.0.0 / all plugins v2.0.0

Per-phase cost stops being a guess, a crashed run stops costing twice, QA and security stop
waiting on each other, and the `Skill` tool starts actually being available to the agents that
were told to use it.

### Breaking

Read this section before upgrading. Each entry is breaking because something that used to be
valid now is not, or produces a different shape.

- **`_telemetry.json` changes shape.** Per-dispatch entries gain `agent_id`, `model_id`,
  `pass`, `group_index`, `started_at`, `completed_at`, and the file gains
  `usage_source_summary`, `nested_cost_usd` and `total_cost_usd_including_nested`.
  `total_cost_usd` keeps its old meaning — phase dispatches only — so `cost_scope` stays
  truthful, but anything parsing this file needs updating.
- **The run marker becomes a state file** (`schema_version: 2`). `.claude/.sdlc-run-active.json`
  keeps `task_slug`, `started_at`, `roster` and `phase_agents` so the hooks are backward
  compatible, and adds the decisions a resume cannot re-derive. Freshness is now judged by
  `updated_at` falling back to `started_at`.
- **Workflow recipes gain a `parallel` construct**, and `Phase N/total` counts **steps**, not
  phases. The members of a group share an `N`. A recipe using `parallel` will not load on
  v1.x, and any tooling that parsed `Phase N` as a phase index must now treat it as a step
  index.
- **`security-analyst` is report-only.** It has no `Edit` tool and never changes code. If you
  relied on the security phase applying its own fixes, that work now happens in a
  `[pass:fix]` dispatch by the development architect, followed by a QA `[pass:verify]` rerun.
  Its compact summary replaces `FIXES_APPLIED` with `MUST_FIX` and adds
  `ENTRY_POINTS_CHECKED` / `CALLERS_TRACED`.
- **The dispatch `description` contract is load-bearing.** `Phase {N}/{total}: {phase}[ — {aspect}][ [pass:…]]`
  is parsed by three consumers. A free-form description silently breaks model enforcement, the
  off-roster deny message, and telemetry attribution.
- **Backend architects moved their API/props contract from the implementation report to the
  plan.** It now lives under a section headed exactly `Contract for frontend` in
  `02-development-plan{-aspect}.md`. Anything reading the contract out of
  `02-development-backend.md` must be repointed.
- **Cache locations moved** to `${CLAUDE_PLUGIN_DATA}/stack-cache/` and
  `${CLAUDE_PLUGIN_DATA}/deps-preflight.json`, falling back to `~/.claude/.sdlc-*` when the
  variable is unset.
- **Hook timeouts were in the wrong unit.** Stack plugins declared `"timeout": 30000`, meaning
  30000 *seconds*. They now declare `30` (60 for the JVM stacks).
- **Agent frontmatter contract changed** — see Added. Notably `tools:` must include `Skill` for
  any agent expected to invoke one.
- **`CONTRIBUTING.md` describes the current layout.** It documented `packages/<stack>/` and
  `stack-manifest.json`, neither of which has existed since v1.0.
- **`detect-stack.py` and `usage-report.py` are gone**, replaced by `.sh` equivalents with the
  same contracts. There is no Python anywhere in this repository any more.

### Added

- **Measured telemetry.** `dispatch-log.sh` (`PreToolUse`/`SubagentStart`) and
  `subagent-usage.sh` (`SubagentStop`) append to `docs/plans/{slug}/_usage.jsonl`;
  `scripts/usage-report.sh` pairs and attributes them. Usage is summed from each subagent's own
  transcript, **deduplicated by `message.id`** — one API response spans several lines with the
  same id, and summing them naively inflates the total 2.5–3×. Prices come from
  `references/pricing.json`, one source of truth. Nested dispatches (a phase agent spawning
  `Explore` or a superpowers skill) are metered into `nested_cost_usd`.
- **`/sdlc:start --resume`.** Re-enters at the first group with unfinished members. Guards: it
  halts if `HEAD` is not the branch the run recorded, and re-runs a plan pass whose file is
  missing rather than presenting an approval gate for a plan that does not exist. Starting
  fresh over a live state file prompts three ways rather than overwriting artefacts.
- **Parallel phase groups.** `default`, `bugfix`, `hotfix` and `refactor` run
  `{parallel: [qa, security]}`. A group is dispatched as several foreground `Agent` calls in
  one assistant message; failure, retry and skip are per member; the cost cap is checked once
  per group.
- **Security fix pass and QA verify rerun**, with an explicit four-outcome table: a failed
  security review produces no fix pass (no trustworthy findings to apply), and a failed QA
  produces no verify rerun (no passing baseline to compare against).
- **Run-scoped guard hooks**, all inert outside a run: `pre-commit-guard.sh` (denies
  `--no-verify` and staged secrets, naming `file:line`; scans added lines only, so removing a
  secret is never blocked), `config-protection.sh` (denies mid-run tooling-config edits unless
  `task_type` is `chore`), `post-implement-check.sh` (runs the stack's typecheck once per
  architect and relays failures as a retry hint).
- **Agent capability frontmatter** across every agent: `skills: [sdlc:architect-conventions]`
  on the 24 stack agents, `maxTurns` everywhere, `memory: project` on architects, specialists
  and security-analyst, and `Skill` in `tools:` for the 28 agents the orchestrator tells to
  invoke one.
- **`user-invocable: false` and `paths:`** on all 61 convention skills — hidden from the `/`
  menu, and auto-activated only under the paths they are about. The pipeline invokes them
  explicitly, so `paths` cannot break a run.
- **`when:` conditions** on phase members (`complexity == small|medium|large`), evaluated after
  BA. When BA was skipped or emitted no `COMPLEXITY:` line the member **runs** — an unevaluated
  condition is unknown, not false.
- **Project-local workflow recipes** in `<project>/.claude/sdlc-workflows/`, validated against
  the same schema and marked `(project-local)` in the announce line.
- **Opt-in post-check fix pass** (`post_check_fix_attempts`, cap 1). A check that is wrong
  about the code is reported, never edited.
- **Experimental `aspect_execution: parallel-implement`** — plan passes stay sequential behind
  one approval gate, implementation passes run concurrently, but only when three deterministic
  invariants hold over the approved plans. Off by default, and documented as constraining what
  the plans declare rather than what an agent can reach.
- **`userConfig`** in the sdlc plugin: `noninteractive`, `default_cost_cap_usd`,
  `stack_cache_ttl_hours`, `post_check_fix_attempts`.
- **CI** (`.github/workflows/ci.yml`): shellcheck and `bash -n`, all test harnesses, schema
  validation, README agent-table drift, relative-link resolution, and
  `claude plugin validate --strict` for all 24 plugins. Plus `scripts/ci/*.sh`, all bash.
- **Eval suite** (`plugins/sdlc/evals/`), four cases, run as a manual `workflow_dispatch` job
  since they make real model calls.
- **`plugins/sdlc/security-patterns.yaml`** — six `core_`-prefixed stack-agnostic rules.

### Fixed

- **No agent had `Skill` in its `tools:` allowlist.** Every documented skill invocation in the
  marketplace was dead text: the "First: load `sdlc:architect-conventions`" line in 24 agents,
  `architect-conventions` steps 1/7/9, and the `Apply skills: …` list every `stack.md` passes
  into the dispatch prompt. Confirmed by headless dispatch probes before and after.
- **The documented model-resolution order was stale.** It is per-invocation parameter →
  frontmatter → `CLAUDE_CODE_SUBAGENT_MODEL` → session model, so that variable alone does not
  override the enforcement layers; `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` (Claude Code v2.1.257+)
  does. The repo documented the reverse in six places — accurate before Claude Code v2.1.251,
  and not updated since. `/sdlc:doctor` now warns only on `_FORCE`.
- **Skip-rule 4 was too easy to trip.** Skipping the security phase now requires two empty
  checks: a widened path regex, and a content check over the **added** lines of the diff.
  Either hit keeps security in the pipeline.
- **`typo-fix` could not match Ukrainian.** Its patterns moved into
  `references/task-type-patterns.json` with `опечатк`, `одрук`, `форматув`, `перейменув` — the
  last two carrying no left boundary, since Ukrainian prefixes attach directly to the stem.
- **Four SPA frontend architects read nothing about a backend contract.** `vue`, `react`,
  `angular` and `rn` now read it from the backend plan and report a divergent response as a
  `BLOCKER` rather than adapting to it.
- **`java-plugin/security-patterns.yaml` duplicated `java-foundation` byte for byte.** Deleted;
  `java-plugin` already depends on `java-foundation`. Zero `rule_name` collisions remain.
- **`references/pricing.json` had two wrong prices** — found by the cost research this
  release's own telemetry work motivated. Sonnet was priced at `$3/$15`; the `$2/$10`
  launch rate became the standard price and the scheduled increase was cancelled, so every
  measured Sonnet dispatch was **overstated by 50%**. Fable 5.1 and Mythos 5.1 read cache
  at `0.025x`, not the `0.1x` every other tier uses — a 43% overstatement on a cache-heavy
  dispatch. Both fixed, both now pinned by tests.
- **The `hotfix` cost cap would have fired on healthy runs.** `$2.50` sat on a modelled
  healthy hotfix cost of `$2.45` — exactly what its own comment says a runaway guard must
  never do. Raised to `$8.00`; `docs-only` from `$0.20` to `$0.40` on the same reasoning.
- **Two dead documentation links** (`ARCHITECTURE.md` → a never-committed ADR, `CONTRIBUTING.md`
  → a pre-`plugins/` schema path), and the broken `yq '.frontmatter'` schema-validation recipe
  in the README, which could never have worked.

### Changed

- **The README cost section is rebuilt from the way dispatches actually bill.** The old
  table modelled each phase as one API request; an agentic loop re-sends its whole context
  every turn, which makes cost roughly quadratic in dispatch length and the old figure low
  by 2–3×. A medium feature models at ~$6 cached, ~$21 cache-cold.
- `docs/cost-baseline.md` and `MODEL-ROUTING.md` now defer to measured numbers. The estimates
  remain as reasoning, explicitly superseded by whatever your own baseline says.
- `README.md`, `ARCHITECTURE.md`, `CONTRIBUTING.md` and `plugins/sdlc/README.md` rewritten
  against the shipped design.

## [1.5.0] — marketplace v1.5.0 / sdlc plugin v1.5.0

Branch *creation* on a git-flow project can now go through the real `git flow` CLI (AVH
edition) instead of always shelling out to raw `git checkout -b`.

### Added

- **`git flow <subcommand> start` branch creation** (`references/GIT-FLOW.md` new Step
  F-2a). Used only when all hold: the detected model is `git-flow`, the `git flow` binary is
  installed, the repo has actually run `git flow init` (`gitflow.branch.master` and
  `gitflow.branch.develop` are both set — a bare `gitflow.prefix.*` key does not count), and
  the task type maps to a native subcommand (`feature`, `release`, `hotfix`). `bugfix`,
  `fix`, `refactor`, `docs`, and `chore` intentionally keep using `checkout -b`: AVH
  git-flow's own `bugfix` subcommand bases off `develop`, which contradicts this pipeline's
  `{REL}` else `{MAIN}` policy for that type (`GIT-FLOW.md` Step D-1).
- `detect-git-flow.sh` now reports two new read-only fields, `git_flow_cli_available` and
  `git_flow_initialized`, alongside the existing topology signals. Neither installs the
  binary nor runs `git flow init` — the detector stays observation-only per its existing
  contract.
- When the git-flow CLI path does not apply (binary missing, not initialized, or a
  non-native task type), the pipeline **silently** falls back to `checkout -b` — this is the
  pre-existing behavior, not a degraded mode, so it does not interrupt the Step F gate with a
  warning.
- `/sdlc:doctor` reports the branch-creation method that would be used and flags the two
  actionable cases: git-flow detected but the CLI is missing, or detected but not
  initialized.
- `plugins/sdlc/skills/pipeline-orchestrator/SKILL.md`'s git command allowlist gained `git
  flow version` (read-only CLI probe) and `git flow {feature|release|hotfix} start {topic}`
  (mutating, conditioned on Step F-2a) — the orchestrator never runs `git flow init` or
  `git flow ... finish` itself.
- Two new fixture cases in `test-detect-git-flow.sh` (48 → 53 assertions) covering
  prefix-only config (not initialized) vs. fully initialized (`branch.master` +
  `branch.develop` set).

Also adds session-scoped caching for stack-profile detection, to cut the token cost of
`/sdlc:start` and `/sdlc:doctor` re-running the same Glob+Read+parse pass over every
installed plugin's `stack.md` on every invocation.

- **`scripts/detect-stack.py`** — a read-only reimplementation of `pipeline-orchestrator/
  SKILL.md` Step 0b and Step 0b-aspects (profile matching, per-aspect winner resolution,
  aspect-tie detection) as a standalone script. Never raises on a malformed `stack.md`; skips
  it and records a `parse_errors` entry instead.
- **`hooks/session-start-stack-cache.sh`** — a new `SessionStart` hook, registered in
  `hooks/hooks.json` alongside the existing `PreToolUse` model-enforcement hook. Runs
  `detect-stack.py --write-cache` on `startup`/`resume`/`clear` (skips `compact`/`fork`,
  where the repo can't have changed) and writes the result to
  `~/.claude/.sdlc-stack-cache/{sha1(repo-path)[:16]}.json`. Prints nothing — a
  `SessionStart` hook fires on every session on the machine, so any stdout here would be a
  token cost paid unconditionally to save tokens conditionally.
- **`pipeline-orchestrator/SKILL.md` Step 0b** gained a cache fast-path (mirroring Step 0a's
  "Fast-path / Full scan / Cache invalidation" structure): a fresh, repo-matching cache with
  no recorded `aspect_ties` is adopted directly, skipping the Glob+Read+parse pass. A
  recorded aspect tie still HALTs the gate exactly as the inline algorithm would — the cache
  is never allowed to silently resolve a tie the full scan would have surfaced. New
  `--redetect-stack` flag (mirrors `--redetect-git-flow`) forces a full scan.
- **`/sdlc:doctor`** now runs `detect-stack.py` for its own stack-profile check (reusing the
  one algorithm instead of a second hand-rolled copy) and additionally reports the session
  cache's presence, age, and whether it agrees with the fresh detection — kept deliberately
  separate from the "always fresh" fresh-scan result, same principle as its existing
  git-flow-cache-disagreement check.
- `test-detect-stack.sh` — 23 assertions covering vanilla/Laravel/full-stack detection, a
  fabricated aspect tie (must be recorded, never silently resolved), a malformed `stack.md`,
  an empty plugins root, and `--write-cache`.

## [1.4.1] — marketplace v1.4.1 / sdlc plugin v1.4.1

Fixes three related defects in task-type classification and recipe selection introduced by
1.4.0's git-flow work, discovered when a Ukrainian-language `/sdlc:start` description failed
to select the `refactor` recipe and fell all the way back to the full 5-phase `default`
pipeline.

### Fixed

- **Every Cyrillic keyword in task-type classification was permanently dead.** ECMAScript
  `\w` is `[A-Za-z0-9_]`, so `\b` never asserts a boundary next to a non-Latin character —
  with or without the `u` flag. `GIT-FLOW.md` Step C-2's Ukrainian patterns (`\bрефактор\b`,
  `\bтерміново\b`, `\bвиправ`, ...) never matched anything, in any input, since the feature
  shipped. The table now lives in `plugins/sdlc/references/task-type-patterns.json` as
  complete, ready-to-compile regex sources using Unicode property escapes
  (`(?<![\p{L}\p{N}])` / `(?![\p{L}\p{N}])`) instead of `\b`, and gained several previously
  missing Ukrainian stems (`bugfix`, `chore`, and broader `feature` coverage).
- **`arguments_pattern` on a `task_type`-mapped recipe could silently veto a correct
  classification.** `RESOLVER.md` Step 1 rule 3 re-checked a recipe's own (narrower, English
  -only) `arguments_pattern` after the authoritative classifier had already named a
  `task_type` — so even a fixed Ukrainian classification could still be discarded by
  `refactor.yaml`'s Latin-only regex. `arguments_pattern` is no longer read by rule 3; every
  built-in recipe's `match` block now carries only measurable signal constraints
  (`loc_touched_max`, `config_only`), and is removed entirely from `refactor.yaml`, which had
  nothing else. New Step 1b in `RESOLVER.md` documents the split: a constraint *selects* in
  rule 4, it only *vetoes* in rule 3.
- **`bugfix`, `hotfix`, and `docs-only` were unreachable on a freshly created branch.**
  `loc_touched_max` and `config_only` never evaluate to true while `diff_scope ==
  "prospective"` (correct for rule 4, where an unmeasurable diff must not select a recipe) —
  but rule 3 was applying the same all-fail treatment to an already-`task_type`-confirmed
  recipe, on what Step 0c calls "the most common way to start a run". Rule 3 now treats an
  unmeasured signal constraint as not applicable rather than failed.
- Added `plugins/sdlc/scripts/test-task-typing.sh` — compiles every pattern in
  `task-type-patterns.json` and asserts classification outcomes (Ukrainian, English, false
  -positive guards, precedence), plus a standing sanity check that no pattern regresses to a
  literal `\b`.

### Known limitation (not fixed here)

- The `typo-fix` skip-rule (`pipeline-orchestrator/SKILL.md` Step 0c-2, rule 1) matches
  `$ARGUMENTS` with its own English-only, start-anchored regex and has the same language
  blind spot. It gates BA-skipping for trivial typo fixes, not recipe selection — left for a
  follow-up.

## [1.4.0] — sdlc plugin v1.4.0

Makes the pipeline git-flow aware. Until now it had no branch logic at all: `/sdlc:start` ran
on whatever branch happened to be checked out, and `gh pr create` was never given a `--base`,
so on a git-flow project every PR silently landed against `main`. The pipeline now detects the
project's branching model **and its actual naming convention**, classifies the task type, puts
the run on an appropriate branch, and targets the PR at the correct base.

### Added

- **Branching-model detection** — `plugins/sdlc/scripts/detect-git-flow.sh`, a read-only shell
  script that emits one JSON object: `git-flow` vs `github-flow`, confidence and provenance,
  default/develop/release branches, and the naming convention learned from the repo's own
  branches (separator, word separator, ticket-key pattern, prefix histogram). Shipped with
  `test-detect-git-flow.sh` (15 fixture repos, 46 assertions). Prefixes seen only **once** are
  discarded as noise — a typo in branch history must not become a learned convention.
- **Documented-convention scan** — `CLAUDE.md`, `.claude/rules/*.md`, `CONTRIBUTING.md`,
  `.cursorrules`, PR templates. An explicitly documented rule **outranks** the branch
  histogram, and a rules/topology conflict is surfaced rather than silently resolved.
- **Task-type classification** — deterministic keyword table with a fixed precedence order
  (`hotfix > release > bugfix > fix > refactor > docs > chore > feature`), overridable with
  `--type=NAME`. Drives the branch prefix, the merge target, and the workflow recipe.
- **Merge-target policy** — `feature`/`fix` → `develop`; `bugfix`/`hotfix` → the active
  `release/*` or `main`; `release` → `main`. github-flow collapses every row to the default
  branch. A `hotfix`/`release` PR carries a "requires back-merge to develop" note (opening that
  second PR remains out of scope).
- **Interactive branch gate** — prints the model, convention, task type and proposed branch,
  then offers create / continue / rename / change type / abort. "Continue" is withheld on a
  base branch, which would otherwise produce a `main → main` PR.
- **`git:` block in `.claude/sdlc.local.yaml`** — authoritative override for model, branches,
  naming and per-type policy, plus `auto_create_branch: false` for CI.
- **Detection cache** `.claude/.sdlc-git-flow.json` — trusted for 30 days once confirmed,
  busted by `--redetect-git-flow`, always bypassed by `/sdlc:doctor`. Excluded from version
  control via `.git/info/exclude`, like the run marker.
- **`/sdlc:doctor`** reports the effective model, its provenance, the learned convention, the
  branch a run would create, and whether the cache disagrees with fresh detection.
- **`references/GIT-FLOW.md`** — the full algorithm, kept out of the orchestrator skill body
  the same way `workflows/RESOLVER.md` is.

### Fixed

- **Skip-rules measured the diff against a hardcoded `origin/main`.** On a git-flow project a
  feature branch's base is `develop`, so `LOC_TOUCHED` counted everything released since the
  last merge-back and every skip-rule decision built on it was wrong. The base is now the
  detected `base_branch`.
- **Prospective runs no longer trigger every skip-rule.** A freshly created branch has an empty
  diff, which read as `WHITESPACE_ONLY`, vacuously `CONFIG_ONLY`, and `LOC_TOUCHED = 0` —
  skipping business analysis, QA *and* security, and satisfying every recipe's
  `loc_touched_max` ceiling. `COMMITS_AHEAD == 0` now takes the same conservative path as a git
  error (no rule fires) and marks `diff_scope: "prospective"`, under which a `loc_touched_*`
  constraint counts as unsatisfied. An unmeasurable diff is unknown, not small.
- **Workflow auto-selection is now implemented.** `README.md` promised the orchestrator checked
  each recipe's `match` rules; `RESOLVER.md` only honoured `--workflow=NAME`, leaving the
  `match:` blocks in `bugfix`/`hotfix`/`refactor`/`docs-only` as dead code. Selection order is
  now flag → config → task type → match scan → default, with the deciding rule printed and
  recorded in telemetry. An inferred-but-missing recipe warns and falls through; an explicitly
  named missing recipe still halts.
- **The documentation phase now commits and pushes the task branch** before opening the PR, and
  reports a null PR with a clear reason when the branch has no commits against its base —
  previously `gh pr create` would fail with a bare "no commits between".
- **README's recipe cost caps contradicted the recipe files** (`$0.60`/`$0.10` versus the
  actual `$2.50`/`$0.20`), and its header line still advertised v1.3.0 after 1.3.1 shipped.

### Known limitations

- `/sdlc:batch` worktree branches are named by the `Agent` tool, so they do not follow the
  learned convention. Their PR base is still correct, since it derives from the task type.
- Back-merging `hotfix/*` / `release/*` into `develop` is reported, not automated.
- Issue-tracker metadata (Jira issue type) is deliberately not a classification signal —
  typing must stay reproducible from `$ARGUMENTS` alone.

## [1.3.1] — sdlc plugin v1.3.1

Fixes an off-roster dispatch bug: a project-local `.claude/agents/{tester,reviewer,...}.md`
roster could silently replace a pipeline phase's declared agent (`qa-engineer`,
`security-analyst`, ...), bypassing model-tier enforcement, artifact validation, and
telemetry entirely. Full analysis: `MODEL-ROUTING.md` §3, D8.

### Added

- **Pipeline run marker** (`.claude/.sdlc-run-active.json`) — written at Step 2 with the
  resolved agent roster for the run, deleted at Step 5 / on abort. Kept out of version
  control via a `.git/info/exclude` entry.
- **`agent_overrides`** key in `.claude/sdlc.local.yaml` — a sanctioned way to deliberately
  dispatch a project-local agent for a given phase.
- **`/sdlc:doctor`** now reports local-agent/profile-agent name collisions and a stale
  (>6h) run marker.

### Fixed

- **`enforce-agent-model.sh` now denies off-roster project- or user-local agents**
  (`.claude/agents/*.md`, `~/.claude/agents/*.md`) while a pipeline run marker is active.
  Plugin agents and built-ins (`general-purpose`, `Explore`, ...) are unaffected — the deny
  is scoped to local agents only. The denial carries both a `permissionDecisionReason`
  (read by Claude, so it can re-dispatch the correct agent) and a `systemMessage` (read by
  the user, so the shadowing isn't invisible).
- **`subagent_type` is now qualified as `{plugin_name}:{agent_name}`** at dispatch (Step
  3c), closing the name collision between a plugin's bare agent name and a same-named
  project-local agent.
- **`enforce-agent-model.sh` resolved a nondeterministic agent `.md`** when two versions of
  the same plugin were installed side by side (`sdlc/1.2.1/` and `sdlc/1.3.0/`) — `find |
  head -1` had no ordering guarantee. Now version-sorted, newest wins.
- **`hooks.json`'s fallback resolution path was dead** (`~/.claude/plugins/cache/sdlc`
  never matches the versioned installed layout, `~/.claude/plugins/cache/{marketplace}/
  sdlc/{version}/`). Replaced with a version-sorted glob over the real layout.
- **`allow_warn`'s JSON interpolation of caller-supplied `agent_name`** could produce
  malformed JSON if the name contained a quote or backslash. Now built with `jq` when
  available.
- **`CONTRIBUTING.md`'s role-naming guidance was inverted** — it recommended generic,
  collision-prone agent names (`developer`, `tester`, `qa`) and claimed `subagent_type`
  cannot be namespaced, both no longer true. Corrected to recommend distinctive,
  plugin-scoped names.

## [1.3.0] — marketplace v1.3.0 / all plugins v1.3.0

Model-routing audit. The tiering across all 29 agents was calibrated when Opus cost 5× Sonnet per input token; it now costs 1.67×. Parts of the repo had already been repriced and parts had not, and the two halves disagreed. Full analysis and rationale: `MODEL-ROUTING.md`.

### Added

- **Two-tier development phase.** The phase already ran a planning pass and an implementation pass either side of the human approval gate, but both resolved the same `model:`, so the structure carried no benefit. A new optional frontmatter field **`model_plan:`** is now resolved for the planning pass (falling back to `model:` when absent). All 19 development-phase agents — 18 stack architects plus the vanilla `developer` — declare `model_plan: opus` alongside `model: sonnet`. Database specialists are unaffected; they run in a separate phase with no planning pass.
  - `pipeline-orchestrator/SKILL.md` step 3b-3 resolves the field; step 3c stamps a `[pass:plan]` / `[pass:implement]` marker into the `Agent()` `description`.
  - `enforce-agent-model.sh` reads that marker and enforces the matching field. Without it the hook would have rewritten every Opus planning dispatch back down to `sonnet` with no visible symptom.
- **`MODEL-ROUTING.md`** — the audit itself: defects with file references, routing decisions, what was deliberately left alone, and the `model`/`effort` API asymmetry.
- **Cost-baseline scaffold** — `/sdlc:doctor` has parsed `<repo>/docs/cost-baseline.md` since it was written, but the file never existed and `docs/` is gitignored, so committing one would not have helped. The scaffold now ships as `plugins/sdlc/templates/cost-baseline.md`, and doctor step 4 seeds the project copy from it when absent (create-if-missing, never an overwrite — the command's only write).
- **Workflow cost-cap enforcement** (step 3d-3). `caps.max_total_cost_usd` was declared in the schema and two recipes but enforced nowhere. The running total is now checked after each phase and the user is asked whether to continue — never a silent abort.
- **`frontend-design`** (official Anthropic plugin) added as an optional external dependency and referenced from the seven frontend-capable stack profiles. Raw generation converges on generic AI aesthetics regardless of model tier; guidance fixes that, a bigger model does not.
- **`/sdlc:doctor` model-routing section** — reports `CLAUDE_CODE_SUBAGENT_MODEL` and the declared tier of every active agent.

### Fixed

- **Telemetry priced Opus at the previous generation's rate.** Step 3d-1 computed `cost_usd` from `opus: $15 in / $1.50 cached / $75 out`, inflating every Opus phase 3×, while `README.md` was already computed at $5/$25 — verified arithmetically across all five rows of that table. Corrected to `$5 / $0.50 / $25`.
- **`compact_handoff_violation` compared characters against a token threshold.** The check fired above `3000 chars` while labelling itself a "3K-token target", and every agent contract states its budget in tokens (≤2K, ≤3K). The threshold was ~4× too tight, so compliant agents tripped it every run — destroying the pipeline's only sensor for model verbosity drift. Now converts to tokens first.
- **The stated enforcement guarantee was false.** `README.md` claimed the declared tier is used "regardless of the session-level default model". Claude Code resolves in the order `CLAUDE_CODE_SUBAGENT_MODEL` → per-invocation parameter → frontmatter, so that environment variable overrides both enforcement layers silently. The claim now carries the condition, in both `README.md` and `SKILL.md`.
- **Hook tier allowlist** accepted only `opus|sonnet|haiku`; the `Agent` tool also accepts `fable`. Added — no agent is assigned to it.
- **Hotfix cost cap was unreachable.** `$0.60` against a real dev+qa+security run of ~$1.52 would have aborted every hotfix once enforcement existed. Recalibrated as runaway guards: hotfix `$2.50`, docs-only `$0.20`.
- README model+effort table listed 22 of 29 agents; regenerated from frontmatter, now complete.
- `batch-pipeline/SKILL.md` carried a second copy of the stale Opus pricing (`$15/$75`) and a `~$1.50` baseline in its mandatory pre-dispatch cost confirmation. It now defers to the orchestrator's table and uses the current `~$2.40` baseline, so batch estimates stop understating a run in one direction while overstating Opus in the other.
- `business-analyst` and `document-writer` were missing the `Write` tool they need to produce their phase artifacts (carried on this branch from before the audit).

### Changed

- `security-analyst` moved from `effort: high` to `xhigh`. It is the one agent whose failures are silent — no error, no failing test — and it processes a small token volume.
- Telemetry carries `cost_scope: "subagent_phases_only"`. The orchestrator's own consumption (skill body, profile globbing, workflow resolution, approval-gate exchanges) runs on the session model and cannot be metered from inside the skill. `total_cost_usd` is a floor, not a bill.
- Cost estimates updated across `README.md` and `ARCHITECTURE.md`: ~$2.40 standard / ~$1.98 intro for a medium feature, against ~$1.84 / ~$1.42 before. The increase is deliberate — the argument is cost per completed task, and one avoided rework cycle exceeds the delta. Opting out is one line: `model_plan: sonnet`, or drop the field.
- All plugin versions aligned to 1.3.0 with the marketplace.

### Known limitations

- **`effort` cannot be varied per dispatch.** The original design called for the planning pass to run at `effort: xhigh` while implementation stayed at `medium`. Not implementable: `effort` is read from frontmatter only and the `Agent` tool exposes no override, so both passes of one agent necessarily share a value. Development architects stay at `medium`.
- Complexity-based escalation (Opus for implementation when a task touches auth, payments, or concurrency) is designed but not built — it needs a machine-readable complexity signal from the BA phase plus a schema extension. See `MODEL-ROUTING.md` §8.
- The Dev-plan and Security-at-`xhigh` cost rows are assumptions, not measurements. Populating `docs/cost-baseline.md` from real runs replaces them.

## [1.2.1] — marketplace v1.2.1 / sdlc v1.2.1

### Changed

- **Execution-model documentation** — `/sdlc:start`, the root README, `plugins/sdlc/README.md`, and `pipeline-orchestrator/SKILL.md` now explicitly state that the pipeline runs synchronously in the current Claude Code session (not as a detached/autonomous background job), that the user stays engaged through dependency/stack-detection checks and phase boundaries (including the interactive development-phase approval gate), and that the final `documentation` phase autonomously opens a Pull Request via `gh pr create`. Addresses [#13](https://github.com/AratKruglik/claude-sdlc/issues/13).
- Fixed a stale banner reference in `plugins/sdlc/commands/start.md`: the doc said Step 0b prints `🎯 Detected stack: ...`, but the orchestrator actually prints `🎯 Active stack profiles: ...` — the doc now matches the skill's actual output.
- Reconciled `plugins/sdlc/.claude-plugin/plugin.json` version (was lagging at 1.1.0) with the marketplace version.

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
