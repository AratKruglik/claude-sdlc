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
   `references/GIT-FLOW.md` Step C, classified against `references/task-type-patterns.json`)
   through `TASK_TYPE_TO_WORKFLOW`:

   | task_type | recipe |
   |---|---|
   | `fix`, `bugfix` | `bugfix` |
   | `hotfix` | `hotfix` |
   | `refactor` | `refactor` |
   | `docs` | `docs-only` |
   | `feature`, `release`, `chore` | `default` |

   The mapped recipe is used only when the file exists **and** its *signal* `match` constraints
   hold (see Step 1a/1b — `arguments_pattern` is not one of them here). A 600-LOC change
   described as a "fix" therefore falls through to rule 5 rather than getting `bugfix`'s
   trimmed pipeline. Reason: `task_type={type}`.
4. **Match scan.** For recipes that no task type maps to, evaluate each recipe's `match`
   block (Step 1a, all constraints including `arguments_pattern`) in **alphabetical order by
   `name`** — a fixed order so the same inputs always select the same recipe. First satisfied
   recipe wins. Reason: `match:{name}`.
5. **Fallback.** `WORKFLOW_NAME = "default"`. Reason: `fallback`.

### Step 1a: Evaluating a `match` block

A `match` block is satisfied when **every** declared constraint holds. An absent constraint
is not a constraint. Signals come from orchestrator Step 0c.

| Constraint | Satisfied when |
|---|---|
| `arguments_pattern` | (rule 4 only — see Step 1b) the ECMAScript regex, compiled with flags `iu`, matches `$ARGUMENTS`. As in `task-type-patterns.json`, write it with `(?<![\p{L}\p{N}])`/`(?![\p{L}\p{N}])`, never `\b` — `\b` cannot assert a boundary next to a non-Latin character. |
| `loc_touched_max` | `diff_scope == "retrospective"` AND `LOC_TOUCHED <= value` |
| `loc_touched_min` | `diff_scope == "retrospective"` AND `LOC_TOUCHED >= value` |
| `has_migrations` | `HAS_MIGRATIONS == value` |
| `config_only` | `CONFIG_ONLY == value` |

**A `loc_touched_*` constraint is never satisfied while `diff_scope == "prospective"`.** On a
freshly created branch `LOC_TOUCHED` is 0, which would satisfy every ceiling in the recipe set
and hand a brand-new feature the `hotfix` pipeline. An unmeasurable diff is unknown, not small.

### Step 1b: A constraint selects in rule 4; it only vetoes in rule 3

Rule 3 and rule 4 both evaluate `match`, but they are not the same kind of check, and treating
them as interchangeable is what broke this resolver twice:

- **Rule 4 evaluates to select.** No recipe has been chosen yet; a constraint that cannot be
  computed must count as unsatisfied, because letting an unmeasurable input satisfy a
  constraint is how a brand-new feature branch ends up on the `hotfix` pipeline (see the
  `loc_touched_*`/`prospective` note in Step 1a).
- **Rule 3 evaluates to veto.** `task_type` has already named a recipe from the authoritative
  classifier in `GIT-FLOW.md` Step C. The only job left for `match` here is to catch a
  contradiction between that type and the **measured** diff — a 600-LOC change mislabeled
  "fix". A constraint that cannot be measured has nothing to contradict and must not fire.
  Concretely: `loc_touched_max: 500` on `bugfix.yaml` does not disqualify `bugfix` on a
  freshly created branch just because `LOC_TOUCHED` reads 0 under `diff_scope ==
  "prospective"` — that reading is unknown, not a pass or a fail, and rule 3 treats it as
  "constraint not applicable" rather than "constraint failed". The same holds for
  `has_migrations` and `config_only` while `CONFIG_ONLY`/`HAS_MIGRATIONS` are still the Step
  0c-1 safe defaults rather than measured values.
- **`arguments_pattern` is never evaluated under rule 3.** Recipes no longer declare it (see
  the workflow YAML files) precisely because it duplicated — and could silently override —
  the `task_type` classification that rule 3 exists to trust. It remains meaningful only in
  rule 4's match scan, where no `task_type` mapping exists yet to defer to.

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

Extract the `phases` array and normalize it into an ordered list of **groups**. A group is the
unit the pipeline dispatches and numbers; a plain phase is a group of one.

