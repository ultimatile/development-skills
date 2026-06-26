# Claim-vs-behavior drift on untouched documentation

When the diff changes behavior — a function delegating to a third-party library where it previously did the work in-house, a return-value shape shift, an added or removed side effect, control-flow restructuring — existing claims in docstrings, comments, and prose can silently invalidate even when the diff does not touch them. Re-verify each affected claim against the new behavior.

**Trigger.** The diff carries at least one behavior-changing element:

- delegation of logic to a third-party library (`mdformat.text`, `serde_json::from_str`, equivalent) where the local code previously did the work in-house
- return type / shape / value semantics changed (added field, narrowed range, different ordering, eager → lazy, sync → async)
- side effects added, removed, reordered, or moved to a different layer (logging, persistence, network call, mutation)
- control-flow restructuring that changes when an existing branch fires (added preconditions, removed early-returns, swapped guard order)
- API contract change without an identifier rename

**Procedure.** For each behavior-changing element:

1. **Locate claim surfaces.** Include the changed function's own docstring; comments inside the function body; sibling code's comments that name the function; README / docs / ADRs describing the function or its public-facing behavior. Surfaces are in scope even when the diff does not touch them.
2. **Extract falsifiable claims** from each surface — return-value claims, invariant claims, scope claims, exemption claims, normalization claims, complexity claims. Skip purely descriptive prose; focus on claims a reader might depend on.
3. **Verify each claim against current behavior.** Authority order: **execution > current code > tests > docstring > commit message / PR description**. Run an execution probe — construct a minimal call against the working tree and observe the output — when the local code does not by itself prove or disprove the claim. The probe is mandatory when behavior is library-owned; reading the delegating call alone is insufficient.
4. **Fix stale prose** to match new behavior. If prose represents an intentional spec the new code violates, flag the code as a bug instead (requires user confirmation before treating doc-vs-code mismatch as code drift rather than doc drift).

**Author-blindspot mitigation.** Authors who shipped the behavior change read existing prose through their post-change mental model and tacitly correct the drift. A **cold-read pass** on each in-scope surface — treating the prose as if reading the project for the first time — exposes claims the author would otherwise overlook.

**N/A:** the diff is text-only (formatting, doc-only edit, rename without behavior shift), or every behavior-changing element is fully internal with no docstring / comment / README claim referencing the changed surface.
