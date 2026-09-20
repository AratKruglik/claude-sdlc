# Model Routing Analysis

How subagents in this marketplace are assigned to models, why the previous assignment went
stale, and what changed as a result.

Companion to `model-analis.md` (research notes, Ukrainian) at the repo root, which is the
source for the model-capability claims cited here. This document is the part that applies to
*this* codebase.

---

## 1. Summary

The marketplace routes 29 agents across three model tiers. That routing was calibrated when
Opus cost **5×** Sonnet per input token. It now costs **1.67×**. A 3× change in the central
ratio invalidates the reasoning behind several decisions, and parts of the repo had already
been repriced while others had not — the two halves contradicted each other.

Seven defects were found. Six are fixed; one (`effort` cannot be varied per dispatch) is an
API constraint, documented rather than fixed.

The headline routing change: **the development phase now runs its two passes on different
tiers** — planning on Opus, implementation on Sonnet. The two-pass structure with a human
approval gate already existed; both passes simply ran on the same model, so the structure
carried no benefit.

---

## 2. What changed in the economics

| | Previous generation | Current generation |
|---|---|---|
| Opus : Sonnet (input) | $15 : $3 = **5.0×** | $5 : $3 = **1.67×** |
| Opus : Haiku (input) | 15× | **5×** |
| Sonnet intro rate | — | $2/$10 per MTok through 2026-08-31 → Opus : Sonnet = 2.5× |

List prices per MTok (input / cached input / output):

| Tier | Input | Cached input | Output |
|---|---|---|---|
| `opus` | $5 | $0.50 | $25 |
| `sonnet` | $3 | $0.30 | $15 |
| `haiku` | $1 | $0.10 | $5 |

`CHANGELOG.md` records the decision that moved 18 stack architects from Opus down to Sonnet.
It was correct at 5×. At 1.67× the question reopens — but the answer is **not** "put the
architects back on Opus". The development phase is the largest token line in the pipeline
(~250K input for a medium feature), and paying Opus rates for bulk implementation against an
already-approved spec buys little. The leverage is in the *planning* pass, which is small,
gated by a human, and determines everything downstream. Hence the split in §4.1.

---

## 3. Defects found

Each is reproducible by reading the cited file.

### D1 — Telemetry priced Opus at the previous generation's rate ✅ fixed

`pipeline-orchestrator/SKILL.md` step 3d-1 computed `cost_usd` from `opus: input $15/MTok,
cached $1.50, output $75`. Meanwhile `README.md` → "Estimated cost for a medium feature" was
already computed at $5/$25 — verified arithmetically on all five rows (BA `40K×$5 + 3K×$25 =
$0.275` against a stated `~$0.28`; Dev `$0.87` ✓; QA `$0.375` ✓; Docs `$0.025` ✓; total
`$1.82` against `~$1.84` ✓).

Telemetry therefore inflated every Opus phase by 3×. The cached-input figure gave it away
independently: cached input is 10% of base input for every tier, which held for Sonnet ($0.30)
and Haiku ($0.10) but not for the stale Opus row ($1.50 against a $5 base).

**Fixed:** pricing table corrected, with a note that it must stay in sync with `README.md`.

### D2 — Handoff budget compared characters against a token threshold ✅ fixed

Step 3d-1 set `compact_handoff_violation: true` when the summary exceeded `3000 chars`, and
labelled that "≈ 3K-token target". But the same step estimates tokens as `chars / 4`, and every
agent contract states its budget in tokens — ≤2K for `business-analyst`, `qa-engineer`,
`security-analyst`; ≤3K for `developer`. 2K tokens is roughly 8000 characters.

The threshold was about 4× too tight, so a fully compliant agent tripped the violation flag on
every run. That matters more than it looks: this counter is the pipeline's only sensor for
model verbosity drift, and newer models default to longer responses and narrate progress more
in agentic sessions. A sensor that fires constantly reports nothing.

**Fixed:** the comparison now converts to tokens first (`chars / 4 > 3000`).

### D3 — `caps.max_total_cost_usd` was declared but never enforced ✅ fixed

The field existed in `schemas/workflow.schema.json` and in two recipes (`hotfix.yaml` $0.60,
`docs-only.yaml` $0.10), with no enforcement anywhere in the orchestrator or hooks.

The hotfix cap was also unreachable. That recipe runs dev + qa + security, which at correct
prices is ~$1.52 standard / ~$1.11 intro — the $0.60 cap sat about 2.5× below a normal run, so
implementing it as written would have aborted every hotfix.

