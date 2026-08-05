# Git Flow — Algorithm Reference

This document specifies how the pipeline orchestrator determines the project's branching
model, classifies the task type, and sets up the working branch. Referenced from
`pipeline-orchestrator/SKILL.md` **Step 0b-git**, and reused in diagnostic mode by
`/sdlc:doctor`.

Everything here is **read-only** except the two mutating commands named in Step F
(`git fetch` of a missing base ref, `git checkout -b`), which run only after the Step F gate
resolves.

---

## Step A: Resolution order

Three layers, first hit wins:

1. **Explicit config** — the `git:` block in `<project>/.claude/sdlc.local.yaml`.
   Authoritative; short-circuits detection entirely.
2. **Detection cache** — `<project>/.claude/.sdlc-git-flow.json`, when it is trusted
   (Step G).
3. **Live detection** — `detect-git-flow.sh` (topology) + the documented-convention scan
   (Step B).

`--redetect-git-flow` in `$ARGUMENTS` skips layers 2 and re-runs 3, then rewrites the cache.
It does **not** override layer 1: an explicit config is a decision, not a guess, and a flag
named "redetect" must not silently discard it.

### A-1. Read the explicit config

`Read` `<project>/.claude/sdlc.local.yaml`. If absent, or it has no `git:` key, continue to
A-2. If present, extract the `git:` block:

```yaml
git:
  model: git-flow            # git-flow | github-flow | custom
  default_branch: main
  develop_branch: develop    # required when model: git-flow
  auto_create_branch: true   # false → never create a branch, only report
  naming:
    separator: "/"
    word_separator: "-"
    ticket_pattern: "^[A-Z][A-Z0-9]{1,9}-[0-9]+$"   # or null
    ticket_position: after-prefix                   # after-prefix | leading
    max_length: 60
  type_policy:               # partial override — unlisted types keep the Step D default
    fix:    { prefix: fix,    from: develop, pr_base: develop }
    bugfix: { prefix: bugfix, from: main,    pr_base: main }
```

Every key is optional except `model`. Merge semantics: a present key **replaces** the
detected value; absent keys fall through to detection. So `git: { model: git-flow }` alone is
legal and means "the model is settled, learn the rest from the repo".

Set `CONTEXT.git_flow_source = "config"` and, for a fully-specified block, skip to Step C.
This file is parsed again in full at Step 1b; `git` is a recognized key there so the later
parse does not warn about it.

### A-2. Read the cache

Per Step G. On a trusted hit, set `CONTEXT.git_flow_source = "cache"` and skip to Step C.

