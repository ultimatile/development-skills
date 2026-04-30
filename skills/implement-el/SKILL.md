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

### 3.0 Preflight via todo-check

Before any code change, invoke `todo-check` against the plan to extract
the active `quality-list` items and their setup actions for this work.
Hand the resulting △ rows to execution-loop's Plan step so the unit
checks already include them. Re-invoke `todo-check` between units when
the next unit changes the active item set (e.g., it introduces a new
public API → items 7 and 11 become active).

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

### 3.3 Quality items during Execute / Review

The substantive rules for implementation guards, test fixture design,
docstring consistency, textual drift sweeps, naming-as-claim, and
plan-vs-actual reconciliation all live in `quality-list` (items 5, 6,
7, 11, 12). Honor whichever items the Step 3.0 preflight marked
active for the current unit.

The wrapper-specific contribution beyond `quality-list` is the
**discovery handling** rule in Step 3.2 above: unlisted discoveries
halt rather than getting ad-hoc-patched.

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
