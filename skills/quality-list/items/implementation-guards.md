# Implementation guards [mechanical]

Invariants that must hold at runtime are encoded as **assertions** (`assert!` / `debug_assert!` / equivalent), not docstring claims or comments. When a guard is added to one API method, its paired / sibling methods get the same guard for consistency. Constructors validate every parameter they accept at construction time — never defer validation to a setter or to the caller. Properties that cannot be reliably inferred from existing fields get an explicit field, not a heuristic.

**Public-function entry validation.** The constructor rule above generalizes to every public function. Any parameter that gates downstream allocation, iteration, or arithmetic — sizes, counts, ranks, dimensions, integer exponents that feed `2^n` / `4^n` / similar overflow-prone arithmetic, finite collections that must be non-empty (Kraus operators, basis matrices, sample lists), shape constraints (square / matching dimensions) — is validated at the function entry with a clear, semantic error type (`ArgumentError`, `ValueError`, `IllegalArgumentException`, equivalent), not deferred to a downstream call. Deferring fails the user in two ways: the surfaced error names the inner function instead of the user-called entry, and certain bad inputs (overflowed bounds → empty range, silently-allocated zero buffer) bypass error paths entirely and produce *wrong* output instead of failing. When several public functions share the same parameter shape (`n`-qubit count, batch size, dimensionality), validate each at its own entry with the same predicate — even if the inner call would catch it — so that the user-facing error message points at the function the user actually called.

**Concern conditions:**

- A new invariant is documented in a comment but not asserted in code
- One sibling method has a guard, others don't
- Constructor accepts a parameter but defers validation downstream
- Public non-constructor function accepts a size / count / rank / dimension / exponent / non-empty-collection / shape parameter without validating it at the entry, deferring the failure to a downstream call (or, worse, allowing the bad input to silently produce empty / overflowed / wrong-shaped output)
- Multiple public entries share a parameter constraint but only a subset validate it; users of the unguarded entries see the inner call's error message rather than one naming the entry they invoked
- A piece of state is reconstructed from heuristics on existing fields rather than tracked explicitly
- A function whose docstring documents a runtime contract (panics, raises, aborts, throws on invalid input) uses an assertion that is compiled out / disabled in release / optimized / production builds for the contract-triggering check. The documented contract is silently unenforced where the assertion is disabled. Language instances: Rust `debug_assert!`, C/C++ `assert()` under NDEBUG, Python `assert` under `-O`, Java `assert` (off by default), Julia `@boundscheck` under `@inbounds` / `--check-bounds=no`.

**N/A:** the change introduces no new invariants (pure data movement, simple delegation, formatting).
