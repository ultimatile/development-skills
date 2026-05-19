# Behavior coverage [mechanical]

Tests must exercise the **implemented behavior**, not just trip the code paths. Cover both representatives of the realistic input space and the corner cases the implementation handles — neither alone is sufficient. Identity matrix only, size-1 only, all-zero or all-equal only, diagonal-only when the implementation handles general matrices: these do not visit the behavior the change introduced. (Size-1 / 1×1 is often itself a corner case, not a representative.)

For parameters that gate a **structural split** between code branches — boundary vs interior, terminal vs intermediate, identity vs non-identity, empty vs non-empty — the fixture must include at least one value from each branch the change touches. A boundary value alone exercises only the branch the boundary case reaches, not the interior branch; the test then verifies the boundary case is correct, not that the interior / bulk / general case is correct. Common structural-split parameters:

- Site count / chain length in 1D structured data (MPS, MPO, tensor train): N=2 collapses every site to an edge; use N≥3 so a bulk site is exercised.
- Stage / layer / step index in a multi-stage pipeline of depth D: index = D-1 (the last stage) collapses any "post-stage" machinery to identity; use an interior index 0 ≤ i < D-1 so the post-stage path is exercised.
- Recursion / induction depth: depth = 0 / 1 collapses inductive cases to base cases.
- Region / sector / boundary count in a partitioned space: count = 1 collapses cross-region logic.
- Target index against the end of a sequence: target at sequence-end collapses any "items after target" path.

The general principle: identify every parameter the change introduces or relies on, classify whether its boundary value class trivializes a downstream code path the change touches, and if so include at least one interior value in the fixture set. Apply the same principle to other domains: the smallest fixture that still exercises every code path the change introduced.

When the implementation has error / failure paths (I/O, network, concurrency, fallible operations, cleanup), tests must cover those too — not just the happy path.

Contract-style tests (asserting the invariant the implementation must satisfy, not just its output on one example) automatically satisfy this. Trivial output-comparison tests on identity inputs do not.

When multiple types share semantics — and the language / test framework supports it — generalize via a single type-parametric helper, not per-type duplication.

**Concern conditions:**

- Behavior was added or changed but no test was added
- Tests only exercise trivial / degenerate inputs (no representative case)
- Representative cases tested but corner cases skipped
- Implementation has error / cleanup paths but only the happy path is tested
- Multiple near-identical per-type tests instead of a generic helper
- New code populates state (a field, slot, storage, output buffer) but no test reads that state directly. Transitive consistency — a test that happens to pass through an unrelated helper while the new state is never observed — does not satisfy this. For each newly written-to location, point to at least one assertion that reads it.

**N/A:** the diff is purely mechanical (rename, formatting, file move) or documentation-only.
