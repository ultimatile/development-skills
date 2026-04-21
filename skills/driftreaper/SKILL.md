---
name: driftreaper
description: >
  Audit docstrings in the codebase for drift — claims that no longer match the
  actual code behavior. Use this skill when the user says things like
  "check for docstring drift", "audit docstrings", "driftreaper", "find stale docs",
  or after a major refactor that may have left docstrings inconsistent.
  Accepts an optional scope argument: a file path, directory, or module name
  (e.g., /driftreaper crates/ariadnetor-linalg/src/block_sparse_decomp.rs).
  Without arguments, audits the entire workspace.
---

# driftreaper

Audit docstrings for SSOT violations (drift between documentation and code).
Do NOT write production code — only fix docstrings or report findings.

## Why this matters

Docstrings are the primary source of truth for both human callers and AI
agents. When a docstring claims "returns Q with identity flux" but the code
actually returns Q with the original flux, downstream consumers silently
build on a false premise. Unlike broken tests, docstring drift produces no
signal until someone reads the wrong claim and acts on it.

## Step 1 — Determine scope

- **With argument**: audit only the specified file, directory, or module
- **Without argument**: audit the full workspace. Start with public API
  surfaces (`pub fn`, `pub struct`, `pub trait`, `pub enum`) since those
  are what callers and agents read.

## Step 2 — Extract docstring claims

For each public item in scope, read the docstring and extract verifiable claims.
Claims fall into these categories:

| Category | Example | How to verify |
|---|---|---|
| Return type / shape | "returns (Q, R) where Q has flux = identity()" | Read the function body or the callee it delegates to |
| Precondition | "panics if center >= chain.len()" | Search for the assert/panic in the body |
| Postcondition | "after completion, canonical form is Mixed { center }" | Trace the code path to the set_canonical_form call |
| Invariant | "Q is isometric regardless of flux" | Check tests or mathematical reasoning |
| Delegation claim | "uses qr_block_sparse internally" | Grep the body for the call |
| Complexity | "O(n) additional cost" | Analyze the code structure |

Skip purely descriptive text ("This function does X") — focus on
**falsifiable claims** that a caller might depend on.

## Step 3 — Verify each claim

For each extracted claim:

1. **Read the code** that the claim describes. Follow the actual control flow,
   not what the docstring says the flow is.
2. **Cross-reference with tests** — if a test exercises the claimed behavior,
   the claim is corroborated (though not proven; the test itself could be
   trivial). If no test covers the claim, note this as an untested claim.
3. **Classify the result**:
   - **Verified**: code matches claim, optionally backed by a test
   - **Drifted**: code contradicts claim — the docstring is stale or wrong
   - **Untested**: claim is plausible but no test or code path directly
     confirms it — flag for manual review
   - **Ambiguous**: docstring is vague enough to be technically correct but
     misleading — suggest a more precise wording

## Step 4 — Fix or report

- **Drifted**: fix the docstring to match the code (or flag if the code
  should be fixed to match the docstring — that is a bug, not drift).
  For each fix, state what the old claim was and what the corrected claim is.
- **Untested**: report as a finding. These are candidates for contract test
  elevation via `/bug-to-contract`.
- **Ambiguous**: propose a more precise wording. Do not change without user
  confirmation if the intended meaning is unclear.

## Step 5 — Report

Present findings grouped by severity:

1. **Drifted** (fixed) — list each correction with file:line, old claim, new claim
2. **Untested** — claims that could not be verified by code or tests
3. **Ambiguous** — vague docstrings with proposed rewording
4. Summary statistics: files audited, claims checked, drifts found

## Scope guidance

For large codebases, prioritize:

1. **Functions that other modules call** — drift here propagates farthest
2. **Recently changed files** (`git log --since="2 weeks ago" --name-only`)
3. **Functions with complex return types** (tuples, Result, custom structs)
   — these are most likely to have stale shape/invariant claims
4. **Decomposition / factorization functions** — their output properties
   (flux, direction, rank, isometry) are subtle and callers depend on
   exact claims

## Principles

- **Code is ground truth, not docstrings.** When code and docstring disagree,
  the code is almost always right and the docstring is stale. The exception
  is when the docstring represents an intentional spec and the code has a
  bug — but that requires explicit user confirmation.
- **One drift fix per claim.** Do not batch unrelated fixes. Each correction
  should be independently reviewable.
- **Don't add docstrings.** This skill audits and fixes existing docstrings.
  Adding docstrings to undocumented functions is a separate task.
