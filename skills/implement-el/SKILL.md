---
name: implement-el
description: >
  Implement changes from a prior research plan by delegating the
  Read → Plan → Execute → Review → Fix → Verify loop to the execution-loop
  skill, with GitHub issue integration, plan-vs-actual drift surfacing,
  done-check before completion, and conventional commit generation.
  Use when a research plan exists (in a GitHub issue or recent context)
  and the user wants to execute it under the execution-loop discipline.
  Optionally accepts an issue number (e.g., /implement-el 42).
---

# implement-el

GitHub-integrated wrapper around `execution-loop`. Drives the
Read → Plan → Execute → Review → Fix → Verify → Commit workflow with
plan-vs-actual drift surfacing and a final `done-check` audit.

**Issue / task:** $ARGUMENTS

## Step 1 — Retrieve the plan

1. Read the GitHub issue and comments using `gh issue view $ARGUMENTS
   --comments`.
2. Identify the implementation plan from the comments. The plan is
   expected to follow the `research-eg` output shape, including the
   `Inconclusive / Deferred items` section.
3. If no plan is found in the comments, check the current conversation
   context. If neither is available, suggest running `/research-eg
   $ARGUMENTS` first and stop.

## Step 2 — Extract the discovery contract

From the plan, extract:

- **Plan checklist** (units of work)
- **Impact list** (callers expected to be touched)
- **Implementation guards** (assertions, paired APIs, constructor
  validations)
- **Derivations** (specific examples and their deductive properties,
  already verified in `research-eg` Step 2.B). The list of examples
  whose properties have been derived defines the **derivationally
  cleared example set** — examples not on this list are unverified
  by the plan, regardless of how obvious their properties may seem.
- **Inconclusive items** with their `probe` and `expected branches`
- **Deferred items** with their `reason` and `resolution-point`

These together form the **discovery contract**: the plan-side definition
of what counts as "expected during implementation" vs "research gap".

If the plan has no `Inconclusive / Deferred items` section at all,
treat that as a research gap and stop. Do not synthesize the section
yourself — silently filling it in defeats its purpose. Re-run
`/research-eg` or ask the user to update the plan.

If the plan has no `Derivations` section but the work involves
specific-example fixtures (concrete Hamiltonians, concrete protocol
messages, named worked cases, etc.), treat that as a research gap
on the derivational axis and stop the same way. The absence of a
`Derivations` section means no specific example has been
derivationally cleared — implementing fixtures in that state is
exactly the failure mode the gate exists to prevent.

## Step 3 — Run execution-loop

Invoke the `execution-loop` skill with the plan as the source of truth.
Honor its workflow exactly: Read → Plan → Execute → Review → Fix →
Verify. The wrapper layers the following additional rules on top.

### 3.0 Preflight via todo-check

Before any code change, invoke `todo-check` against the plan to extract
the active `quality-list` items and their setup actions for this work.
Hand the resulting △ rows to execution-loop's Plan step so the unit
checks already include them. Re-invoke `todo-check` between units when
the next unit changes the active item set (e.g., it introduces a new
public API → items 7 and 11 become active).

### 3.0.1 Pre-commit hook recall

Once per session (cache for the duration of the conversation), read
the project's pre-commit configuration to identify the constraints
each hook will enforce. Typical config locations:
`.pre-commit-config.yaml`, `lefthook.yml`, `.husky/`, the `[hooks]`
section of a project task runner (e.g. `Makefile.toml` /
`Justfile`).

For each hook, summarize what it enforces. Do not memorize hook
internals — the goal is to anticipate which checks will run at
commit time, not to reproduce them. Pay particular attention to:

- **Line-count / file-size limits.** Hooks that reject commits when
  a file exceeds a threshold (production vs test, src vs vendored,
  etc.). The correct response to a line-count violation is **file
  split first, content trim only when the trimmed text is genuinely
  redundant** — see `quality-list` item 9. Knowing the limit ahead
  of time avoids the round-trip where a feature lands at the limit,
  pre-commit rejects, and an emergency restructure follows.
- **Linter constraints** that gate commits (e.g., warnings-as-errors
  flags). These need to be visible during implementation, not
  surfaced only at commit time. They feed into Step 3.1 Baseline.
- **Custom checks** specific to the project (banned imports, header
  enforcement, schema validation). Note their existence so the
  implementation does not trip them.

Formatter hooks (rustfmt, prettier, black, clang-format) do not
need anticipation — they reformat in place at commit time, which is
not a meaningful constraint on implementation choices.

Output: a short summary of the binding constraints. Do not paste the
configuration into context.

### 3.0.2 Memory recall

Memory is loaded into context passively at session start, but agents
do not reliably recall passive context when actually writing code —
rules that "everyone knows" still get violated when a hot path
through a code change does not actively reference them. This step
exists to turn passive presence into a deliberate read once per
session, scoped to the current work.

Procedure:

1. Read `MEMORY.md` (the index only; not every linked entry).
2. For each feedback / convention entry whose one-line description
   plausibly intersects the diff scope (the units listed in the plan
   checklist from Step 2), open the full entry and read it.
   Representative triggers:
   - Adding new `pub` symbols → entries on visibility / public
     surface.
   - Adding or modifying tests → entries on test conventions.
   - Writing anything that might reference prior issues / phases
     → entries banning issue numbers / phase markers in code /
     comments / test names.
   - Pre-release work that touches deprecation, aliases, or shims
     → entries on backwards-compat policy.
   - Naming a new helper or wrapper → entries on naming-as-claim.
   - Touching repo conventions → entries on documentation channel
     boundaries (e.g., dev-docs vs main repo).
