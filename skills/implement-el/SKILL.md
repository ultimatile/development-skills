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
- **Inconclusive items** with their `probe` and `expected branches`
- **Deferred items** with their `reason` and `resolution-point`

These together form the **discovery contract**: the plan-side definition
of what counts as "expected during implementation" vs "research gap".

If the plan has no `Inconclusive / Deferred items` section at all,
treat that as a research gap and stop. Do not synthesize the section
yourself — silently filling it in defeats its purpose. Re-run
`/research-eg` or ask the user to update the plan.

## Step 3 — Run execution-loop

Invoke the `execution-loop` skill with the plan as the source of truth.
Honor its workflow exactly: Read → Plan → Execute → Review → Fix →
Verify. The wrapper layers the following additional rules on top.

### 3.1 Baseline

Before any code change, build and run existing tests to record
pre-existing failures. Compare against this baseline at every
verification step so new failures are distinguishable from prior state.

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

### 3.3 Implementation guards (from execution-loop's Execute step)

When executing each unit, enforce the guards specified in the plan:

- New invariants → `assert!` / `debug_assert!` / equivalent, never
  comments
- Adding a guard to one method → review all sibling/paired methods for
  consistency
- Constructors → validate all accepted parameters at construction time;
  do not defer validation downstream
- Properties not reliably inferable from existing fields → add an
  explicit field; do not use heuristics

### 3.4 Test fixture design (during Execute / Review)

When designing test fixtures, the rule is **smallest non-trivial input
that exercises all code paths**. Trivial-only fixtures (size-1
containers, identity matrices, dimension-1 cases, single-element MPS,
all-zero or all-equal inputs) make invariant-level bugs trivially pass.

For each parameter in the fixture, ask: "is this the trivial case?" If
so, include at least one variant where it takes its smallest
non-trivial value:

- Scalar → non-unity (e.g., 2.0, not 1.0)
- Dimension → 2 instead of 1 (makes QR/LQ factorization non-trivial)
- Symmetry label → non-identity (flux=1, not flux=0)
- Matrix shape → non-square (2×3, distinguishes row from column)
- Memory layout → include the "other" layout if the API claims
  layout-invariance
- Tensor network site count → enough sites to have a non-edge bulk
  tensor (e.g., 3+ sites for MPS, not 2)

If a test passes with both trivial and non-trivial fixtures, the
invariant is likely correct. If it passes only with the trivial
fixture, that is an implicit specification gap — fix it before review.

### 3.5 Docstring consistency (during Review)

Before declaring a unit done, check docstrings of changed/added public
functions and types:

- Each docstring claim (return type, invariant, precondition,
  postcondition, panic condition) is verified against the
  implementation
- **Callee docstrings the diff relies on** are also checked. If the
  implementation assumes a property of a dependency, the dependency's
  docstring should state it.
- **Textual-surface drift sweep** for renames/removals: `rg
  <old-identifier>` over the touched crate(s). Resolve every hit:
  panic / `expect` / `assert!` messages, error format strings, inline
  comments, doctest blocks, rustdoc links, error-variant `detail`
  strings, README / module-level prose.
- For `mod` / `pub mod` add/remove/rename: re-read the parent module's
  `//!` docstring against the current set of children. Stale "currently
  exposes X" or "lands in a subsequent phase" claims are concerns.
- **Naming-as-claim**: a new identifier whose name asserts a property
  (`random_right_canonical_*`, `is_normalized_*`, `into_canonical_*`)
  must be backed by an implementation that actually provides that
  property. Helpers wrapping a parametrized API call are named after
  the parameter values they pin, not the operational role.

### 3.6 Plan-vs-actual reconciliation

At the end of execution-loop, before declaring done:

1. Compare the **impact list** against actually modified callers:
   - Listed but not modified → missed impact, investigate
   - Modified but not listed → scope creep, investigate
2. Produce a **plan-vs-actual diff**: what changed from the original
   plan and why. Each change must trace to either an `inconclusive`
   probe outcome, a `deferred` resolution, or an explicit re-plan note.

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
