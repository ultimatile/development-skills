---
name: bug-to-contract
description: Promote review findings or bug fixes into contract tests that prevent the entire class of issue from recurring. Use this skill after a review cycle when the user says things like "bug to contract", "what contract is missing", "promote this finding", "postmortem test", or when you notice review findings or fix commits that address symptoms without testing the underlying invariant.
---

# Bug-to-Contract

Review findings and bug fixes address symptoms. This skill asks: **what implicit specification was violated, and is that specification now tested?**

A single fix prevents one bug. A contract test prevents the entire class.

## Inputs

This skill works from two kinds of input, depending on context:

| Context | Input | How to obtain |
|---|---|---|
| Review pipeline (Phase 3) | Review findings from codex/Copilot review | The triage output from Phase 1/2 — especially actionable findings that required fixes |
| Standalone use | Fix commits on the branch | `git log main..HEAD --oneline --grep="fix" -i` or `git diff HEAD~1` |

In the review pipeline, the primary input is **review findings that led to code changes**, not just fix commits. A reviewer saying "this doesn't handle column-major layout" is a stronger signal than a commit message.

## Core procedure

### 1. Collect signals

**From review pipeline:**
- List all actionable findings from Phase 1 (codex) and Phase 2 (Copilot) that resulted in code changes
- For each finding, note: what was the issue, what was changed

**Standalone:**
- Examine fix commit diffs:
  ```bash
  git log main..HEAD --oneline --grep="fix" -i
  git show <commit-sha>
  ```

### 2. Ask the contract question

For each signal, determine:

1. **What broke?** — The specific symptom (wrong output, crash, silent corruption, reviewer complaint, etc.)
2. **What implicit specification was violated?** — The unstated property that users expect to hold. This is the contract. Examples:
   - Memory layout should not affect computation results
   - Operation order in einsum should not affect results (up to floating-point tolerance)
   - Transpose is an involution: `transpose(transpose(A)) == A`
   - Scalar type promotion should be consistent across operations
   - Empty inputs should produce empty outputs with correct shape
3. **Is this contract already tested?** — Search for existing tests that verify this property in general, not just the specific case that broke.

### 3. Search for existing contract tests

Look for tests that verify the identified contract beyond the specific case:

```bash
grep -r "test.*layout\|test.*order\|row_major.*column_major" --include="*.rs" tests/
```

If a test exists that covers the general contract, the contract is already guarded. Report this and stop.

### 4. Classify the contract

Identifying the category helps write a general test rather than a point fix test.

| Category | Description | Example |
|---|---|---|
| Representation invariance | Result is independent of internal representation choices | Memory layout, stride order, storage format |
| Algebraic identity | Mathematical property that must hold | Involution, associativity, commutativity |
| Structural preservation | Shape, type, or metadata properties preserved through operations | Output shape matches specification, dtype preserved |
| Boundary behavior | Correct handling of edge cases | Empty input, zero-size dimension, single element |
| Semantic equivalence | Different spellings of the same operation produce the same result | `einsum("ij,jk->ik", A, B)` == `matmul(A, B)` |

### 5. Propose the contract test

Write a test (or propose one) that verifies the **general contract**, not just the specific case that broke. The test should:

- **Vary the representation**: If it's a layout bug, test with all valid layouts
- **Use multiple inputs**: Not just the one that triggered the issue
- **State the contract explicitly**: The test name and/or comment should name the property being verified

### 6. Check for related contracts

Once a contract is identified, look for related contracts in the same category. If memory layout invariance was violated for GEMM, it could also be violated for SVD, QR, eigendecomposition, solve, etc.

Propose tests for related operations if they are missing.

### 7. Report

Present to the user:

1. **The implicit contract** that was violated (one sentence)
2. **Whether it was already tested** (yes/no + evidence)
3. **Proposed contract test** (code or description)
4. **Related contracts** that may also be untested

## Integration with review pipeline

bug-to-contract is Phase 3 of the review pipeline — after all reviews are clean:

```
Phase 1: Codex review loop → fixes
Phase 2: Copilot review loop → fixes
Phase 3: /bug-to-contract
  Input: all actionable findings from Phase 1 and 2
  Output: contract tests for implicit specifications
```

The key insight is that review findings are **direct evidence of missing contracts**. If a reviewer had to point out an issue, it means the test suite didn't catch it, which means either:
- The contract was tested but the test was too narrow (specific case only)
- The contract was not tested at all (implicit specification gap)

## Important principles

- **General over specific**: A regression test for the exact input that broke is weak. A contract test for the property that was violated prevents the entire bug class.
- **Name the contract**: If you can't name the implicit specification in one sentence, you haven't understood the issue yet.
- **Patterns are escalation-worthy**: A cluster of findings in the same category (e.g., three layout-related issues in one review cycle) indicates a systematically untested contract. Escalate this to the user.
- **Don't boil the ocean**: One contract test per finding is enough. Incremental contract coverage is the goal.
