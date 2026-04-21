---
name: implement
description: >
  Implement changes according to an existing plan from a prior research phase.
  Use this skill when a research/investigation has already been completed and the user
  wants to proceed with implementation, says things like "implement the plan",
  "go ahead and implement", "start coding", or wants to execute a previously agreed-upon plan.
  Can optionally accept an issue number as an argument (e.g., /implement 42).
---

# implement

Execute an implementation plan that was produced by a prior research phase.

**Issue:** #$ARGUMENTS

## Step 1 — Retrieve the plan

1. Read the GitHub issue and its comments using `gh issue view $ARGUMENTS --comments`
2. Identify the implementation plan from the comments
3. If no plan is found in the comments, check the current conversation context. If neither is available, suggest running `/research $ARGUMENTS` first.

## Step 2 — Review and confirm

1. **Establish a baseline**: build and run existing tests to record any pre-existing failures
2. Summarize the plan briefly and ask the user for final confirmation before writing code

## Step 3 — Implement

1. Implement the changes according to the plan
2. After each file change, build and run tests using the project's build/test commands documented in CLAUDE.md
3. Iterate until all tests pass and the build is clean. Compare against the baseline to distinguish new failures from pre-existing ones.
4. If the plan has a flaw, note the correction and continue
5. **Enforce implementation guards from the plan:**
   - New invariants must be guarded with assertions, not comments
   - If adding a guard to one API method, review all sibling/paired methods for consistency
   - Constructors must validate all parameters they accept at construction time — do not defer validation to callers
   - If a property cannot be reliably inferred from existing fields, add an explicit field rather than relying on heuristics
6. **Design minimal-but-nontrivial test fixtures.** A fixture whose parameters are all at identity/trivial values (zero, identity matrix, dimension 1, single element) makes invariant-level bugs trivially pass. For each parameter in the fixture, ask: "is this the trivial case?" If so, include at least one fixture variant where that parameter takes its smallest non-trivial value. Examples:
   - Scalar → non-unity (e.g., 2.0, not 1.0)
   - Dimension → 2 instead of 1 (makes QR/LQ factorization non-trivial)
   - Symmetry label → non-identity (e.g., flux=1, not flux=0)
   - Matrix shape → non-square (e.g., 2×3, not 2×2 — distinguishes row from column)
   - Memory layout → include the "other" layout if the API is supposed to be layout-invariant

   The goal is the smallest input that still exercises all code paths — the "construct the smallest non-trivial counterexample" principle from math qualifying exams. If a test passes with both trivial and non-trivial fixtures, the invariant is likely correct. If it only passes with the trivial fixture, you have discovered an implicit specification gap before the review cycle.

## Step 4 — Docstring consistency check

Before committing, verify that docstrings in the changed files are consistent with the actual code behavior. Docstrings are the closest thing to a single source of truth for callers and agents, so drift here silently propagates incorrect assumptions.

1. For each file in the diff, read the docstrings of changed or newly added public functions/types
2. For each docstring claim (return type, invariant, precondition, postcondition, panic condition), verify it against the implementation
3. Also check docstrings of **callee** functions that the diff relies on — if the implementation assumes a property of a dependency (e.g., "qr returns Q with identity flux"), verify that the dependency's docstring actually states this. A missing or contradictory docstring on a dependency is a drift that should be fixed or reported.

If drift is found, fix the docstring (or the code, if the docstring is the intended spec). Do not leave known drift for the review cycle to discover.

## Final Output

After implementation completes:

1. **Review impact list vs actual changes** — compare the callers listed in the plan's impact list against the callers you actually modified. Gaps in either direction (listed but not touched, or touched but not listed) indicate missed impact or scope creep and must be investigated.
2. Show a **plan-vs-actual diff** — what changed from the original plan and why
3. Generate conventional commit message(s) following the same rules as /gen-conventional-commits-message