**Fixed:** enforcement added as step 3d-3 (running total checked after each phase, user is
asked whether to continue, never a silent abort). Caps recalibrated as runaway guards rather
than routine blockers: hotfix $2.50, docs-only $0.20.

### D4 — `docs/cost-baseline.md` was read but never existed ✅ fixed

`/sdlc:doctor` step 4 parses this file for `avg_cost_per_medium_run_usd`, `p90`, and
`cache_hit_ratio`. The file was absent, so every cost claim in the repo rested on estimates
with nothing to check them against.

Note that `docs/` is gitignored — it is a per-project working area (plans, telemetry), not
tracked documentation. A baseline file committed here would never reach a user's project
anyway, which is likely why it was never created.

**Fixed:** the scaffold ships as a plugin template at
`plugins/sdlc/templates/cost-baseline.md` — with the `json summary` block doctor expects,
marked "not yet baselined", plus instructions for aggregating `_telemetry.json` across runs —
and `/sdlc:doctor` step 4 now seeds `<repo>/docs/cost-baseline.md` from it when absent. That
seed is the command's only write, and it never overwrites an existing file.

### D5 — The stated enforcement guarantee was false ✅ fixed

`README.md` claimed without qualification: *"The pipeline guarantees that tier is actually used
— regardless of the session-level default model."*

