# Workflow Resolver — Algorithm Reference

This document specifies how the pipeline orchestrator loads, validates, and
applies a workflow recipe file. Referenced from `pipeline-orchestrator/SKILL.md`
Step 1c.

## Step 1: Locate the workflow file

1. If `$ARGUMENTS` contains `--workflow=NAME`, use `NAME` as `WORKFLOW_NAME`.
2. Else if `EFFECTIVE_PROFILE` (from sdlc.local.yaml) specifies `active_workflow`,
   use that as `WORKFLOW_NAME`. *(Iteration 4+)*
3. Otherwise: `WORKFLOW_NAME = "default"`.

Search path (in order, first match wins):

```text
~/.claude/plugins/cache/sdlc/workflows/{WORKFLOW_NAME}.yaml
```

*(Iteration 4+: also search `<project>/.claude/sdlc-workflows/` for project-local recipes.)*

If no file is found → **HALT**:

```text
❌ Workflow '{WORKFLOW_NAME}' not found.
   Searched: ~/.claude/plugins/cache/sdlc/workflows/{WORKFLOW_NAME}.yaml
   Available: {list all *.yaml in the workflows/ directory via Glob, excluding test-fixtures/}
   Omit --workflow=NAME to use the default workflow.
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
`CONTEXT.active_workflow`.

Print a new line **at Step 1c** (not part of the earlier Step 0b block):

```text
   workflow: {WORKFLOW_NAME}  ({N} phases after skips)
```

The full "resolved plan + cost-preview" verbatim block is added in Iteration 1.
