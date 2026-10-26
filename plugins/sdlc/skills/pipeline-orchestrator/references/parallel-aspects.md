# Pipeline orchestrator — 3b-parallel-aspects (experimental)

Read this when `EFFECTIVE_PROFILE.aspect_execution == "parallel-implement"`.


Applies only when `EFFECTIVE_PROFILE.aspect_execution == "parallel-implement"` (default
`sequential`, Step 1b). This is **experimental**: the safety argument rests on file-set
disjointness the orchestrator can check, plus prompt-level guardrails it cannot enforce. Leave
it off unless you are deliberately testing it.

**Plan passes never run in parallel.** The frontend plan is built against the backend plan's
"Contract for frontend" section, so backend must plan first. Run all plan passes in canonical
order, exactly as in 3b-special.

**One approval gate for the whole phase.** Instead of a gate per aspect, print every aspect's
plan summary, then ask once:

```
📋 Implementation plans ready for development ({aspects, comma-separated}).
   Review: docs/plans/{task_slug}/02-development-plan-{aspect}.md (one per aspect)
```

Accept *approve* / *request changes {aspect}: {feedback}* / *abort [{aspect}]*. Requesting
changes on `backend` invalidates the frontend plan too and re-plans both, because the frontend
plan was derived from the backend contract that just changed. Record `approval_rounds` in
telemetry.

**Implementation passes run concurrently only for the `backend ∥ frontend` pair, and only when
every invariant below holds.** Check them yourself, from the two approved plan files — this is
a deterministic check on file lists, not a judgement call:

1. **Different profiles own the two aspects.** One profile owning both means one agent, and an
   agent cannot run concurrently with itself.
2. **The plans' create/modify file sets are disjoint.** Any single path in both sets disqualifies
   the pair — two agents editing one file in a shared working tree is a lost write, not a race
   to reason about.
3. **Neither plan touches a shared-fate file**: `package.json`, `composer.json`, any lockfile,
   `Dockerfile*`, CI YAML, `.env*`, or a routes file both stacks register into. These serialize
   the whole build even when the diffs look unrelated.

If any invariant fails, fall back to sequential for this run and **print the reason**:

```
   ℹ️ aspect_execution=parallel-implement not applied: {which invariant failed, and the paths that failed it}
      Running development aspects sequentially.
```

When the pair does run concurrently, both dispatches go in one message (3c-group), each keeps
its own `[pass:implement]` marker, and the trailer of each prompt gains:

```
parallel_peer_aspects: {the other aspect}
```

with this fixed text appended to the `development_implement` base prompt:

> A peer architect is editing a different part of this working tree at the same time. Type
> errors, lint failures, missing imports and failing tests **outside your own aspect's paths**
> are transient noise from work in progress — do not fix them, do not reformat them, do not
> report them as findings. Run formatters and linters against your own files only, never
> repo-wide. If a file you need is being changed by the peer, that is an invariant violation:
> stop and report it rather than working around it.

**Known limitation.** Invariants 2 and 3 constrain what the *plans* declare. Nothing prevents an
agent from touching a file its plan did not mention, and tool-level interference (a repo-wide
formatter, a build that writes generated files) is guarded only by the prompt text above. This
is why the mode is experimental and off by default.