Claude Code resolves a subagent's model in the order **per-invocation parameter →
frontmatter → `CLAUDE_CODE_SUBAGENT_MODEL` → session model**
([docs](https://code.claude.com/docs/en/sub-agents)). Both enforcement layers write one of
the first two, so that environment variable *alone* never overrides them.

**Corrected in v2.0.0.** This section previously stated the reverse order —
`CLAUDE_CODE_SUBAGENT_MODEL` first — and so did README, SKILL, doctor and the hook header.
That was accurate for Claude Code before v2.1.251, where the variable did sit above both
layers; it stopped being true and the repo did not follow. The real override is
**`CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1`** (v2.1.257+), which makes Claude Code ignore the
dispatch parameter and every agent's `model:` frontmatter, running every phase on
`CLAUDE_CODE_SUBAGENT_MODEL` — or on the session model when that is unset. An organization
`availableModels` allowlist can likewise cause a value to be skipped in favour of the
inherited model.

This is the trap flagged in `model-analis.md` §5, and it was unchecked anywhere in the repo.

**Fixed:** `/sdlc:doctor` reports `CLAUDE_CODE_SUBAGENT_MODEL` as informational and warns
only when `CLAUDE_CODE_SUBAGENT_MODEL_FORCE` is on — the distinction that makes the report
actionable rather than alarming; the guarantee in `README.md` and `SKILL.md` carries the
condition.

### D6 — Tier vocabulary was narrower than the tool accepts ✅ fixed

`enforce-agent-model.sh` accepted only `opus|sonnet|haiku` and silently skipped anything else.
The `Agent` tool also accepts `fable`. Latent rather than active — no agent is assigned to
Fable, and none should be by default (token-hungry, unreliable under subscription plans) — but
it capped the vocabulary for no reason.

**Fixed:** `fable` added to the allowlist. No agent assigned to it.

### D7 — Telemetry omits the orchestrator's own consumption ✅ documented

`phases[]` meters subagent spawns only. The orchestrator itself — a ~1000-line skill body,
stack-profile globbing and parsing, workflow resolution and schema validation, and the
approval-gate exchanges — runs on the session model and is invisible. `total_cost_usd` is a
floor, not a bill.

Metering it properly is not possible from inside the skill.

**Documented:** telemetry now carries `cost_scope: "subagent_phases_only"`, with the same
caveat repeated in `docs/cost-baseline.md`, so the number cannot be silently misread as a
total.

### D8 — Off-roster project-local agents could silently replace a phase agent ✅ fixed

Observed live: a project shipping its own `.claude/agents/{tester,reviewer,...}.md` had two
pipeline phases dispatch `tester` and `reviewer` instead of `qa-engineer` and
`security-analyst`. Neither name is declared by any plugin in this marketplace — the
orchestrator improvised, because nothing enforced that `subagent_type` must come from
`EFFECTIVE_PROFILE.agents_per_phase`. The hook's `.md not found — skipping model check`
warning was not the bug; it was the only signal that this had happened, since the two
dispatches also dropped the `description: "Phase N/total: ..."` contract (ruling out a
description-pattern gate) and used `run_in_background: true` (skipping Step 3d artifact
validation and 3d-1 telemetry for both phases).

**Fixed:**

- The orchestrator writes a run marker (`.claude/.sdlc-run-active.json`, Step 2) listing the
  resolved agent roster for the run, and deletes it at Step 5 / on abort.
- `enforce-agent-model.sh` denies `subagent_type`s that resolve to a **project- or
  user-local** agent (`.claude/agents/*.md` or `~/.claude/agents/*.md`) not present in that
  roster, while a marker is active. Plugin agents and built-ins (`general-purpose`,
  `Explore`, ...) are untouched — the deny is scoped to local agents only, since architects
  legitimately spawn built-ins via `superpowers:requesting-code-review` and
  `superpowers:subagent-driven-development`.
- A deliberate override is available: `agent_overrides` in `.claude/sdlc.local.yaml` adds a
  project-local agent to the roster for a named phase.
- Step 3c now dispatches `subagent_type` qualified as `{plugin_name}:{agent_name}` (e.g.
  `sdlc:qa-engineer`), closing the name collision between a plugin's bare agent name and a
  same-named project-local agent, and restates that `description` must follow the
  `Phase N/total: {phase_name}{pass_marker}` contract exactly. Claude Code's own docs
  confirm the collision is real, not hypothetical: *"Project and user `.claude/agents/`
  definitions override same-named plugin agents"* — a bare `developer` dispatch in a
  project with `.claude/agents/developer.md` resolves to the local file, full stop.
  Because of this, the hook's local-agent probe fires **only for unqualified
  dispatches** — a qualified `plugin:agent` name cannot resolve to a local file, so
  checking it against local agents would produce false-positive denies of legitimate
  plugin agents whose bare name happens to collide (verified: `sdlc:developer` allowed
  even with a colliding local `developer.md` present). Step 3c also drops the
  "retry with the bare name on error" fallback that an earlier draft of this fix had —
  a bare-name retry after a qualified-dispatch error would reintroduce the exact
  collision this fix closes, since the roster's qualified entry (`sdlc:developer`)
  must not be read as authorizing the bare form.
- `/sdlc:doctor` reports local-agent/profile name collisions and a stale (>6h) run marker.

See `pipeline-orchestrator/SKILL.md` Step 2, Step 3c, and Hard Rules; `enforce-agent-model.sh`
for the deny rule; `doctor.md` Step 6.

---

## 4. Routing changes

### 4.1 Development phase: split the two passes

The development phase already ran two passes with a human approval gate between them —
Pass 1 writes an implementation plan, the user approves it, Pass 2 implements. Both passes
resolved the same `model:` field, so the `opusplan` structure was there while the benefit was
not.

Planning and implementation have opposite economics. Planning is small-output work whose
result passes human review and then governs everything downstream; a bad plan costs a full
implementation cycle plus the QA and security passes that follow it. Implementation is
high-volume execution against an approved spec — exactly Sonnet's job.

**Change:** a new optional frontmatter field `model_plan:` is resolved for the planning pass,
falling back to `model:` when absent. All 19 development-phase agents (18 stack architects plus
the vanilla `developer`) now declare `model_plan: opus` alongside `model: sonnet`. Database
specialists are untouched — they run in a separate `database` phase with no planning pass.

Three places must agree or the change silently does nothing:

1. **Agent frontmatter** — `model_plan:` (optional; falls back to `model:`).
2. **Orchestrator** — step 3b-3 resolves `model_plan` for Pass 1, `model` for Pass 2, and
   step 3c stamps a pass marker into `description`.
3. **`enforce-agent-model.sh`** — reads that marker and enforces the matching field.

The hook is the part that is easy to miss. It sees only `tool_input`, so without the marker it
would read `model:`, find `sonnet`, and rewrite the Opus planning dispatch back down —
undoing the split with no visible symptom. `description` is orchestrator-controlled and
therefore the reliable channel; matching on prompt content would be fragile.

Marker format: `[pass:plan]` / `[pass:implement]`, appended to the existing description with a single leading space.

### 4.2 Security review: raised to `effort: xhigh`

`security-analyst` moved from `effort: high` to `xhigh`. It is the one agent whose failures are
silent — a missed vulnerability produces no error, no failing test, and no signal anywhere in
the pipeline — and it processes a small token volume (~40K in), so the extra reasoning applies
to a cheap line.

### 4.3 Frontend: guidance, not a bigger model

Six frontend architects run on `sonnet/medium`. The obvious move — raise them to Opus for
better-looking UI — is the wrong one. Raw generation converges on generic AI aesthetics
regardless of tier; that is a distributional property, not a capability gap, and a larger model
does not fix it.

**Change:** `frontend-design` (official Anthropic plugin) added as an optional external
dependency, following the pattern already used for `security-guidance`, and referenced from
the convention skills of the seven frontend-capable stack profiles. It is `policy: warn` — the
pipeline runs without it, with a note that visual quality regresses.

Project-specific style rules (palette, spacing, an explicit "no generic AI aesthetics") belong
in the project's own `CLAUDE.md` and are out of scope for the marketplace.

---

## 5. What was deliberately not changed

**Database specialists stay on Sonnet.** Moving the six migration agents to Haiku saves about
$0.11 per run. They generate column types, indexes, foreign keys, and cascade rules — a wrong
cascade is a production incident. The trade is not close enough to be worth measuring.

**No Haiku "repo-scout" pre-pass.** Adding a cheap read-only agent to digest the codebase so
the Sonnet architect reads less is superficially attractive and contradicts an earlier finding
of this project's own — recorded in the dynamic-workflows design note under `docs/plans/`, a
gitignored working area and therefore not readable from a checkout: *"the dominant cost driver
in this architecture is the per-phase subagent spawn… the efficiency win comes overwhelmingly
from removing unnecessary spawns, not from clever routing."* Adding a spawn to save cached
input tokens runs the wrong way.

**No cleanup of self-verification instructions.** Newer Opus models verify their own work and
can over-verify when prompted to do it again, so standing instructions like "include a final
verification step" or "use a subagent to verify" are a token-bloat risk. Checked by grep across
all `plugins/**/*.md`: no such instructions exist. The two matches in
`batch-pipeline/SKILL.md` concern auto-approving the development gate in background runs and
are unrelated. No exposure.

**`business-analyst` stays at `effort: high`.** Its work is requirements elicitation, not deep
code reasoning; `xhigh` buys less here than it does in security review.

---

## 6. An API constraint worth knowing

**`model` can be varied per dispatch. `effort` cannot.**

The original plan called for the development planning pass to run at `effort: xhigh` alongside
`model_plan: opus`, keeping the implementation pass at `medium`. This is not implementable.
`effort` is read by the harness from agent frontmatter and has no per-invocation override — the
`Agent` tool exposes `description`, `isolation`, `model`, `prompt`, `run_in_background`, and
`subagent_type`, and nothing else. Both passes use the same agent file, so they necessarily
share one `effort` value.

Options considered: split each architect into two agent files (19 → 38 files, duplicated stack
knowledge — rejected), or raise the whole agent to `high` (also raises the expensive
implementation pass — rejected). Development architects stay at `medium` for both passes.

Related ladder constraints, for anyone tuning `effort` further:

- Thinking cannot be disabled at `effort` ≥ `xhigh` (the request fails).
- Thinking is on by default on current Opus and counts toward `max_tokens`.
- Available levels depend on the model — `xhigh`/`max` are not universal.

One more operational limit, relevant to `/sdlc:batch`: **20 concurrent subagents per session**
(`CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS`), after which spawning fails. Batch fans out one
background worktree agent per task, and each of those runs a full 5-phase pipeline, so the
ceiling is reachable on large batches.

---

## 7. Cost impact

Estimated cost for a medium feature, before and after. **These are estimates, not
measurements** — see `docs/cost-baseline.md`.

| Phase | Tier | Before | After (standard) | After (intro rate) |
|---|---|---|---|---|
| BA | opus/high | $0.28 | $0.28 | $0.28 |
| Dev — plan | opus (new) | — | ~$0.50 | ~$0.50 |
| Dev — implement | sonnet/medium | $0.87 | $0.87 | $0.58 |
| QA | sonnet/medium | $0.38 | $0.38 | $0.25 |
| Security | opus/xhigh | $0.28 | ~$0.35 | ~$0.35 |
| Docs | haiku/low | $0.03 | $0.03 | $0.03 |
| **Total** | | **~$1.84** | **~$2.40** | **~$1.98** |

**This is an increase of roughly 30%, and it is a deliberate trade, not an oversight.** The
argument is cost per *completed* task rather than cost per run: a development pass that starts
from a weak plan is re-run, and it drags the QA and security phases with it. One avoided rework
cycle on a medium feature costs more than the delta.

Two figures carry real uncertainty and are marked with `~`:

- **Dev plan pass.** No measured token volume exists for a planning-only pass; 80K in / 4K out
  is an assumption.
- **Security at `xhigh`.** Thinking tokens bill at the output rate ($25/MTok), and how much
  `xhigh` adds is not something this repo has measured. The row assumes output roughly doubles.

Both are the same class of staleness as D1 — a plausible number nobody has checked. Populating
`docs/cost-baseline.md` from real runs replaces them.

**Opting out.** If the increase is not wanted, `model_plan: sonnet` (or deleting the field) in
an architect's frontmatter reverts that agent to single-tier behaviour with no other changes.

---

## 8. Open item: complexity-based escalation

Model tier is currently static per agent. A better fit would escalate on task properties — a
feature touching authentication, payments, or concurrency, or exceeding a file-count threshold,
warrants Opus for implementation too, while a CRUD endpoint does not.

**Half-closed in v2.0.0.** The machine-readable complexity signal now exists — the BA
compact summary's `COMPLEXITY:` line — and the recipe schema can consume it
declaratively: a phase member may carry `when: complexity == large` (or `!=`), evaluated
once after BA returns, per RESOLVER Step 4b. That covers *dropping* a phase on a small
task.

What remains open is **escalating a model tier** on the same signal. `when:` removes
members; it does not re-tier one. Doing that needs a place in the recipe to declare the
escalation and a rule for how it interacts with `model_plan`, which is its own change.
The constraint below still holds for it.

The original framing, kept because the constraint outlives the gap: it needs a decision
on how the BA phase signals complexity in a
machine-readable way, plus a `workflow.schema.json` extension to declare the rule
declaratively — enough design surface to belong in its own change. The escalation must stay
deterministic and declared in the recipe, not inferred at dispatch time, or runs stop being
reproducible.

---

## 9. Verification

- **Hook** — `bash -n plugins/sdlc/hooks/enforce-agent-model.sh`, then feed synthetic
  `PreToolUse` payloads: `[pass:plan]` → `opus`; `[pass:implement]` → unchanged `sonnet`;
  `document-writer` with a requested `opus` → corrected to `haiku`; a plan pass on an agent
  without `model_plan` → falls back to `model`.
- **Schema** — validate `hotfix.yaml` and `docs-only.yaml` against
  `schemas/workflow.schema.json`.
- **Doctor** — run `/sdlc:doctor`; with `CLAUDE_CODE_SUBAGENT_MODEL` set alone it must report
  the value as informational and **not** warn, since that variable no longer overrides the
  two layers. Set `CLAUDE_CODE_SUBAGENT_MODEL_FORCE=1` and confirm the override warning
  appears.
- **End to end** — run `/sdlc:start` on a small feature and check
  `docs/plans/{slug}/_telemetry.json`: Opus phase costs down ~3× against the old table, no
  `compact_handoff_violation` on compliant summaries, and `opus` on the plan pass with `sonnet`
  on the implement pass in `docs/plans/_model-enforcement.log`.

---

## 10. v2.0.0 — measured telemetry supersedes these estimates

Every cost figure in this document was derived from assumed token volumes: the `Agent` tool
result carries no usage data, so the orchestrator estimated tokens as `chars / 4`. Section 7's
table is that arithmetic, and the two rows it flags as uncertain (the Dev plan pass, Security
at `xhigh`) were never measurable at all.

As of v2.0.0 they are measured. Hooks read each finished subagent's own transcript, dedupe by
`message.id`, and price the result from `references/pricing.json`; `usage-report.sh` attributes
each dispatch to its phase, aspect and pass. `docs/plans/{slug}/_telemetry.json` now carries
real numbers, and `docs/cost-baseline.md` aggregates fully-measured runs.

**Treat this document as the reasoning, and your own baseline as the numbers.** Where the two
disagree, the baseline is right: it was measured on your codebase, and this table was estimated
for one that is not yours.

Three consequences for routing decisions:

- **`maxTurns` values are unmeasured.** Architects 120, database specialists and QA 60, BA and
  security 80, docs 30 were chosen from phase shape, not data. Telemetry now records real turn
  counts per dispatch, so these should be recalibrated downward wherever the distribution says
  they can be — a ceiling nobody ever reaches bounds nothing.
- **Nested cost was previously invisible.** A phase agent spawning `Explore` or a superpowers
  skill spends real money that no earlier version could see. It now lands in `nested_cost_usd`,
  separate from `total_cost_usd` so `cost_scope` stays truthful. Expect the true per-run figure
  to exceed every estimate in §7 for that reason alone.
- **Security's tiering rests on a job that changed.** `opus/xhigh` was justified by security
  being the phase whose failures nothing else catches. That still holds, but the agent is now
  **report-only**: it finds and prescribes, and the development architect applies the fix under
  a minimal-diff contract on its own `model:` tier, followed by a QA verify rerun. The expensive
  reasoning is spent on detection, and the mechanical edit runs at Sonnet — which is the right
  split, and was not possible while one agent did both.
