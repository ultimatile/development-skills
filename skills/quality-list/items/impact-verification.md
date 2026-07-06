# Impact / caller verification

If the change has a planned impact list (from research or design notes), verify it against the actual diff:

- Every caller listed as affected has been updated (gap = missed impact)
- No caller has been modified that wasn't in the impact list (gap = scope creep)

When no formal impact list exists, manually trace the public symbol's callers and confirm each remains consistent with the change.

Beyond signature compatibility, check for **value-class shifts**: a change — with or without a signature change — can make a value class newly reachable or unreachable in a symbol's returns. Value classes are: zero / non-zero, negative / non-negative, empty / non-empty, `None` / `Some`, NaN / finite, subnormal / normal, the enum-variant set, and bounds stated on the symbol itself (its own docstring or type) — the boundaries consumers typically branch on. Read the shift from diff-visible evidence (an added or removed guard, clamp, or early return; an operation whose result class the diff visibly changes), not whole-program value-range analysis; a value move within the old classes (an off-by-one count fix) or ulp-level noise from reordered arithmetic is not a class shift, unless the noise itself crosses a class boundary (an exactly-zero result becoming tiny non-zero). When a class boundary shifts, the caller trace must additionally check consumers' class-dependent behavior at the class(es) added or removed: reciprocals and guards at a newly-reachable zero or subnormal, match exhaustiveness and emptiness checks at a new variant or newly-empty result. Trace direct consumers; when a direct consumer only stores or returns the value unchanged, follow it one hop to that surface's consumers, and record deeper propagation as the trace boundary instead of chasing it. Documentation claims invalidated by the same shift — stated bounds and closed enumerations alike — are `docstring-drift`'s concern; this item owns consumer code.

**Concern conditions:**

- A listed caller was not updated
- A caller was updated but is not in the impact list (or the deviation is not justified)
- Public symbol changed but no caller trace was performed
- The diff made a value class newly reachable or unreachable in a symbol's returns, and the caller trace did not check class-dependent consumer behavior at the shifted class(es) within the trace bound above

**N/A:** the change touches no symbol with cross-module callers (internal helper with single use site, isolated test, etc.), and no value class shifted. A class shift whose bounded trace finds no affected cross-module consumer is a pass with evidence, not N/A.
