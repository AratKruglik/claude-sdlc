# Workflow Resolver — Algorithm Reference

This document specifies how the pipeline orchestrator loads, validates, and
applies a workflow recipe file. Referenced from `pipeline-orchestrator/SKILL.md`
Step 1c.

## Step 1: Select the workflow

Resolve `WORKFLOW_NAME` by taking the first rule that yields a usable recipe. Record the
deciding rule in `CONTEXT.workflow_selection_reason` — the selection must always be
explainable, since it decides which phases run.

1. **Explicit flag.** `--workflow=NAME` in `$ARGUMENTS`. Reason: `flag`.
   An explicit choice is never second-guessed: if the named recipe exists it wins, even when
   its own `match` constraints would not hold.
2. **Project config.** `EFFECTIVE_PROFILE.active_workflow` from `sdlc.local.yaml`.
   Reason: `config`.
3. **Task type.** Map `CONTEXT.task_type` (set by orchestrator Step 0b-git, per this plugin's
   `references/GIT-FLOW.md` Step C) through `TASK_TYPE_TO_WORKFLOW`:

   | task_type | recipe |
   |---|---|
   | `fix`, `bugfix` | `bugfix` |
   | `hotfix` | `hotfix` |
   | `refactor` | `refactor` |
   | `docs` | `docs-only` |
   | `feature`, `release`, `chore` | `default` |

   The mapped recipe is used only when the file exists **and** its own `match` constraints
   hold (see Step 1a). A 600-LOC change described as a "fix" therefore falls through to rule
   5 rather than getting `bugfix`'s trimmed pipeline. Reason: `task_type={type}`.
4. **Match scan.** For recipes that no task type maps to, evaluate each recipe's `match`
   block (Step 1a) in **alphabetical order by `name`** — a fixed order so the same inputs
   always select the same recipe. First satisfied recipe wins.
   Reason: `match:{name}`.
5. **Fallback.** `WORKFLOW_NAME = "default"`. Reason: `fallback`.

### Step 1a: Evaluating a `match` block

A `match` block is satisfied when **every** declared constraint holds. An absent constraint
is not a constraint. Signals come from orchestrator Step 0c.

| Constraint | Satisfied when |
|---|---|
| `arguments_pattern` | the ECMAScript regex matches `$ARGUMENTS` case-insensitively |
| `loc_touched_max` | `diff_scope == "retrospective"` AND `LOC_TOUCHED <= value` |
| `loc_touched_min` | `diff_scope == "retrospective"` AND `LOC_TOUCHED >= value` |
| `has_migrations` | `HAS_MIGRATIONS == value` |
| `config_only` | `CONFIG_ONLY == value` |

**A `loc_touched_*` constraint is never satisfied while `diff_scope == "prospective"`.** On a
freshly created branch `LOC_TOUCHED` is 0, which would satisfy every ceiling in the recipe set
and hand a brand-new feature the `hotfix` pipeline. An unmeasurable diff is unknown, not small.

Search path for the resolved name (in order, first match wins):

```text
~/.claude/plugins/cache/sdlc/workflows/{WORKFLOW_NAME}.yaml
```

*(Iteration 4+: also search `<project>/.claude/sdlc-workflows/` for project-local recipes.)*

If no file is found, the behaviour depends on which Step 1 rule produced the name. A rule that
inferred the name must degrade; a rule that was told the name must halt.

- **Rules 1–2** (`--workflow=NAME`, `active_workflow`) — the user named a recipe that does not
  exist. **HALT**:

  ```text
  ❌ Workflow '{WORKFLOW_NAME}' not found.
     Searched: ~/.claude/plugins/cache/sdlc/workflows/{WORKFLOW_NAME}.yaml
     Available: {list all *.yaml in the workflows/ directory via Glob, excluding test-fixtures/}
     Omit --workflow=NAME to use the default workflow.
  ```

- **Rules 3–4** (task-type mapping, match scan) — the recipe was inferred, so a missing file is
  a gap in the recipe set, not an operator error. Warn once and continue to the next Step 1
  rule; `default` is guaranteed to exist:

  ```text
  ⚠️ Inferred workflow '{WORKFLOW_NAME}' not found — falling back.
  ```

## Step 2: Read, parse, and validate

`Read` the located file. Parse YAML. Validate the parsed structure against
`schemas/workflow.schema.json` (Read the schema, verify `required` fields are
present, types match, and no unknown properties exist). If validation fails → **HALT**:

```text
❌ Workflow '{WORKFLOW_NAME}' failed schema validation.
   Errors: {list each violation — missing field, wrong type, unknown property}
   File: {file_path}
```

Extract `phases` array. Normalize each element to `{name: string, when?: string}`:

- String element `"foo"` → `{name: "foo"}`
- Object element `{name: "foo", when: "..."}` → keep as-is

## Step 3: Acyclic validation (Iteration 0)

Extract the list of phase names: `phase_names = [p.name for p in phases]`.

If any name appears more than once → **HALT**:

```text
❌ Workflow '{workflow_name}' contains duplicate phase '{duplicate_name}'.
   A workflow DAG must be acyclic — each phase may appear at most once.
   File: {file_path}
```

*(Iteration 1+: when `after:` edges are introduced, also run a topological sort and
detect back-edges. Until then, duplicate-name detection is sufficient.)*

## Step 4: Build the resolved phase list

Start with the normalized `phases` from Step 2 (already in order for Iteration 0).

### Insert extra_phases from stack profiles

For each entry in `EFFECTIVE_PROFILE.extra_phases` (merged in Step 1a):

- Find the index of the phase named `extra_phase.after` in the list.
- If found: insert the extra phase immediately after that index.
- If not found: skip with a one-line warning:

```text
⚠️ Extra phase '{extra_phase.name}' has after='{extra_phase.after}' which is
   not present in workflow '{WORKFLOW_NAME}' — skipping.
```

### Conflict detection after insertion

After all extra_phases have been inserted, re-run the acyclic check from Step 3
on the merged list. If any phase name now appears more than once → **HALT**:

```text
❌ Workflow '{workflow_name}' after merging stack extra_phases contains duplicate
   phase '{duplicate_name}'. Check the stack profile's extra_phases declaration.
```

### Apply skip_phases

Sources: Step 0c skip-rules + Step 1b sdlc.local.yaml.

Remove all phases whose `name` is in the combined skip set.

## Step 5: Persist and announce

Store the resolved list as `CONTEXT.resolved_phases[]`. Persist `WORKFLOW_NAME` in
`CONTEXT.active_workflow` and the Step 1 deciding rule in
`CONTEXT.workflow_selection_reason`.

Print a new line **at Step 1c** (not part of the earlier Step 0b block):

```text
   workflow: {WORKFLOW_NAME}  ({N} phases after skips, selected by {workflow_selection_reason})
```

Examples of the reason field: `flag`, `config`, `task_type=hotfix`, `match:docs-only`,
`fallback`.

The full "resolved plan + cost-preview" verbatim block is added in Iteration 1.
