---
name: pipeline-orchestrator
user-invocable: false
effort: medium
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

## Execution model

This algorithm runs **synchronously in the current session** — there is no detached or autonomous background process. The user stays engaged through Steps 0-2 and every phase boundary below, including the interactive plan/approve/request-changes/abort gate in the development phase (Step 3b-special). `SDLC_NONINTERACTIVE=true` (headless mode) only changes how policy failures and prompts are surfaced (machine-readable output vs. interactive text) — it does not make execution detached or asynchronous.

A run is **resumable**: Step 2 writes a state file (`.claude/.sdlc-run-active.json`, schema v2) and every phase boundary updates it, so a session lost to compaction, a crash or a closed terminal can be continued with `/sdlc:start --resume` from the first unfinished phase (Step R) instead of paying for the completed ones again.

---

## Inputs

- `$ARGUMENTS` — feature description from `/sdlc:start`. May contain `--stack=NAME` override, or `--resume` (Step R) in which case the description may be empty.
- Current project working directory.
- Installed plugins under `~/.claude/plugins/cache/**`.
- `<project>/.claude/.sdlc-run-active.json` — the state file of an in-progress run, if any (Step R / Step 2).
- Plugin options (see below), delivered by Claude Code as `CLAUDE_PLUGIN_OPTION_*` environment variables.

### Precomputed run plan (hook fast path)

When `/sdlc:start` is typed, the `UserPromptSubmit` hook `hooks/user-prompt-run-plan.sh` runs
`scripts/run-plan.sh` and injects one block into your context:

```
=== SDLC RUN PLAN (precomputed by hooks/user-prompt-run-plan.sh) ===
{ …compact JSON… }
=== END RUN PLAN ===
```

It holds the deterministic results of Steps 0a, 0b, 0b-git (GIT-FLOW A–E, never the gate), 0c,
1b (the listed keys), 1c and the Step 2 slug, plus `print_blocks` — the verbatim 🔌 / 🎯 / 🌿 /
✂️ / `workflow:` text each step must print. **When the block is present, every step below marked
"Fast path" reads its keys and prints its block instead of re-deriving the answer with
`Glob`/`Read`/`Bash`.** The inline algorithms for Steps 0a–1c live in
`${CLAUDE_SKILL_DIR}/references/fallback-steps.md` as the authoritative definition and as the
last-resort fallback. Decisions that need a human — the branch gate, the plan approval, ties and halts —
are never taken by the plan: it reports them under `halts[]` / `gate_default` and you ask.

When the plan would exceed the hook context cap, the block instead names a JSON file: `Read` it
once and treat its content exactly as the inline plan.

Trust the plan only for the prompt it was computed for: the block carries the `arguments` it saw;
if they differ from `$ARGUMENTS`, ignore it and fall back. `warnings[]` are printed once, verbatim.

**No block, or a stale one.** A `/sdlc:batch` task runs this skill inside a subagent, where
`UserPromptSubmit` does not fire, and a harness may skip hooks. Then compute the plan yourself,
once, and use its JSON exactly as the block:
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/run-plan.sh" --repo . --arguments "<$ARGUMENTS>"` (append
`--headless` in headless mode; dev checkout: `plugins/sdlc/scripts/run-plan.sh … --dev-root .`).
Only when that fails — no `jq`, or the JSON carries an `error` — read `references/fallback-steps.md`
once and follow its inline algorithms.

### Plugin options (`userConfig`)

Declared in the plugin manifest; the user sets them when enabling the plugin. Every option reaches this skill and the hooks as an environment variable named `CLAUDE_PLUGIN_OPTION_<KEY>` (key uppercased). An explicit project or environment setting always wins over the option:

| Option | Env var | Default | Read at | Overridden by |
|---|---|---|---|---|
| `noninteractive` | `CLAUDE_PLUGIN_OPTION_NONINTERACTIVE` | `false` | Step 0a-1 | `SDLC_NONINTERACTIVE` (env) |
| `default_cost_cap_usd` | `CLAUDE_PLUGIN_OPTION_DEFAULT_COST_CAP_USD` | `0` (off) | Step 1c | `caps.max_total_cost_usd` in the recipe |
| `stack_cache_ttl_hours` | `CLAUDE_PLUGIN_OPTION_STACK_CACHE_TTL_HOURS` | `6` | Step 0b | `--redetect-stack` |
| `post_check_fix_attempts` | `CLAUDE_PLUGIN_OPTION_POST_CHECK_FIX_ATTEMPTS` | `0` | Step 4 | `post_check_fix_attempts` in `sdlc.local.yaml` |

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

## Hard rules for the orchestrator

You **never**:
- Read or write project source files directly. Delegate to agents.
- Run any Bash command beyond the post-pipeline checks and the Bash allowlist below. Delegate to agents.
- Skip phases except per Step 0c skip-rules.
- Continue past a failed phase validation without user input.
- Modify files inside `~/.claude/plugins/cache/**`.
- Dispatch an agent that is not named in `EFFECTIVE_PROFILE.agents_per_phase` (or added
  via `agent_overrides` in `sdlc.local.yaml`) — not even if a project-local agent (e.g.
  `.claude/agents/tester.md`) looks like a better fit for the phase than the profile's
  declared agent. This is what the Step 2 run marker and the `enforce-agent-model.sh`
  deny rule enforce; the orchestrator must not route around it by improvising a name.
- Dispatch a phase agent with `run_in_background`. Every phase in Step 3 is synchronous
  by design (see "Execution model" above) — a backgrounded dispatch skips the Step 3d
  artifact-file validation and the Step 3d-1 telemetry capture for that phase entirely.
  A parallel group is not an exception: its members are concurrent **foreground** calls
  issued in one message (3c-group), and the orchestrator still blocks until all of them
  return. (`batch-pipeline` is a separate skill with a separate execution model and is
  not governed by this rule.)
  artifact-file validation and the Step 3d-1 telemetry capture for that phase entirely.
- Commit, merge, rebase, force-push, tag, or delete a branch. Branch *creation* (below) is the
  only history-shaping act the orchestrator performs; committing belongs to the documentation
  phase and merging belongs to a human reviewing the PR.

### Bash allowlist (Steps R, 0b-git, 0c, 2, 3d-1 and 5 only)

Branch setup needs git plumbing and telemetry needs one read-only script, which is why the
Bash rule above is scoped rather than absolute. Exactly these are permitted:

**Read-only (Steps R / 0b-git / 0c / 2)** — `git rev-parse` (including `--abbrev-ref HEAD` for
the Step R branch guard and `--git-path info/exclude` for the Step 2 exclusion), `git symbolic-ref`,
`git for-each-ref`, `git branch` (listing only), `git config --get` / `--get-regexp`,
`git ls-remote --heads`, `git status --porcelain`, `git diff` (the Step 0c signals),
`git rev-list --count`, `git check-ref-format`, `git flow version` (the F-2a CLI-availability
probe), and `scripts/detect-git-flow.sh`. Step 0c's rule-4 content check additionally
pipes one of those reads — `git diff {BASE}...HEAD | grep '^+' | grep -nE '<pattern>'` —
which stays read-only: `grep` over a diff, never over the working tree.