3. Scope filter: if the unit's description does not plausibly invoke
   the entry's surface, the entry is not active for that unit. Do
   not exhaustively read every memory entry.

Output: a short list of the memory rules active for the current
work, threaded into the plan's per-unit checks alongside the
`quality-list` items extracted by `todo-check`. The active list
becomes part of the discovery contract — a unit that violates an
active memory rule is treated the same way as a unit that violates
a `quality-list` item.

### 3.1 Baseline

Before any code change, build and run existing tests to record
pre-existing failures. Compare against this baseline at every
verification step so new failures are distinguishable from prior state.

Also run the project's linter (e.g., `cargo clippy`, `clang-tidy`,
`ruff check`, `eslint`) and record pre-existing warnings. Linter
output overlaps the test baseline conceptually — both establish what
"clean" means before the work begins, so a new warning introduced by
the change is distinguishable from one that was already present.
Linters that are gated by pre-commit (Step 3.0.1) are particularly
important to baseline, since the gate will reject the commit on any
new violation regardless of pre-existing state.

Formatters are excluded from baseline: they reformat in place at
commit time and produce no warnings to track.

### 3.2 Discovery handling during Execute

If, while executing a unit, an unexpected fact is observed (a behavior,
type, caller, or invariant the plan did not anticipate):

1. **Check the plan's `Inconclusive` items.** Is this discovery an
   expected branch?
   - **Yes** → follow the listed branch. If the branch says
     "re-plan trigger", **stop implementation** and return to research
     for this hypothesis.
   - **No** → continue to step 2.
2. **Check the `Deferred` items.** Is this discovery the
   resolution-point of a deferred concern?
   - **Yes** → surface to user, decide whether to expand scope or keep
     it deferred.
   - **No** → continue to step 3.
3. **Unlisted discovery = research gap.** **Stop.** Do not patch the
   surprise ad-hoc. Surface to the user with: what was observed, why it
   contradicts the plan, what hypothesis class it falls under. Ask
   whether to re-research or to expand the discovery contract
   explicitly.

This rule prevents silent drift between plan and implementation. The
plan's Inconclusive section is the only sanctioned channel for
mid-implementation surprises.

### 3.2.1 Specific-example derivation gate

The Step 3.2 rule above covers behavioral / structural surprises. A
parallel gate covers **the introduction of a new specific example**
during implementation, review, or test addition — even when no
"unexpected fact" has surfaced. This includes:

- A concrete Hamiltonian, fixture, or input case being added to
  satisfy a test plan that named only the abstract spec.
- A worked numerical case being chosen to instantiate a property
  the plan stated abstractly ("multi-sector W bond" → a particular
  choice of operators that supposedly realizes it).
- A protocol message, schema, or replay sequence being filled in
  for a placeholder.
- A test fixture acquiring concrete parameter values where the plan
  only constrained their qualitative properties.

For every such example, before adding the implementation:

1. **Check the derivationally cleared example set** (extracted in
   Step 2 from the plan's `Derivations` section). If the example is
   on the list, it has already been derivationally verified during
   research; proceed.
2. **If the example is not on the list, halt.** Do not add it on
   the strength of its properties feeling obvious. Properties that
   feel obvious are exactly the ones that bypass derivation and
   surface as fixture-construction bugs.
3. **Required action when halted:** Surface to the user with: the
   proposed example, the deductive properties it is being relied on
   to satisfy (e.g., "this Hamiltonian must be U(1)-symmetric, must
   be Hermitian, must be non-diagonal in the chosen basis, must
   exercise the multi-sector path"), and the request to extend the
   plan's `Derivations` section before proceeding. The derivation
   itself is performed in `research-eg` Step 2.B, not in
   implementation.

A `rejected` derivational outcome (the example does not in fact
satisfy the claimed properties) is a plan bug — return to research
and choose a different example. Patching the example
mid-implementation is the failure mode this gate exists to prevent.

Typical failure mode this gate catches: a fixture is chosen during
implementation on the strength of its "obvious" properties, the
properties turn out to be either false (the example violates the
class the test was supposed to constrain it to) or vacuous (the
example is a degenerate case that fails to exercise the path the
test was supposed to cover), and the bug surfaces only at fixture
construction or test-output inspection. The derivation step would
have rejected the example before any code was written.

### 3.3 Quality items during Execute / Review

The substantive rules for implementation guards, test fixture design,
docstring consistency, textual drift sweeps, naming-as-claim, and
plan-vs-actual reconciliation all live in `quality-list` (items 5, 6,
7, 11, 12). Honor whichever items the Step 3.0 preflight marked
active for the current unit.

The wrapper-specific contributions beyond `quality-list` are:

- **Discovery handling** (Step 3.2): unlisted behavioral / structural
  discoveries halt rather than getting ad-hoc-patched.
- **Specific-example derivation gate** (Step 3.2.1): new concrete
  examples introduced during implementation halt unless the plan's
  `Derivations` section already covers them, regardless of how
  obvious their properties seem.

## Step 4 — Run done-check

Invoke the `done-check` skill against the diff. Resolve every `⚠`
before proceeding. If a ⚠ cannot be resolved within the current scope,
file a follow-up issue and document the deferral.

## Step 5 — Final output

After done-check passes:

1. **Plan-vs-actual diff** (from Step 3.6)
2. **Conventional commit message(s)**, generated under the rules of
   `generate-conventional-commit-messages` if the skill is available.
   No HPC paths, no cluster context, no local environment details, no
   line numbers in body.
3. Hand off — do **not** commit unless the user explicitly authorized
   commits. The execution-loop skill enforces this and so does this
   wrapper.