- String element `"foo"` → group `[{name: "foo"}]`
- Object element `{name: "foo", when: "..."}` → group `[{name: "foo", when: "..."}]`
- Object element `{parallel: [m1, m2, …]}` → group `[normalize(m1), normalize(m2), …]`, each
  member normalized by the two rules above. Groups do not nest — the schema rejects a
  `parallel` inside a `parallel`, so this recursion is one level deep by construction.

Record each member's group index. `resolved_phases` is therefore a list of lists, which is also
the shape the run state file stores.

## Step 3: Acyclic validation

Flatten the groups and extract the list of phase names:
`phase_names = [m.name for group in groups for m in group]`.

If any name appears more than once → **HALT**:

```text
❌ Workflow '{workflow_name}' contains duplicate phase '{duplicate_name}'.
   A workflow DAG must be acyclic — each phase may appear at most once.
   File: {file_path}
```

The check runs over the **flattened** list, so `{parallel: [qa, qa]}` and a `qa` that appears
both inside a group and outside it are both caught. Members of one group are concurrent, not
repeated, so being in the same group is not itself a duplicate.

*(Iteration 1+: when `after:` edges are introduced, also run a topological sort and
detect back-edges. Until then, duplicate-name detection is sufficient.)*

## Step 4: Build the resolved phase list

Start with the normalized groups from Step 2 (already in order).

### Insert extra_phases from stack profiles

For each entry in `EFFECTIVE_PROFILE.extra_phases` (merged in Step 1a):

- Find the group containing a member named `extra_phase.after`.
- If found: insert the extra phase as **its own group** immediately after that group — never
  as a member of it. A stack profile declares a dependency ("after development"), not a
  statement that its phase is safe to run concurrently with that group's members, and the
  orchestrator must not infer the second from the first.
- If not found: skip with a one-line warning:

```text
⚠️ Extra phase '{extra_phase.name}' has after='{extra_phase.after}' which is
   not present in workflow '{WORKFLOW_NAME}' — skipping.
```

### Conflict detection after insertion

After all extra_phases have been inserted, re-run the flattened acyclic check from Step 3. If
any phase name now appears more than once → **HALT**:

```text
❌ Workflow '{workflow_name}' after merging stack extra_phases contains duplicate
   phase '{duplicate_name}'. Check the stack profile's extra_phases declaration.
```

### Apply skip_phases

Sources: Step 0c skip-rules + Step 1b `sdlc.local.yaml`.

Remove every **member** whose `name` is in the combined skip set. Removal is per member, not
per group: skipping `security` out of `{parallel: [qa, security]}` leaves `qa`, it does not
drop QA along with it.

Then collapse the groups:

| Members left in a group | Result |
|---|---|
| 2 or more | stays a parallel group |
| exactly 1 | becomes a plain phase — a one-member group is dispatched and printed exactly like a sequential phase, with no `∥` in its banner |
| 0 | the group is removed from the list entirely |

Collapsing before numbering is what keeps `{N}/{total}` honest: a run that skipped security
must say `Phase 3/4: qa`, not `Phase 3/4: qa ∥ …` with one member.

## Step 5: Persist and announce

Store the resolved groups as `CONTEXT.resolved_phases[]` — a list of lists, one inner list per
group, which is the same shape the run state file persists. Persist `WORKFLOW_NAME` in
`CONTEXT.active_workflow` and the Step 1 deciding rule in
`CONTEXT.workflow_selection_reason`.

`{total}` in every `Phase {N}/{total}` label is the number of **groups**, not the number of
phases. Members of one group share an `N` and are distinguished by their own phase name and
aspect (`Phase 3/4: qa — frontend`, `Phase 3/4: security`). This is deliberate: `N` identifies
a pipeline step, and the members of a group are one step.

Print a new line **at Step 1c** (not part of the earlier Step 0b block):

```text
   workflow: {WORKFLOW_NAME}  ({N} steps after skips, selected by {workflow_selection_reason})
```

When any group has more than one member, add a second line naming them:

```text
   parallel: {comma-separated "a ∥ b" per multi-member group}
```

Examples of the reason field: `flag`, `config`, `task_type=hotfix`, `match:docs-only`,
`fallback`.

The full "resolved plan + cost-preview" verbatim block is added in Iteration 1.