**Read-only (Steps 0a–1c fallback / 3d-1 / 5)** — `scripts/run-plan.sh`, `scripts/deps-preflight.sh` (`--write-cache` writes only the plugin-data stamp), `scripts/detect-stack.sh --shape-only` and `bash "${CLAUDE_PLUGIN_ROOT}/scripts/usage-report.sh" {task_slug} --project-root .` (dev checkout: `plugins/sdlc/scripts/…`). They read the repo and `docs/plans/{task_slug}/_usage.jsonl` and print JSON.

**Writing one artifact (Step 5)** — `bash "${CLAUDE_PLUGIN_ROOT}/scripts/finalize-telemetry.sh" {task_slug} --project-root . [--aborted-at-phase X] [--extra JSON]`. It writes exactly `docs/plans/{task_slug}/_telemetry.json` and prints the final summary.

**Mutating** — only three, each narrowly conditioned:

- `git fetch origin {base_branch}` — only when the base ref does not resolve locally
  (GIT-FLOW Step F-3). One attempt, no retry loop.
- `git checkout -b {branch_name} {base_branch}` — only after the GIT-FLOW Step F gate
  resolves to *create*, and only when GIT-FLOW Step F-2a's git-flow-CLI conditions do
  *not* all hold. Unconditional in headless mode per Step F-4 when F-2a does not apply.
- `git flow {feature|release|hotfix} start {topic}` — only after the GIT-FLOW Step F gate
  resolves to *create* **and** every GIT-FLOW Step F-2a condition holds (git-flow model,
  CLI installed, repo initialized via `git flow init`, task_type in the native-subcommand
  table). Never `git flow init`, `git flow {subcommand} finish`, or any other subcommand —
  the orchestrator only starts branches, it never finishes or inits git-flow itself.

Anything outside this list is a delegation to an agent or a job for the user, not something to
improvise with a shell command.

You **always**:
- Use file paths under `docs/plans/{task_slug}/` for inter-phase data.
- Pass agents COMPACT prompts. Never inline a previous phase's full output.
- Update `phase_status` + `updated_at` in the state file at every phase boundary (3d-0) — it is
  the only thing that makes a crashed run resumable, and it keeps the hooks armed.
- Save telemetry, even if the pipeline is aborted (with `aborted_at_phase` field).
- Print final summary to the user, even on partial completion.
- Run Step R before Step 0a — never start a second run on top of a fresh state file without
  asking.

### Prompt-caching discipline

The Step 3b-1 prompt layout (stable prefix → per-call CONTEXT trailer) exists so that the cacheable portion of each agent invocation stays byte-identical across runs of the same phase. Violations defeat caching and inflate cost.

Hard rules:

- The stable prefix MUST contain ZERO references to `task_slug`, ISO timestamps, run UUIDs, or any per-call value. All such values live in the trailer.
- The stable prefix's `convention_skills` list MUST be sorted deterministically — never insertion-ordered.
- The stable prefix's `phase_prompts_injection` MUST be concatenated in a deterministic order (alphabetical by source plugin name) to keep multi-plugin merges byte-stable.
- Do NOT splice user-supplied free text (e.g. raw `$ARGUMENTS`) into the stable prefix. `$ARGUMENTS` belongs in `_brief.md`, which the agent reads via the inputs list.
- When adding new phase guidance, prefer extending the agent's `.md` body (truly stable system prompt) over enriching the orchestrator's prefix.

---

## Algorithm — 8 Steps

### Step R — Resume check (before anything else)

`Read` `<project>/.claude/.sdlc-run-active.json`. This is the state file Step 2 writes and every
phase boundary updates (3d-0). Decide how to proceed:

| State file | `--resume` given | Action |
|---|---|---|
| absent | no | Continue to Step 0a (normal start). |
| absent | yes | HALT: `❌ Nothing to resume — no .claude/.sdlc-run-active.json in this project.` |
| present, `schema_version` < 2 | any | It is a v1 marker (no `phase_status`), i.e. a crashed pre-2.0 run. Cannot resume. Ask **start fresh** (delete it, continue to 0a) / **abort**. Headless: start fresh, one stderr line. |
| present, v2, `updated_at` older than 6h | any | Stale — a crashed or force-quit run. Print `⚠️ Stale run "{slug}" found (last update {age} ago)` and ask **resume** / **start fresh** / **abort**. Headless: start fresh. |
| present, v2, fresh | yes | Resume (R-1 … R-5). |
| present, v2, fresh | no | 🚨 **MUST PRINT VERBATIM** and ask — never silently start a second run on top of an active one: |

```
⏸️  An SDLC run is already in progress in this project:
   task:     "{task_slug}"  (started {started_at}, last update {updated_at})
   branch:   {git_flow.branch_name}
   progress: {N completed}/{M} phase steps
   resume / start fresh / abort ?
```

- **resume** → R-1 … R-5.
- **start fresh** → if `$ARGUMENTS` produces the same `task_slug` as the state file, move
  `docs/plans/{task_slug}/` to `docs/plans/_archive/{task_slug}-{YYYYMMDDTHHMMSSZ}/` so the
  old artifacts are not silently overwritten; delete the state file; continue to Step 0a.
- **abort** → stop. Nothing written.
- Headless mode (`SDLC_NONINTERACTIVE=true`) without `--resume`: start fresh, one stderr line
  `WARN: stale/active run "{slug}" archived — starting fresh`. With `--resume`: resume.

**R-1 … R-5 — resuming.** Only when the decision above is *resume*: read
`${CLAUDE_SKILL_DIR}/references/resume.md` once and follow it (R-1 branch guard, R-2 CONTEXT
from the state file, R-3 refresh, R-4 print, R-5 enter Step 3).

### Step 0a — External plugin dependency preflight