### A-3. Run detection

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/detect-git-flow.sh"
```

If `${CLAUDE_PLUGIN_ROOT}` is unset (development checkout), fall back to
`<repo>/plugins/sdlc/scripts/detect-git-flow.sh` — the same two-path lookup
`commands/doctor.md` uses for its cost-baseline template. If neither path exists, warn once
and treat the model as `github-flow` off the default branch: a missing helper script must
degrade the feature, not abort the pipeline.

The script emits one JSON object and **never exits non-zero**. Parse:

| Field | Use |
|---|---|
| `model` | `git-flow` \| `github-flow` \| `unknown` |
| `confidence` | `high` \| `medium` \| `low` |
| `sources[]` | provenance strings for the Step F print |
| `default_branch`, `develop_branch`, `release_branches[]` | base-branch resolution (Step D) |
| `prefix_style` | `conventional` \| `custom` \| `none` |
| `prefix_histogram` | observed prefixes with counts ≥2 |
| `naming.*` | separator, word separator, ticket pattern/position; `observed_max_length` is diagnostic only — never a limit (see Step E) |
| `current_branch`, `current_branch_is_base`, `dirty_file_count` | Step F gate |

`model: "unknown"` (no commits, no branches, not a repo) → treat as `github-flow`, confidence
`low`, and never create a branch: there is no base to branch from.

---

## Step B: Documented-convention scan

Topology tells you what the team *did*; a rules file tells you what the team *agreed*. An
explicitly documented convention **outranks** the histogram — this is the "врахувати правила
проєкту" requirement, and it is what makes the feature work on a repo whose history predates
its own conventions.

`Glob`/`Read` these, in this order (first file with a usable statement wins):

1. `<project>/CLAUDE.md`, `<project>/.claude/CLAUDE.md`
2. `<project>/.claude/rules/*.md`
3. `<project>/AGENTS.md`, `<project>/GEMINI.md`
4. `<project>/CONTRIBUTING.md`
5. `<project>/.cursorrules`, `<project>/.cursor/rules/*`
6. `<project>/.github/pull_request_template.md`, `<project>/.github/PULL_REQUEST_TEMPLATE.md`

`Grep` each for `-i` matches on `branch`, `git.flow`, `git-flow`, `develop`, `prefix`, or a
literal `feature/`. Read the surrounding lines of any hit.

A hit counts as a **statement** only when it names either a model ("we use git-flow",
"trunk-based development", "branch off develop") or a naming rule (`feature/<ticket>-<slug>`,
"branches must start with one of feature|fix|chore"). A passing mention ("fixed a branch
prediction bug") is not a statement — do not let it flip the model.

On a statement:

- Override the corresponding fields from Step A-3.
- Set `confidence = "high"` and prepend `rules:<relative-path>` to `sources[]`.
- When the statement contradicts topology (rules say git-flow, no `develop` branch exists),
  keep the rules' model but record `topology_conflict: "<one line>"` and surface it in the
  Step F print. Do **not** silently pick either side — a repo mid-migration is exactly when
  the operator needs to see both facts.

---

## Step C: Task-type classification

Produces `CONTEXT.task_type` and `CONTEXT.task_type_confidence`. Deterministic and
precedence-ordered — never "ask the model what it thinks the task is".

### C-1. Explicit flag

`--type=NAME` in `$ARGUMENTS`, where NAME ∈ {`feature`, `fix`, `bugfix`, `hotfix`, `release`,
`refactor`, `docs`, `chore`}. Strip it from the description. Confidence `high`, source
`flag`. An unrecognized value → warn, list the valid set, and fall through to C-2.

### C-2. Keyword table

Match case-insensitively against `$ARGUMENTS` (the cleaned description). The **authoritative
source for task typing** is the data file `references/task-type-patterns.json` — Read and
compile it, do not re-derive patterns from prose. Each entry there is a complete, ready-to-use
ECMAScript regex source string; compile with the file's `flags` (`iu`) and test directly, no
assembly step.

**`\b` is banned from this table and from that file.** ECMAScript `\w` is `[A-Za-z0-9_]`, so
`\b` never asserts a boundary next to a Cyrillic character — with or without the `u` flag. A
pattern like `\bрефактор\b` silently never matches anything, in any input, forever; that bug
shipped invisibly for months because nothing exercises Ukrainian input in CI. Use the
`u`-flag Unicode property escapes documented in the JSON file's `boundary` block instead:
`(?<![\p{L}\p{N}])` on the left, `(?![\p{L}\p{N}])` on the right — applied selectively, since
Ukrainian inflection means several stems (e.g. `рефактор`, matching рефакторинг/рефакторити)
intentionally omit the right-side assertion. `plugins/sdlc/scripts/test-task-typing.sh` fails
the whole suite if any pattern in the JSON file contains a literal `\b` — treat a failure there
as a regression, not a flaky test.

This table's relationship to recipe matching changed from the original design: workflow
recipes (`workflows/*.yaml`) no longer carry their own `arguments_pattern` — this table is now
the *only* keyword classifier in the pipeline. See `RESOLVER.md` Step 1b for why a second,
narrower keyword check on top of this one used to silently veto a correct classification.

### C-3. Precedence on multiple matches

`hotfix > release > bugfix > fix > refactor > docs > chore > feature`.

Urgency and blast radius win over the verb: "urgently refactor the broken payment fix" is a
`hotfix`, because getting that wrong branches production work off `develop`. When two or more
rows match, set `task_type_confidence = "medium"` and show the runners-up in the Step F gate
so the operator can override with one word.

Single match → `high`. No match → `feature`, confidence `low`.

### C-4. Not consulted

Issue-tracker metadata (Jira issue type via MCP) is deliberately **not** a signal. It adds a
network dependency and a non-deterministic input to a decision that must be reproducible from
`$ARGUMENTS` alone.

---

## Step D: Type → branch policy

### D-1. git-flow

`{DEV}` = the detected `develop_branch`; `{MAIN}` = `default_branch`; `{REL}` = the highest
`release/*` branch when one exists.

| task_type | prefix | branch from | PR base |
|---|---|---|---|
| `feature` | `feature` | `{DEV}` | `{DEV}` |
| `fix` | `fix` | `{DEV}` | `{DEV}` |
| `bugfix` | `bugfix` | `{REL}` else `{MAIN}` | same as "branch from" |
| `hotfix` | `hotfix` | `{REL}` else `{MAIN}` | same as "branch from" |
| `release` | `release` | `{DEV}` | `{MAIN}` |
| `refactor` | `refactor` | `{DEV}` | `{DEV}` |
| `docs` | `docs` | `{DEV}` | `{DEV}` |
| `chore` | `chore` | `{DEV}` | `{DEV}` |

`fix` merges to `develop`; `bugfix` and `hotfix` do not. That asymmetry is the point of the
model — `fix` is ordinary corrective work scheduled with the next release, while `bugfix` and
`hotfix` target something already released or about to be. When `{REL}` exists, the Step F
gate offers it and `{MAIN}` as alternatives; in headless mode, `{MAIN}` wins.

For `release` and `hotfix`, the merge to `{MAIN}` leaves `{DEV}` behind. Record
`CONTEXT.requires_back_merge = "{DEV}"` — the documentation phase writes it into the PR body
and the orchestrator repeats it in the final summary. **Opening the back-merge PR is out of
scope**; the obligation is reported, never silently dropped.

### D-2. github-flow

Every row collapses: branch from `{MAIN}`, PR base `{MAIN}`. Only the prefix varies, and only
when the project uses prefixes at all.

### D-3. custom

Use `type_policy` from the explicit config. For a type the config does not list, fall back to
the D-1 row when `develop_branch` is known, else the D-2 row. If neither the config nor
detection can name a base branch, ask in the Step F gate.

### D-4. Prefix spelling follows the project, not the table

The table's prefix column is a *default*, not a mandate:

1. `prefix_style == "none"` (empty histogram) → **no prefix and no separator**. The branch
   name is the bare slug. Inventing a `feature/` convention for a project that has never used
   one is precisely what "врахувати вже існуючі патерни" forbids.
2. The canonical prefix appears in `prefix_histogram` → use it.
3. It does not, but a synonym does → use the observed one and say so in the gate. Synonym
   sets: {`feature`, `feat`}, {`fix`, `bugfix`, `hotfix`}, {`docs`, `doc`},
   {`chore`, `build`, `ci`}, {`refactor`, `perf`, `style`}. Within
   {`fix`, `bugfix`, `hotfix`}, prefer the exact type first; collapse only when the type's own
   spelling is unobserved.
4. Neither appears, but the histogram is non-empty → use the canonical prefix and note it as
   new to this project.

---

## Step E: Branch-name synthesis

```text
{prefix}{separator}{ticket}{word_separator}{slug}
```

- `slug` — reuse the Step 2 `task_slug` generator (lowercase, alphanumerics + dashes, ≤40
  chars) so the branch and the `docs/plans/{task_slug}/` directory stay recognizably paired.
  Then substitute `naming.word_separator` for `-` if the project uses `_`.
- `ticket` — included **only** when `naming.ticket_pattern` was learned or configured **and**
  a matching key appears in `$ARGUMENTS`. Placed per `ticket_position`
  (`after-prefix` → between prefix and slug; `leading` → before the prefix, which in practice
  means no prefix). Never fabricate a ticket id.
- `prefix`/`separator` — per Step D-4; both empty when `prefix_style == "none"`.
- Truncate the whole name to the length cap, cutting the slug only and never leaving a trailing
  separator. **The cap is `naming.max_length` from explicit config, or 60 when there is no
  config.** The detector's `naming.observed_max_length` is never used as a cap — it is the
  longest name already in the repo, reported for diagnostics only. Deriving a limit from it
  would be a footgun: a repo whose longest branch happens to be `fix/typo` would truncate every
  future name to 8 characters.
- **Collision:** if the name already exists locally or on the remote, append `-2`, `-3`, … up
  to `-9`, then fail into the gate and ask. Never check out an existing unrelated branch just
  because the name matched.

---

## Step F: The gate

### F-1. MUST PRINT VERBATIM

```text
🌿 Git flow
   Model:       {model} (confidence: {confidence} — {sources, comma-separated})
   Convention:  {rendered pattern}  (learned from {branches_analyzed} branches)
   Task type:   {task_type} ({source}{, runners-up: X, Y if confidence == medium})
   Current:     {current_branch}{ (base branch — a task branch is required) if current_branch_is_base}
   Proposed:    {branch_name}
   Branch from: {base_branch}
   PR base:     {pr_base_branch}
```

Add these lines only when they apply:

```text
   ⚠️  Uncommitted changes: {dirty_file_count} file(s) — they follow you onto the new branch
   ⚠️  Rules/topology conflict: {topology_conflict}
   ↩️  Requires back-merge to {requires_back_merge} after the PR merges
```

### F-2. Choices

Ask the user, then act:

| Choice | Effect |
|---|---|
| **create** | `git checkout -b {branch_name} {base_branch}`. `branch_action = "created"` |
| **continue** | Stay on `current_branch`. `branch_action = "continued"` |
| **rename** | Take the user's name verbatim (validate with `git check-ref-format --branch`), then create |
| **change type** | Take a task_type from the Step C set, re-run D and E, re-print this block |
| **abort** | Stop the pipeline before Step 2. Nothing has been written yet |

Defaults, and the one hard restriction:

- `current_branch_is_base == true` → **"continue" is not offered.** Staying would make
  `pr_base_branch == branch_name`, and the documentation phase would try to open a
  `main → main` PR. The choices reduce to create / rename / change type / abort.
- `current_branch_is_base == false` and `current_branch` matches the learned convention →
  default to **continue**. A second branch for work already in progress on a correctly-named
  branch is almost never what the operator wants.
- Otherwise → default to **create**.

### F-3. Fetching a missing base ref

Before `checkout -b`, verify the base ref resolves: `git rev-parse --verify {base_branch}`.
If it does not, and a remote-tracking equivalent might exist, run exactly one
`git fetch origin {base_branch}` and re-verify. Still missing → report it and fall back to
`current_branch` as the base, recording the substitution in telemetry. Never invent a base.

### F-4. Headless mode

When `HEADLESS == true` (`SDLC_NONINTERACTIVE`, resolved at Step 0a-1) there is no user
channel, so the gate does not ask:

- Print nothing to stdout. Write one line to stderr:
  `GIT-FLOW: model={model} confidence={confidence} type={task_type} branch={branch_name} base={base_branch} pr_base={pr_base_branch} action={branch_action}`
- `confidence == "low"` or `model == "unknown"` → fall back to github-flow off
  `default_branch`, and add `fallback=low-confidence` to that stderr line.
- `current_branch_is_base == true` → create the branch. Otherwise → continue on the current
  branch (a CI job that already checked out a task branch must not get a second one).
- `git.auto_create_branch: false` in config → never create; `branch_action = "declined"`.

### F-5. Outputs

Set, for the rest of the run:

`CONTEXT.git_flow_model`, `git_flow_confidence`, `git_flow_source`, `git_flow_sources[]`,
`task_type`, `task_type_confidence`, `branch_name`, `branch_action`, `base_branch`,
`pr_base_branch`, `naming_convention`, `requires_back_merge` (or null),
`topology_conflict` (or null).

`base_branch` is consumed by Step 0c's diff signals; `task_type` by `RESOLVER.md` Step 1;
`pr_base_branch`, `task_type` and `requires_back_merge` reach the documentation phase through
the Step 3b-1 per-call CONTEXT trailer.

---

## Step G: Cache and exclusion

### G-1. Shape

`<project>/.claude/.sdlc-git-flow.json`:

```json
{
  "schema_version": 1,
  "detected_at": "2026-08-04T11:20:00Z",
  "user_confirmed": true,
  "model": "github-flow",
  "confidence": "high",
  "sources": ["rules:CONTRIBUTING.md", "topology:prefix-histogram"],
  "default_branch": "main",
  "develop_branch": null,
  "prefix_style": "conventional",
  "prefix_histogram": { "feature": 7, "fix": 4 },
  "naming": {
    "separator": "/",
    "word_separator": "-",
    "ticket_pattern": null,
    "ticket_position": null,
    "observed_max_length": 42
  }
}
```

Per-run values — `task_type`, `branch_name`, `branch_action` — are **not** cached. They belong
to one invocation and caching them would propose the previous run's branch for the next task.

### G-2. Trust rules

A cache hit is used when **all** hold:

- `schema_version == 1`.
- `user_confirmed == true` (an unconfirmed guess is re-asked, so a wrong detection cannot
  silently outlive the run that produced it).
- `detected_at` is younger than 30 days.
- `--redetect-git-flow` was not passed.
- The cached `default_branch` still resolves (`git rev-parse --verify`) and, for
  `model: git-flow`, so does `develop_branch`. A repo that dropped its `develop` branch has
  changed model.

Otherwise re-run detection. Parse failure or unknown `schema_version` → warn once, ignore the
file, re-detect, overwrite.

### G-3. Writing it

Write the cache only after the gate resolves, with `user_confirmed = true` in interactive mode
and `false` in headless (so the next interactive run confirms what CI assumed).

Before writing, ensure the file is excluded from version control — the same idempotent
mechanism Step 2 uses for `.claude/.sdlc-run-active.json`: if `.git/info/exclude` exists and
does not already contain `.claude/.sdlc-git-flow.json`, append it. This keeps a
machine-generated file out of the commit the documentation phase creates without touching the
project's own `.gitignore`.

Unlike the run marker, the cache is **not** deleted at Step 5 — outliving the run is its
entire purpose.

---

## Worked example: this repository

Real `detect-git-flow.sh` output for `AratKruglik/claude-sdlc`:

```text
default_branch:    main
develop_branch:    null
gitflow_config:    0 keys
prefix_histogram:  feature=7, fix=4      (feaature=1 and docs=1 discarded as singletons)
prefix_style:      conventional
naming:            separator=/, word_separator=-, ticket_pattern=null
→ model=github-flow, confidence=high
```

So for `/sdlc:start "Add /healthz endpoint"` from `main`: task_type `feature`, branch
`feature/add-healthz-endpoint`, base `main`, PR base `main`.

Two properties of this example are load-bearing as regression checks:

1. **A detector that reports `git-flow` here is wrong.** The repo uses git-flow-*style*
   prefixes with no `develop` branch — prefix vocabulary alone must never imply the model.
2. **`feaature/optimization` is a real typo in this repo's history.** It must not become a
   learned prefix; that is why singleton counts are discarded.
