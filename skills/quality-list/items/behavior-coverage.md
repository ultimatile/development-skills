# Behavior coverage

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

**Delegation / equivalence tests** — a wrapper asserted equivalent to the path it delegates to — carry three extra strength requirements (each surfaced as a real review finding before being captured here):

- Assert **every component** of the result, not just the first. A component the test receives but no assertion ever reads is unverified even though it travels through the wrapper; for multi-component results (tuples, result structs), each member needs an assertion or an explicit reason it carries nothing checkable.
- A verification predicate must not be **vacuously satisfiable**. A residual identity like `A v = λ v` is satisfied by `v = 0`; a predicate with a degenerate witness needs a guard excluding it (nonzero-norm check, non-empty check) before it counts as verification.
- When the delegate has **siblings that mathematically coincide** on special fixtures (general vs Hermitian matrix exponential on a Hermitian input), at least one fixture must lie where the siblings disagree — otherwise a cross-wired delegation (wrapper calling the sibling instead of its own twin) passes the equivalence test undetected.

**Round-trip (serialize / parse) coverage.** When a diff changes how a persisted or serialized value is **encoded, written, or parsed** — a serialization format, a field's type, or a read / write primitive changes, meaning the encoded representation or the read / write logic changes, not a rename of a field whose encoding is untouched — the coverage axis is not the fixture's input values but the set of **value classes the field's type admits** for each field: a property of the type, so the list is available even when nothing documents it. Require a case per class the code under change can reach — a full round-trip when both the writer and the reader are available in the codebase, or a one-sided emit / parse case per class when only one side exists in the codebase and its counterpart is an external producer or consumer — or a recorded reason a class is unreachable. A single representative value passes the item literally while leaving the rest of the type's range unpinned. The starting list comes from the type: for a floating-point field, an ordinary finite value / zero / negative zero / `+inf` / `-inf` / NaN / subnormal / max / lowest; for an integer field, zero / max / min; for a string field, empty / whitespace-only / a value containing a character the format treats as structural (delimiter, quote, escape, newline). When the same diff swaps a parse primitive, its input-acceptance impact — which classes the new primitive newly rejects or accepts — is `impact-verification`'s concern; this item owns the round-trip test coverage, and both apply rather than one substituting for the other.

When multiple types share semantics — and the language / test framework supports it — generalize via a single type-parametric helper, not per-type duplication.

**Guarantee-broadening diffs (doc-to-test obligation).** When a diff — *including a documentation-only diff* — broadens a behavioral guarantee stated in a docstring or module doc from one symbol to a family of sibling symbols (a hoisted / shared docstring, or wording widened from "this function" to "these functions"), each newly-covered sibling inherits the guarantee's coverage obligation independently: at least one test must exercise the guaranteed behavior for that sibling. Enumerate the symbols the broadened guarantee now covers — resolving the set against the module source, not the diff hunk alone, when the widened wording ("these functions") names the family only implicitly — and, for each, point to a test that exercises it. Shared mechanism is not shared coverage — a cross-wired or diverging sibling is exactly what the per-symbol test catches — so a symbol the doc now guarantees but no test exercises is a concern even when it shares an already-tested member's mechanism.

**Concern conditions:**

- Behavior was added or changed but no test was added
- Tests only exercise trivial / degenerate inputs (no representative case)
- Representative cases tested but corner cases skipped
- Implementation has error / cleanup paths but only the happy path is tested
- Multiple near-identical per-type tests instead of a generic helper
- New code populates state (a field, slot, storage, output buffer) but no test reads that state directly. Transitive consistency — a test that happens to pass through an unrelated helper while the new state is never observed — does not satisfy this. For each newly written-to location, point to at least one assertion that reads it.
- An equivalence / delegation test receives result components that no assertion reads (discarded or ignored bindings)
- A test predicate is satisfiable by a degenerate witness (zero vector, empty collection, identity element) and no guard excludes that witness
- Sibling delegation targets are exercised only on fixtures where the siblings mathematically coincide, leaving cross-wiring undetectable
- A docstring / module-doc edit broadens a behavioral guarantee from one symbol to a family, but some newly-covered sibling has no test exercising that guarantee
- A diff changes how a serialized / persisted value is encoded, written, or parsed, but the tests exercise only a representative value, leaving value classes the field's type admits (per the type's class list) neither round-tripped — nor one-sided-tested, when the counterpart is external — nor recorded as unreachable

**N/A:** the diff is purely mechanical (rename, formatting, file move) or documentation-only, and broadens no behavioral guarantee to a newly-covered sibling symbol. (A docstring hoist that widens a guarantee to a family fails the second conjunct, so it never reaches N/A; a change to how a serialized value is encoded or read fails the first conjunct instead, being neither purely mechanical nor documentation-only, so the round-trip axis never reaches N/A either.)
