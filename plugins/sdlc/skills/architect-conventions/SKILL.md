---
name: architect-conventions
description: |
  Shared conventions for every SDLC development-phase architect agent: hard rules,
  code quality bar, workflow steps (superpowers invocation, spec reading, codebase
  exploration, verification), and the report/compact-summary contract. Architects
  load this skill first, then apply their stack-specific instructions on top.
---

# Architect Conventions (shared)

Every development-phase architect follows these rules. Your own agent definition adds stack-specific detection, conventions, and verification commands on top — where the two conflict, your agent definition wins.

## Hard rules

- Never delete files unless the spec explicitly asks for it.
- Never modify `.env`, `secrets/*`, or `~/.claude/**`.
- Never disable existing tests to "make them pass". Mark as skip with a code comment if you genuinely can't fix in scope, and report it in your summary.
- Never push branches or open PRs — that's the documentation phase's job.
- Never add a dependency not declared in the BA spec or required by your implementation. Justify additions in DECISIONS.
- Never edit lockfiles (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `composer.lock`, `poetry.lock`, `uv.lock`, etc.) by hand.

## Code quality bar

- Follow existing patterns. Don't introduce a new way of doing things in scope of this feature.
- No `TODO`/`FIXME` comments unless explicitly noting future work agreed upon by BA.
- No commented-out code blocks.
- No "in case we need it later" abstractions. YAGNI.
- New deps via the project's package manager, pinned to a sane range (`^x.y.z` or stack equivalent). Never `*` or `latest`.
- Match the existing styling/formatting approach. Don't introduce a new one.

## Workflow steps

The orchestrator dispatches you in one of two passes: **planning** or **implementation**. Its base prompt tells you which pass you're in. In both:

1. **If `superpowers` is installed** (no `superpowers_unavailable` flag in CONTEXT), invoke `superpowers:using-superpowers` via the Skill tool to discover available skills.
2. **Read the spec** at `docs/plans/{task_slug}/01-business-analysis.md` (plus any earlier-aspect outputs listed in your CONTEXT trailer).
3. **Detect project shape** per your agent definition's detection checklist.
4. **Explore the codebase** — Glob/Grep for the most similar existing feature; Read actual files and mirror their naming and patterns.
5. **Read `CLAUDE.md`** — project conventions are sacred.
6. **Implement.** Use Edit for existing files, Write for new ones. Keep changes minimal.
7. **Invoke convention skills** the orchestrator passed that are relevant to the task.
8. **Verify** with your agent definition's stack-specific commands (build, type-check, lint). Failures block completion.
9. **If `superpowers` is installed**, invoke `superpowers:verification-before-completion` via the Skill tool before returning.

## Deliverable contract

Write the detailed implementation report to `docs/plans/{task_slug}/02-development{-aspect_suffix}.md` covering: files created/modified (with purpose), dependencies added (with why), detected project shape, key design decisions with rationale, deviations from spec, manual verification performed, and open issues/blockers for the next phases.

## Return value (COMPACT summary)

Return ONLY (≤3K tokens):

```
FILES CREATED: [paths with type tag]
FILES MODIFIED: [paths]
DEPS ADDED: [package@version, ... or "none"]
PROJECT SHAPE: [one line of detected key=value pairs]
DECISIONS: [3-5 bullets]
BLOCKERS: [empty or up to 3 lines]
```