**Fast path.** With a RUN PLAN in context, take `deps_preflight` (results, `all_satisfied`, `dependencies[]`, `security_guidance_available`, `source: cache|scan`) and print `print_blocks.preflight`; the hook already ran the scan or the cache fast-path and wrote the stamp. Then apply 0a-1 (headless comes from the plan's `headless_mode`) and 0a-4 policy enforcement only — the status computation (0a-2/0a-3) is done. Without the plan, run `scripts/deps-preflight.sh --write-cache` in one Bash call where `jq` exists and fall back to the inline algorithm in `references/fallback-steps.md` (Step 0a) only when it does not.

#### 0a-1. Detect headless mode

```
HEADLESS = (env SDLC_NONINTERACTIVE == "true" OR "1")
       OR (env SDLC_NONINTERACTIVE unset AND env CLAUDE_PLUGIN_OPTION_NONINTERACTIVE == "true")
```

Persist in `CONTEXT.headless_mode` for telemetry. Affects UX of policy enforcement below (interactive prompts vs. machine-readable JSON to stdout, warnings to stderr, etc.).

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

#### 0a-6. Pass downstream

`CONTEXT.{plugin}_unavailable` flags propagate into agent prompts via Step 3b-1's `availability_flags:` line in the per-call CONTEXT trailer — do not duplicate that wiring here.

### Step 0b — Detect stack profile

**Fast path.** With a RUN PLAN in context, take `stack` (primary, `active_profiles`, `aspect_ties`, `forced`, `source`) and print `print_blocks.stack`. A non-empty `aspect_ties` arrives as a `halts[]` entry — HALT with that `halts[]` text verbatim. The plan also carries `stack.project_shape` (package manager, runner prefix, test/lint/typecheck/format commands, test framework) which Step 3b-1 forwards to every agent.

Without a plan, the cache / full-scan detection and the 0b-aspects winner resolution (with its
🎯 print) are in `${CLAUDE_SKILL_DIR}/references/fallback-steps.md`, Step 0b.

#### 0b-git — Git branching model, task type, and branch setup

**Fast path.** With a RUN PLAN in context, Steps A–E are done: `git_flow` holds model, confidence, sources, the config/cache/detection provenance, `documented_convention_hits[]` (grep hits from Step B — you still judge whether a hit is a *statement* and, if so, override the model and add `rules:<path>` to sources), `task_type` with confidence and runners-up, `branch_name`, `base_branch`, `pr_base_branch`, `requires_back_merge`, `branch_creation_method`, `current_branch_is_base`, `dirty_file_count` and `gate_default`. Print `print_blocks.git_flow` (it is the F-1 block with the conditional lines already resolved) and run the gate (Step F) and the cache write (Step G) yourself — those are the only parts that mutate anything or need a human. In headless mode `print_blocks.headless_line` is the F-4 stderr line.

Determine how this project branches, classify what kind of task this is, and put the run on an
appropriate branch. Follow the algorithm in `references/GIT-FLOW.md` (Steps A–G) — locate it at
`${CLAUDE_PLUGIN_ROOT}/references/GIT-FLOW.md`, falling back to
`<repo>/plugins/sdlc/references/GIT-FLOW.md` in a development checkout.

Summary:

1. **Resolve** (GIT-FLOW Step A): `git:` block in `.claude/sdlc.local.yaml` → the
   `.claude/.sdlc-git-flow.json` cache → live detection via
   `scripts/detect-git-flow.sh` plus the documented-convention scan (Step B). Because Step 1b
   parses `sdlc.local.yaml` only later, this step reads that file itself for the `git:` key
   alone.
2. **Classify** the task type from `$ARGUMENTS` (Step C) — deterministic keyword table with a
   fixed precedence order, or an explicit `--type=NAME`.
3. **Apply** the type → branch policy (Step D) and synthesize the branch name (Step E).
4. **Gate** (Step F): print the 🌿 block, ask create / continue / rename / change type /
   abort, then `git checkout -b` on approval. Headless mode skips the prompt and reports the
   decision on stderr.
5. **Cache** the result (Step G), excluded from version control the same way Step 2 excludes
   the run marker.

Outputs consumed downstream: `CONTEXT.base_branch` (Step 0c diff signals),
`CONTEXT.task_type` (Step 1c recipe selection), and `CONTEXT.pr_base_branch`,
`CONTEXT.task_type`, `CONTEXT.requires_back_merge` (Step 3b-1 per-call trailer → the
documentation phase). Full list in GIT-FLOW Step F-5.

This step runs **before Step 2**: the branch must exist before `docs/plans/{task_slug}/` and
the run marker are written, so the pipeline's own artifacts land on the task branch rather than
on whatever branch happened to be checked out.

If the user chooses **abort** at the gate, stop here. Nothing has been written yet — no
artifacts, no run marker — so there is nothing to clean up.

### Step 0c — Skip-rule analysis (cost optimization)

**Fast path.** With a RUN PLAN in context, `diff_signals` (incl. `diff_scope` and its reason) and `skip_rules` (`skip_rules_applied[]`, `phases_removed`, `security_lite`, the rule-4 path/content hits) are computed; print `print_blocks.skip_rules` when it is non-empty and apply the SECURITY-LITE injection when `security_lite` is true. Nothing in this step needs a tool call then.

Before phase execution, determine if any phases can be skipped to save tokens. Rules are conservative: when in doubt, run the phase.

Without a plan, 0c-1 (diff signals), 0c-2 (the ordered rule table, rule 4's path and content
checks) and 0c-3 (recording and the ✂️ print) are in
`${CLAUDE_SKILL_DIR}/references/fallback-steps.md`, Step 0c.

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

With a RUN PLAN, `effective_profile` is the merged result; read only the `## Phase prompts
injection` section of each active profile's `stack.md`, concatenated per phase in the order
the Prompt-caching discipline sets. Without a plan, the full parse and merge rules (including
the `qa` fan-out rule) are in `${CLAUDE_SKILL_DIR}/references/fallback-steps.md`, Step 1a.

#### 1b. Apply project-local overrides from `<project>/.claude/sdlc.local.yaml`

**Fast path.** With a RUN PLAN in context, `local_config` already holds `present`, `active_workflow`, `skip_phases`, `git`, `post_check_fix_attempts`, `aspect_execution`, `agent_overrides` and `other_keys[]`. `Read` the file only when `other_keys[]` is non-empty, and parse only those keys (`post_pipeline_checks`, `phase_command_overrides`, `extra_phase_prompts`, `convention_skills_extra`).

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
| `git` | object | **Already consumed by Step 0b-git** — recognized here so it is not reported as an unknown key. Do not re-apply it; the branch decision is settled by now. Shape documented in `references/GIT-FLOW.md` Step A-1. |
| `agent_overrides` | object (phase → agent name) | Deliberately dispatch a different agent for that phase — e.g. a project-local `.claude/agents/{name}.md`. **REPLACES** `EFFECTIVE_PROFILE.agents_per_phase[phase]` for that phase and is added to the Step 2 run-marker `roster`, so the `enforce-agent-model.sh` PreToolUse hook allows it. Without this key, a project-local agent is off-roster for the run and the hook denies it — see Step 2 and Step 3c. |
| `post_check_fix_attempts` | integer `0` or `1` | **REPLACES** the plugin option `CLAUDE_PLUGIN_OPTION_POST_CHECK_FIX_ATTEMPTS` (default `0`) for this project. Consumed by Step 4: `1` allows one minimal-diff fix pass by the development architect when a post-pipeline check fails; `0` keeps the report-only behaviour. |
| `aspect_execution` | `sequential` (default) or `parallel-implement` | **Experimental.** Consumed by 3b-parallel-aspects. `sequential` runs each development aspect through both passes before the next begins. `parallel-implement` keeps the plan passes sequential and in canonical order, gates them all behind one approval, then dispatches the `backend` and `frontend` implementation passes concurrently — but only when the invariants in 3b-parallel-aspects hold; otherwise it falls back to sequential and prints the reason. |

An example `sdlc.local.yaml` is in `${CLAUDE_SKILL_DIR}/references/fallback-steps.md`, Step 1b.

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

**Fast path.** With a RUN PLAN in context, `workflow` is the resolved result of RESOLVER Steps 1–5: `active_workflow`, `workflow_selection_reason`, `project_local`, `resolved_phases` (list of lists, extra phases inserted, skips applied, groups collapsed), `parallel_groups`, `max_total_cost_usd` and its source. Print `print_blocks.workflow_line`. A missing `--workflow` file arrives in `halts[]` with the exact RESOLVER error text. `effective_profile` carries `phase_agents`, `roster`, `phase_status_keys`, `convention_skills` (sorted) and `post_pipeline_checks` for Step 2; `phase_prompts_injection` text is the one thing you still read from the active `stack.md` files.

Without a plan, the RESOLVER-driven algorithm (locate, validate, insert extra phases, apply
skips, persist the cost cap) is in `${CLAUDE_SKILL_DIR}/references/fallback-steps.md`, Step 1c.

### Step 2 — Generate task slug and prepare workspace

**Fast path.** With a RUN PLAN in context, `task_slug` is in the plan, and `effective_profile.roster` / `phase_status_keys` / `phase_agents` seed the state file verbatim.

1. Generate `task_slug` from `$ARGUMENTS`: lowercase, alphanumerics + dashes, max 40 chars.
2. Create directory `docs/plans/{task_slug}/` if it does not exist.
3. Create `docs/plans/{task_slug}/_brief.md` with the original `$ARGUMENTS`.
4. **Write the run state file** `.claude/.sdlc-run-active.json` (schema v2). It serves three
   consumers at once: the `enforce-agent-model.sh` PreToolUse hook (roster: a legitimate
   phase-agent dispatch vs. an off-roster project-local agent such as `.claude/agents/tester.md`),
   the telemetry hooks (`task_slug` + freshness gate), and Step R (everything a resumed session
   needs to continue). Order matters — exclude before write:
   1. Exclude it from version control **worktree-safely**: `git rev-parse --git-path info/exclude`
      gives the right path both in a normal checkout (`.git/info/exclude`) and in a worktree,
      where `.git` is a file. If that file does not already contain the line
      `.claude/.sdlc-run-active.json`, append it (idempotent; a no-op if the project already
      ignores `.claude/` wholesale). This keeps the state file out of any commit the
      document-writer phase creates without touching the project's own `.gitignore`.
   2. Compute `roster` = every agent named in `EFFECTIVE_PROFILE.agents_per_phase`
      (flattened across aspect-aware phases) plus every value in `agent_overrides`
      from `sdlc.local.yaml` (Step 1b), each qualified as `{plugin_name}:{agent_name}`.
   3. Compute `phase_status` — one key per **phase step**: `{phase}` for aspect-agnostic
      phases, `{phase}/{aspect}` for each aspect of an aspect-aware phase — all `"pending"`.
   4. Write the file. Persist **decisions**, not derived data: anything deterministic from
      disk (the merged `EFFECTIVE_PROFILE`, injections, convention skills) is recomputed on
      resume, so the file stays small (a few KB) and cheap to update.
      ```json
      {
        "schema_version": 2,
        "task_slug": "{task_slug}",
        "started_at": "{ISO 8601 UTC}",
        "updated_at": "{ISO 8601 UTC — refreshed at every phase boundary}",
        "arguments": "{cleaned $ARGUMENTS}",
        "flags": { "stack": null, "type": null, "workflow": null, "redetect_git_flow": false, "redetect_stack": false, "force_preflight": false },
        "roster": ["sdlc:business-analyst", "sdlc:qa-engineer", "..."],
        "phase_agents": { "{phase_name}": "{qualified_agent}", "...": "..." },
        "stack": { "primary": "laravel", "active_profiles": { "backend": "laravel", "frontend": "inertia-vue", "database": "laravel" }, "profile_source": "laravel-plugin/stack.md", "forced": false },
        "git_flow": { "...the same object Step 5 writes to _telemetry.json — model, task_type, branch_name, base_branch, pr_base_branch, requires_back_merge, diff_scope, ..." : "..." },
        "narrative_language": "uk",
        "headless_mode": false,
        "active_workflow": "default",
        "workflow_selection_reason": "fallback",
        "max_total_cost_usd": null,
        "resolved_phases": [["business_analysis"], ["development"], ["database"], ["qa"], ["security"], ["documentation"]],
        "skip_rules_applied": [],
        "phase_status": { "business_analysis": "pending", "development/backend": "pending", "development/frontend": "pending", "database": "pending", "qa": "pending", "security": "pending", "documentation": "pending" },
        "cost_cap_overridden": false,
        "aborted_at_phase": null,
        "resume_count": 0
      }
      ```
      `resolved_phases` is a list of **groups** (each a list of phase names); today every group has
      one member — the shape is chosen so parallel groups can be expressed without a schema change.
      `roster`, `phase_agents`, `task_slug`, `started_at` keep their v1 meaning: `enforce-agent-model.sh`
      reads exactly those and judges freshness by `updated_at // started_at`.
   5. This file is project-local (not `~/.claude/`) so `/sdlc:batch`'s parallel
      worktree-isolated pipelines each get their own state file without colliding.
   6. Any later update to this file (3b-special, 3d-0, Step 5) is a targeted `Edit` of the
      changed keys plus `updated_at` — never a full rewrite, and never from a hook: hooks only
      *read* it. The orchestrator is the single writer.

This directory is the **single source of truth** for inter-phase communication. Agents read prior phase outputs from here, not from your context window.

### Step 3 — Execute each group

`CONTEXT.resolved_phases` is a list of **groups** (RESOLVER Step 2). A group is one pipeline
step: `Phase {N}/{total}` numbers groups, and every member of a group shares that `N`. Most
groups have one member and behave exactly as a sequential phase always did.

Iterate groups in order. Within a group, first classify each member as **aspect-agnostic** or
**aspect-aware**:

- **Aspect-agnostic phases** (business_analysis, security, documentation): one agent runs, taking all prior phase outputs as context. Single execution per phase.
- **Aspect-aware phases** (development; qa on multi-profile runs per the Step 1a qa fan-out rule): fan-out — one agent per relevant aspect. Canonical order: `database → backend → frontend → testing` (matches typical dependency direction; backend depends on database; frontend depends on backend's API contract). The development phase always fans out **sequentially** unless the experimental `aspect_execution: parallel-implement` applies — see 3b-parallel-aspects.

**3a-group. Assemble the group's dispatch list.** Expand every member into its concrete
dispatches (one per aspect for an aspect-aware member, one otherwise). A member whose
aspect-aware fan-out yields no agent at all is dropped from the group with a note in telemetry;
if that empties the group, skip the group and move on.

Every dispatch in the list carries the same `{N}`, its own `{phase_name}`, and its own
`{aspect}`.

**3a-pre. MUST PRINT VERBATIM** at the start of a group, before dispatching:

- Single member, aspect-agnostic — print nothing here; 3b-2's per-dispatch line is the banner.
- Single member, aspect-aware:

  ```
  ▶ Phase {N}/{total}: {phase_name} — fan-out across {count} aspects
  ```

- Two or more members:

  ```
  ▶ Phase {N}/{total}: {member names joined by " ∥ "} — {count} dispatches in parallel
  ```

**3b. For each dispatch in the group's list**, build the prompt (3b-1), print its label (3b-2)
and resolve its model (3b-3). Build **every** dispatch in the group before spawning any of
them.

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
task_type: {CONTEXT.task_type}
branch: {CONTEXT.branch_name}
base_branch: {CONTEXT.base_branch}
pr_base_branch: {CONTEXT.pr_base_branch}
requires_back_merge: {CONTEXT.requires_back_merge or "none"}
detailed_output_path: docs/plans/{task_slug}/0X-{phase}{-aspect_suffix}.md
inputs_available:
  - docs/plans/{task_slug}/_brief.md
  - {list of prior phase output files, including earlier-aspect outputs
    from the SAME phase — both the implementation report and the plan
    (e.g. 02-development-database.md, then 02-development-plan-backend.md
    and 02-development-backend.md, before running development-frontend).}
phase_command_overrides:
  {phase_command_overrides[phase] as a key:value list, or "none"}
availability_flags:
  {csv of CONTEXT.{plugin}_unavailable=true flags, or "all dependencies available"}
project_shape:
  {stack.project_shape from the run plan (or `scripts/detect-stack.sh --shape-only`) as a key:value list — package_manager, runner_prefix, test_command, lint_command, typecheck_command, format_command, test_framework, coverage_available, ci, monorepo — or "unknown"}
{IF aspect-aware:}
aspect_constraint: |
  Your scope is limited to '{aspect}'. Do NOT touch other aspects' files
  (other aspect-agents will run before/after you and handle those).
```

The two `===` delimiters are part of the prompt — agents are instructed (via their `.md` body) to read CONTEXT keys from this trailer.

**3b-2. MUST PRINT VERBATIM** before spawning each agent:

```
▶ {dispatch_label} → {agent_name} ({model_tier})
```

where `{dispatch_label}` is **exactly the string passed as `description` in 3c**:

```
Phase {N}/{total}: {phase_name}{aspect_marker}{pass_marker}
  aspect_marker = " — {aspect}"          (aspect-aware dispatches only)
  pass_marker   = " [pass:plan]" | " [pass:implement]" | " [pass:fix]" | " [pass:verify]"
                                         (development passes; security fix / QA verify sub-passes)
```

Examples:
- Aspect-agnostic: `▶ Phase 1/6: business_analysis → business-analyst (opus)`
- Development, plan pass: `▶ Phase 2/6: development — backend [pass:plan] → laravel-architect (opus)`
- Development, implement pass: `▶ Phase 2/6: development — backend [pass:implement] → laravel-architect (sonnet)`
- Aspect-aware: `▶ Phase 3/6: qa — frontend → qa-engineer (sonnet)`

Print and `description` carry the identical label: the label is what the telemetry hooks
(`hooks/dispatch-log.sh`) parse to attribute measured usage to a phase, aspect and pass, and what
`enforce-agent-model.sh` parses to pick the frontmatter field. This is a contract with the user
and with the hooks. Do not skip, do not paraphrase.

**3b-3. Resolve model from agent frontmatter** — before spawning, read the agent's `.md` file (`plugins/**/agents/{agent_name}.md`) and resolve `{model_tier}`:

- **Planning pass of the development phase** (Pass 1 in 3b-special): use `model_plan:` if present, otherwise fall back to `model:`.
- **Every other invocation** (including the development implementation pass): use `model:`.

This resolved tier is what you print in 3b-2 and pass to `Agent()` in 3c. Pass the tier **as-is** (`opus`, `sonnet`, `haiku`, or `fable`) — the Agent tool's `model` parameter accepts only these short aliases; a full model ID (e.g. `claude-haiku-4-5-20251001`) fails schema validation and the dispatch silently falls back to the session model. (Agent *frontmatter* does accept full IDs and `inherit`; the dispatch parameter does not. Do not confuse the two.) If the file is missing or `model:` is absent, warn inline and fall back to `sonnet`.

> **What this step actually controls.** Claude Code resolves a subagent's model in the order
> per-invocation `model` parameter → agent `model:` frontmatter → `CLAUDE_CODE_SUBAGENT_MODEL`
> → session model. This step writes the first, the PreToolUse hook writes it too, and the
> frontmatter is the second — so `CLAUDE_CODE_SUBAGENT_MODEL` alone never overrides either.
> The one override that does is `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` (v2.1.257+): it makes
> Claude Code ignore both the parameter and the frontmatter, and every phase runs on
> `CLAUDE_CODE_SUBAGENT_MODEL` (or the session model if that is unset). An organization
> `availableModels` allowlist can likewise skip a value. `/sdlc:doctor` reports both — run it
> before trusting a cost estimate. (Before v2.1.251 the variable came first; that is the
> behaviour this note used to describe.)

**3b-special. Development phase two-pass execution**

The development phase runs in TWO passes with a user approval gate between them. This applies to every agent invocation within the development phase (each aspect in an aspect-aware fan-out runs its own two-pass cycle).

The two passes have different economics and therefore **different model tiers**. Planning is small-output, high-leverage work whose result passes a human gate and then governs the whole implementation; implementation is high-volume execution against an approved spec. Pass 1 therefore resolves `model_plan:` (typically `opus`) and Pass 2 resolves `model:` (typically `sonnet`). Both passes must carry a pass marker in `description` so the PreToolUse hook enforces the right one — see 3c.

**Pass 1 — Planning:**

1. Use base prompt `development_plan` (instead of `development`).
2. Resolve the model via `model_plan:` per 3b-3. Set `description` to `Phase {N}/{total}: {phase_name}{aspect_marker} [pass:plan]`.
3. Spawn the agent. It reads the BA spec + codebase and writes an implementation plan to `docs/plans/{task_slug}/02-development-plan{-aspect_suffix}.md`.
4. Agent returns a plan summary. Set `phase_status["development/{aspect}"] = "planned"` (+ `updated_at`) in the state file — a resumed session then re-enters the gate below instead of re-planning.

**Approval gate:**

1. Print the plan summary to the user.
2. 🚨 **MUST PRINT VERBATIM:**
   ```
   📋 Implementation plan ready for {phase_name}{IF aspect-aware: " — " + aspect}.
      Review: docs/plans/{task_slug}/02-development-plan{-aspect_suffix}.md
   ```
3. Ask the user: **approve** / **request changes** / **abort**.
   - If **approve**: set `phase_status["development/{aspect}"] = "approved"` in the state file, then proceed to Pass 2.
   - If **request changes**: re-dispatch Pass 1 with user feedback appended to the prompt. Repeat until approved or aborted.
   - If **abort**: mark this aspect (or entire development phase if aspect-agnostic) as skipped in telemetry and `phase_status`. Continue to the next phase.

**Pass 2 — Implementation:**

1. Use base prompt `development_implement` (instead of `development`).
2. Resolve the model via `model:` per 3b-3. Set `description` to `Phase {N}/{total}: {phase_name}{aspect_marker} [pass:implement]`.
3. Spawn the agent. It reads the approved plan and implements the code.
4. Agent writes the implementation report to `docs/plans/{task_slug}/02-development{-aspect_suffix}.md`.
5. Standard validation (3e) applies: output must list files changed.

Re-dispatches of Pass 1 after "request changes" keep the `[pass:plan]` marker — they are still planning work.

For aspect-aware fan-out, the canonical order remains: `database → backend → frontend → testing`. Each aspect completes both passes before the next aspect begins (the plan for backend may depend on what database-aspect implemented).

**3b-parallel-aspects. Experimental: parallel implementation passes.** Applies only when
`EFFECTIVE_PROFILE.aspect_execution == "parallel-implement"` (default `sequential`, Step 1b).
Then read `${CLAUDE_SKILL_DIR}/references/parallel-aspects.md` once before the first plan pass
and follow it — plan passes, the single approval gate and the invariants checked before any
implementation pass runs concurrently.

**3c. Spawn the agent** via the `Agent` tool with `subagent_type` and the model resolved in 3b-3:

```
Agent({
  subagent_type: "{plugin_name}:{agent_from_profile}",
  model: "{model_tier_resolved_in_3b-3}",   // short alias only: "opus" | "sonnet" | "haiku" | "fable"
  description: "Phase {N}/{total}: {phase_name}{aspect_marker}{pass_marker}",   // = the 3b-2 label
  prompt: <the prompt built in 3b>
})
```

**Always qualify `subagent_type`** with the name of the plugin that declared the agent
in its `stack.md` (e.g. `sdlc:qa-engineer`, `laravel-plugin:laravel-architect`) — the
bare form (`qa-engineer`, `developer`) collides by name with any project-local
`.claude/agents/{name}.md` the project happens to ship. `enforce-agent-model.sh` already
strips the prefix before resolving the `.md` file, so this is purely additive.

**Never retry with the bare name if the qualified dispatch errors.** The hook only
treats an *unqualified* `subagent_type` as eligible for the local-agent probe — a
qualified one is, by construction, never a project-local agent, so it skips that check
entirely. Falling back to the bare name on error reopens exactly the collision this fix
closes: in a project with `.claude/agents/developer.md`, a bare `developer` retry
resolves to that local file while `roster_contains`'s bare-suffix match
(`"sdlc:developer".endswith(":developer")`) makes it look roster-legitimate, silently
running the wrong agent. If a qualified dispatch errors (rare — e.g. an older Claude
Code build without `plugin:agent` support), treat it as a phase failure per *Failure
modes and recovery* (retry / skip / abort with the user) rather than papering over it
with an unqualified retry.

`description` is not decoration — the hooks only see `tool_input`, so it is the sole
channel telling `enforce-agent-model.sh` (a) which frontmatter field to enforce and
(b) which phase this dispatch belongs to, for its off-roster deny message, and telling
`dispatch-log.sh` which phase / aspect / pass a measured usage row belongs to. It **MUST**
be exactly the 3b-2 label `Phase {N}/{total}: {phase_name}{aspect_marker}{pass_marker}` — a
free-form description (e.g. "Regression test verification for X") breaks all three: the
model rewrite, the deny message, and the telemetry attribution (the row is then recorded
as a *nested* dispatch, not a phase). `{aspect_marker}` is ` — {aspect}` on aspect-aware
dispatches and empty otherwise. `{pass_marker}` is empty for every phase except
development, where it is ` [pass:plan]` or ` [pass:implement]` per 3b-special (` [pass:fix]`
and ` [pass:verify]` are reserved for the security fix / QA verify sub-passes). Drop the
marker on a planning pass and the hook rewrites the model back to `model:`, silently
undoing the tier split.

**3c-group. Spawning a parallel group.** When the group has more than one dispatch, issue
**all** of its `Agent` calls in a **single assistant message**. Several `Agent` calls in one
message run concurrently in the foreground and share the working tree; issued in separate
messages they run one after another, and the group silently degrades to sequential execution
at full cost.

- Never `run_in_background` for a phase agent. Parallel here means concurrent **foreground**
  calls in one message — the orchestrator still blocks until every member returns. (The
  `batch-pipeline` skill's background dispatch is a different mechanism for a different job and
  is unaffected by this rule.)
- Each member keeps its own `description` label, its own model tier, and its own telemetry row.
  The hooks never see the group: they parse `description`, which carries phase, aspect and pass
  per dispatch. Two members sharing one `{N}` is expected and harmless.
- A member's own aspect fan-out (QA across aspects, for instance) is part of the same message —
  one group, one message, however many dispatches it expands to.
- Results arrive together. Process them in the group's declared member order, not in the order
  they happen to complete, so a run is reproducible in its output.

**3d. Save the COMPACT summary** returned by the agent to `CONTEXT.{phase}_output`. The `SubagentStop` hook `hooks/phase-output-guard.sh` has already checked, before the agent was allowed to stop, that the deliverable file `docs/plans/{task_slug}/0X-{phase}.md` exists and that the compact summary carries its required lines (3e); on a miss it returned `decision: block` and the agent finished the work in place. So do **not** `Glob` for the file here. Only if the summary still lacks the file or the lines (the hook blocks at most once, and never without `jq`) ask the agent again to write it before proceeding.

**3d-0. Update the state file.** Once the phase step is settled — after 3e passes, or the user
chose *skip* / *abort* for it — `Edit` `.claude/.sdlc-run-active.json`: set
`phase_status["{phase}"]` (or `"{phase}/{aspect}"`) to `completed` / `failed` / `skipped` /
`skipped-cost-cap`, and `updated_at` to now. Two keys, one targeted edit, nothing else. This is
the checkpoint Step R resumes from and the heartbeat that keeps the hooks' 6h freshness window
open on a long run; skipping it turns a later crash into a full re-run.

**3d-1. Capture per-dispatch telemetry (measured).** The Agent tool result carries **no** usage data, so nothing in this step reads token counts from the result envelope. Usage is measured by this plugin's hooks while the Step 2 run marker is fresh: `hooks/dispatch-log.sh` records every `Agent` dispatch (`PreToolUse`) and its assigned `agent_id` (`SubagentStart`), and `hooks/subagent-usage.sh` (`SubagentStop`) sums the finished subagent's own transcript — deduplicated by `message.id` — and prices it from `references/pricing.json`. All three append rows to `docs/plans/{task_slug}/_usage.jsonl`; the orchestrator never writes that file.

Right after the `Agent` call returns, the `PostToolUse(Agent)` hook `hooks/agent-result-context.sh` injects the record for **this** dispatch as context (`SDLC telemetry for {description}: usage_source=… model_id=… input=… output=… turns=… cost_usd=…`, plus a `Running total:` line and, when it applies, `compact_handoff_violation`). Read the entry from there; do **not** run `usage-report.sh` yourself. Only when no such context arrived (hook disabled, no `jq`) run the one Bash call below and take the record with the same bare `agent_type`, same `phase` / `aspect` / `pass` as the 3b-2 label and the latest `started_at`:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/usage-report.sh" {task_slug} --project-root .
```

(dev checkout fallback: `plugins/sdlc/scripts/usage-report.sh`). `scripts/finalize-telemetry.sh`
builds `phases[]` from the usage log at Step 5. The per-field mapping — needed only to build
telemetry by hand when `jq` is missing — is in `${CLAUDE_SKILL_DIR}/references/telemetry.md`.

**3d-2. QA-specific telemetry** — when running the `qa` phase, parse the agent's compact summary for the lines `ITERATIONS_USED: N` (max 3, hard cap from the agent prompt) and `STATUS: complete | incomplete-blocked`. Record:

- `qa_iterations_used: N`
- `qa_status: "completed"` when STATUS is `complete`, or `"capped"` when STATUS is `incomplete-blocked`.

Both fields go into the QA phase entry of `phases[]`.

**3d-3. Enforce the workflow cost cap.** If `CONTEXT.max_total_cost_usd` is `null`, skip this step.

The `PostToolUse(Agent)` hook reads `max_total_cost_usd` from the state file, keeps the running total from measured rows, and prints the 💸 block below as context the moment the cap is exceeded — your job then is only to ask **continue** / **stop here** and record the outcome. Sum the costs yourself only when the hook's context did not arrive.

Otherwise sum `cost_usd` across `phases[]` so far (measured rows where available — this is exactly why 3d-1 prefers the hook-measured value over an estimate; a cap compared against guesses is not a guard). If the running total exceeds the cap, **MUST PRINT VERBATIM**:

```
💸 Cost cap exceeded for workflow '{active_workflow}'
   Cap: ${max_total_cost_usd}   Spent so far: ${running_total} (through phase {phase_name})
   Remaining phases: {list}
```

Then ask the user: **continue** / **stop here**. On *stop*, skip all remaining phases, mark them `status: "skipped-cost-cap"` in telemetry, and go to Step 4 — the work already done is kept, not rolled back. On *continue*, set `CONTEXT.max_total_cost_usd = null` so the prompt does not repeat every phase, and record `cost_cap_overridden: true` in telemetry.

Never abort silently: a cap is a runaway guard, and a half-finished pipeline that vanishes without a word is worse than an expensive one. The check runs *after* a phase completes because per-phase cost is only known then — a cap cannot prevent the phase that breaches it, only the ones after.

**3d-security. Security fix pass and QA verify rerun.** `security-analyst` is report-only, so
its Critical and High findings are applied afterwards, by the agent that wrote the code. Run
this immediately after the group containing the `security` member has been validated (3e), and
before moving to the next group.

Decide from two inputs: whether each member of the group **succeeded**, and the
`ISSUES_FOUND: critical=N high=N` counts from the security compact summary.

| Security member | `critical + high` | QA member | Fix pass | QA verify |
|---|---|---|---|---|
| succeeded | 0 | any | no | no |
| succeeded | > 0 | succeeded or absent | **yes** | yes, only if `FIXES_APPLIED` is non-empty |
| succeeded | > 0 | failed / skipped | **yes** | **no** — there is no passing baseline to re-verify against |
| failed / skipped | unknown | any | **no** | **no** |

A failed security review yields no trustworthy finding list, so nothing is fixed on its basis.
That is the point of the first-column rule: the fix pass exists to apply a review, not to guess
at one.

**The fix pass.** One dispatch to the development-phase architect for the `backend` aspect (or
the sole aspect when the run has one):

- `description`: `Phase {N}/{total}: security [pass:fix]` — `{N}` is the security member's own
  group number. `[pass:fix]` resolves `model:`, not `model_plan:`.
- Input: `docs/plans/{task_slug}/04-security.md`, plus the must-fix list from the compact
  summary.
- Contract, stated in the prompt: apply exactly the prescribed fixes; minimal diff; no
  refactoring, no reformatting, no new dependencies, no changes outside the files named in the
  findings. A finding the architect believes is a false positive is **reported, not silently
  skipped**.
- Returns `FIXES_APPLIED: [file:line, …]` and `NOT_FIXED: [finding → reason]`.

**The QA verify rerun.** Only when the fix pass reported at least one applied fix:

- `description`: `Phase {N}/{total}: qa [pass:verify]`.
- Contract: run the existing suite only. Write no new tests, change no test, change no source.
  Report pass/fail counts and the failing test names.
- A failure here is a regression introduced by the fix pass — surface it to the user with the
  normal retry / skip / abort prompt rather than attempting another fix automatically.

Both sub-passes get their own telemetry entries (`security_fix_pass`, `qa_verify_rerun` in the
Step 5 trailer) and their own `phase_status` keys, `security/fix` and `qa/verify`.

**3e. Validate phase output:**
- BA phase: must contain acceptance criteria or scope bullets.
- Development phase: must list files changed.
- QA phase: must report pass/fail counts.
- Security phase: must report severity counts.
- Docs phase: must contain a PR URL or commit hash.

**Truncated output (`maxTurns` reached).** Every agent carries a `maxTurns` cap in its
frontmatter (architects 120, specialists and QA 60, BA and security 80, docs 30). When an
agent hits it, the Agent tool returns whatever it had produced, so the compact summary is
usually missing its closing fields. Treat that as a validation failure, not as success:

- **QA phase** — record `incomplete-blocked` for the member and do not report a pass/fail
  count you did not receive.
- **Any other phase** — apply the normal member-failure prompt below (retry / skip / abort).

A retry after a `maxTurns` hit must narrow the scope (one aspect, or the failing subset)
rather than re-issuing the same prompt — the cap will be reached again otherwise.

**Post-implement check findings.** A stack's `post-implement-check.sh` hook runs its
typecheck or linter once after each architect finishes; the findings arrive in the
`PostToolUse(Agent)` context right after the `SDLC telemetry` line for that dispatch. Treat that as a **retry hint for the implement pass**, not as a verdict:
on a parallel-aspect run some diagnostics come from a peer's unfinished work. Re-dispatch
the aspect with the relevant lines appended to the prompt; never edit the code yourself,
and never fail a member on diagnostics outside its own aspect's paths.

**Security fact-forcing.** `hooks/phase-output-guard.sh` applies this rule first, at `SubagentStop`, and blocks the agent in place with the entry points named. Apply it here only if the summary still violates it. **Security fact-forcing.** Reject a security member that returns `STATUS: clean` while
both `ENTRY_POINTS_CHECKED` and `CALLERS_TRACED` are empty. "Nothing found" is a
conclusion; with no entry point read and no call site followed it is an absence of
analysis wearing the same words. Re-dispatch once, naming the changed files' entry
points explicitly.

If validation fails, **do not proceed** — ask the user how to handle (retry, skip, abort).

**Failure inside a parallel group is per member.** Validate each member's output separately and
apply retry / skip / abort to **that member only** — a failing security review does not
invalidate a QA pass that returned cleanly, and re-dispatching the whole group would pay for
the healthy member twice. Ask once per failed member, in the group's declared member order.

The cost cap (3d-3) is evaluated **once per group**, after every member has returned. A cap
cannot prevent the step that breaches it, and members of a group are dispatched together, so
checking mid-group is not possible even in principle.


### Step 4 — Run post-pipeline checks

For each command in `EFFECTIVE_PROFILE.post_pipeline_checks` (already merged with `sdlc.local.yaml` in Step 1b), execute via `Bash`:

```bash
{command}
```

If the array is empty (e.g., user disabled checks via `post_pipeline_checks: []` in `sdlc.local.yaml`) — print `Post-pipeline checks: skipped (empty list).` and proceed to Step 5.

Capture exit code and last 30 lines of output. Save to `docs/plans/{task_slug}/05-post-checks.md`, and end that file with a fenced block tagged `json post-checks` holding `[{"command": "…", "exit_code": N}, …]` — `scripts/finalize-telemetry.sh` reads it for the `post_pipeline_checks` telemetry field.

If any command fails:
- Print the failure summary to the user.
- **If `post_check_fix_attempts` is `0`** (the default, from `sdlc.local.yaml` or the
  `CLAUDE_PLUGIN_OPTION_POST_CHECK_FIX_ATTEMPTS` plugin option): do **not** iterate. Report and
  proceed to Step 5. The orchestrator does not implement fixes; that is a follow-up run's job.
- **If it is `1`**: dispatch exactly one fix pass, then stop regardless of the outcome.

**The post-check fix pass** (only when `post_check_fix_attempts == 1`):

- One dispatch to the development-phase architect for the `backend` aspect, or the sole aspect
  on a single-aspect run.
- `description`: `Phase {X}/{Y}: post_checks [pass:fix]` — `{X}/{Y}` is the last group's
  numbering. `[pass:fix]` resolves `model:`.
- Input: `docs/plans/{task_slug}/05-post-checks.md`, plus the failing command and its captured
  output.
- Contract, stated in the prompt: fix only what makes the failing commands pass. Minimal diff,
  no refactoring, no new dependencies, no changes to the checks themselves. A check that is
  wrong about the code is **reported, not edited** — silently rewriting a failing check to pass
  is the one outcome this pass must never produce.
- After it returns, re-run **only the commands that failed**, once. Record both results.
- Whatever happens, there is no second attempt. The cap is 1 by design: an agent that cannot
  fix a lint failure in one pass is not going to fix it in three, and the retry loop is the
  single most expensive failure mode this pipeline has.

Record in telemetry: `post_check_fix_attempted` (bool), `post_check_fix_resolved` (bool —
whether the re-run passed), and the fix pass's own `phases[]` entry with `pass: "fix"`.

### Step 5 — Write telemetry and final summary

Run one Bash call (listed in the Bash allowlist above):

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/finalize-telemetry.sh" {task_slug} --project-root . --extra '{"pr_url": "…", "model_enforcement_corrections": N, "qa": {"iterations_used": N, "status": "completed|capped"}}'
```

(dev checkout fallback: `plugins/sdlc/scripts/finalize-telemetry.sh`; add `--aborted-at-phase {name}` on an aborted run.) It assembles `_telemetry.json` from the usage log, the state file, the deps-preflight cache and `05-post-checks.md`, computes every aggregate below, and prints the final summary block — echo that block to the user verbatim. `--extra` is deep-merged last and is the only place for values the scripts cannot see (the PR URL, the 3d-2 QA counters, enforcement corrections). Build the file by hand, per `${CLAUDE_SKILL_DIR}/references/telemetry.md`, only when `jq` is unavailable.


When `CONTEXT.requires_back_merge` is set (a `hotfix` or `release` whose PR targets `main`),
append this line — the obligation is real and the pipeline does not discharge it:

```
↩️  After the PR merges, back-merge {pr_base_branch} into {requires_back_merge} — this
    pipeline does not open that second PR.
```


**Delete the state file** (`.claude/.sdlc-run-active.json`, written in Step 2) once
telemetry is written and the summary is printed — a pipeline is no longer "active" once
the operator has the final report, its off-roster-agent deny rule must not outlive the run it
was scoped to, and a leftover file would make the next `/sdlc:start` offer to resume a run
that already finished.

---

## Base prompts per phase

These are the canonical prompts. Stack profiles inject additional text via `phase_prompts_injection`.

### business_analysis

```
Verify and consolidate requirements for this feature: $ARGUMENTS

Step 0: If mattpocock-skills is available (no mattpocock-skills_unavailable flag),
invoke mattpocock-skills:grill-me to relentlessly interview the user to sharpen the spec.

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
- **Contract for frontend** — a section under exactly that heading when your aspect is
  `backend` (see your agent file's "Plan additions"). The frontend aspect plans against
  this shape, and the approval gate reviews it, so it is fixed here rather than
  discovered from the implementation. If the change exposes no frontend surface, write
  the heading with the single line `No frontend contract`.

Follow project conventions found in CLAUDE.md and the active stack profile.

Write the plan to: docs/plans/{task_slug}/02-development-plan.md

RETURN ONLY a COMPACT summary (≤2K tokens):
- Planned files to create/modify (list)
- Contract for frontend: [one line per endpoint/prop shape, or "none"]
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

You are report-only — you have no Edit tool. Do not change code.
For every Critical and High finding, prescribe the exact change instead:
file, line, and what to do there. A separate fix pass by the
development-phase architect applies them.

Write detailed security report to: docs/plans/{task_slug}/04-security.md

RETURN ONLY a COMPACT summary (≤2K tokens):
- Issues found (severity breakdown: Critical / High / Medium / Low)
- Must-fix list (file:line per Critical/High finding)
- Outstanding recommendations
- ENTRY_POINTS_CHECKED and CALLERS_TRACED (see your agent file)
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

Target the base branch from the per-call CONTEXT trailer: pass `--base {pr_base_branch}`
(or the MCP `base` parameter). Never rely on the repository default — on a git-flow project
that silently retargets the PR from `develop` to `main`.

If `requires_back_merge` in the trailer is not "none", state the outstanding back-merge in
the PR description.

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


## Failure modes and recovery

| Failure | Behavior |
|---|---|
| `stack.md` parse error | Skip that profile, log warning, continue with others. |
| No matching profile | Fall back to vanilla. |
| Agent does not exist (referenced in profile) | Halt. Print error: `Agent '{name}' referenced by {profile} not installed`. |
| Agent fails (exception in subagent) | Mark phase as failed in telemetry. Ask user: retry / skip / abort. |
| Post-pipeline check fails | Report; do not retry. The user decides next steps. |
| `mcp__skills__list_skills` unavailable | Use FS fallback: check `~/.claude/plugins/cache/*/{plugin}/*/skills/{skill}/SKILL.md` exists. |
| Token budget exceeded | Halt at next phase boundary. Report partial telemetry. |
| Pipeline aborted (Halt above, or user chooses **abort** at the Step 3b-special approval gate) | Write partial telemetry (`aborted_at_phase`), then delete the state file (`.claude/.sdlc-run-active.json`, Step 2) before stopping, same as the Step 5 cleanup — otherwise its off-roster-agent deny rule stays active for up to 6h after a run that no longer exists and the next `/sdlc:start` offers to resume a run the user deliberately abandoned. |
| Session lost mid-run (compaction, crash, closed terminal) | Nothing to do in the moment — the state file already holds every decision through the last completed phase step. On the next `startup`/`resume`/`compact`, `hooks/session-start-run-context.sh` injects a one-line reminder (task, branch, next unfinished step) while the state file is fresh. The user runs `/sdlc:start --resume` (Step R); completed phases are not re-paid. |
| `--resume` on a different branch than `git_flow.branch_name` | HALT (Step R-1). Tell the user which branch to check out. Never resume onto the wrong branch. |
| `--resume` with a v1 marker (no `schema_version`) | Cannot resume — offer start fresh / abort (Step R). |
