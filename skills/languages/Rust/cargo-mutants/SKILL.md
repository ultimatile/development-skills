---
name: cargo-mutants
description: Configure and run cargo-mutants for Rust mutation testing — invoking runs, reading mutants.out, writing exclude_re patterns matching cargo-mutants' mutant-name format, and choosing exclude_re vs #[mutants::skip].
---

# cargo-mutants

`cargo-mutants` mutates Rust source and re-runs the test suite to find spec gaps. The trap is not the tool itself but the gap between **what you think a mutant is named** and **what cargo-mutants actually emits** — that gap silently turns `exclude_re` entries into dead config.

## Running mutation runs

| Command | Purpose |
| -- | -- |
| `cargo mutants --file <path>` | Run mutations on one file (fast iteration) |
| `cargo mutants --regex '<pattern>'` | Restrict to mutants whose name matches |
| `cargo mutants --list` | Print every mutant name **after** `exclude_re` filtering — your single source of truth for valid regex targets |
| `cargo mutants --list-skipped` | Print mutants that `exclude_re` / `#[mutants::skip]` removed |
| `cargo mutants --jobs N` | Parallelize across N rebuilds (CPU-bound) |
| `cargo mutants --no-shuffle` | Stable order; required when comparing two runs |
| `cargo mutants --baseline=skip` | Skip the unmutated baseline (only safe if you ran it manually) |

Output lives in `mutants.out/`:

| File | Meaning |
| -- | -- |
| `caught.txt` | Test suite failed — mutant killed |
| `missed.txt` | Test suite passed — **spec gap** (or equivalent mutant) |
| `unviable.txt` | Code didn't compile — usually a type-system save |
| `timeout.txt` | Tests hung — most often LAPACK/BLAS on garbage matrices; tune `timeout_multiplier` |
| `outcomes.json` | Machine-readable outcomes for the whole run |
| `mutants.json` | All mutants the planner generated, including filtered ones |

## Forbidden flag: `--in-place`

**Never pass `--in-place`.** It mutates the working tree directly, so any abnormal termination leaves the source holding the last applied mutation, and subsequent `cargo` commands operate on corrupted source. Default mode copies the workspace to a temp directory before mutating, leaving the original tree untouched.

## Mutant name format — the trap

`exclude_re` matches against the **full mutant name string** as printed by `cargo mutants --list`. The string format depends on the mutation kind:

| Mutation kind | Mutant name format | Example |
| -- | -- | -- |
| Binary operator in fn body (`+ → -`, `&& → \|\|`, `== → !=`, `< → >`, etc.) | `replace X with Y in <fn>` | `replace == with != in einsum_pair` |
| `delete !` (boolean negation) | `delete ! in <fn>` | `delete ! in contract_to_tensor` |
| `delete match arm <pat>` | `delete match arm <pat> in <fn>` | `delete match arm 0 in einsum` |
| Free fn / private fn returning a primitive — replace whole body with constant | `replace <fn> -> <Ret> with <const>` (no `in <fn>`) | `replace is_identity_perm -> bool with false` |
| Inherent method (`impl T`) — replace body with default value | `replace <T>::<method> -> <Ret> with <default>` | `replace NativeBackend::shared -> Arc<NativeBackend> with Arc::new(Default::default())` |
| Trait method body — replace body with default value | `replace <X as Trait>::<method> -> <Ret> with <default>` | `replace <NativeBackend as ComputeBackend>::is_available -> bool with true` |

Each line is prefixed with the source location: `path:line:col: <name>`.

The most common mistake is **assuming `in <fn>` always appears**. It does not — it only appears for body-internal mutations (binary ops, `delete !`, match arms). Whole-body replacements name the function as part of the **subject** of `replace`, not after `in`.

Concrete failure: a pattern like

```toml
"replace .* with false in is_identity_perm"
```

matches **nothing**, because cargo-mutants emits

```
replace is_identity_perm -> bool with false
```

— note the absence of ` in is_identity_perm`. The pattern is dead config; the mutant survives forever and the regex looks reasonable in code review.

## Verification protocol

**Before adding any `exclude_re` entry**, prove it matches the intended mutant(s) and only those:

1. Run `cargo mutants --list` and grep for the intended target string.
2. Apply the `exclude_re` change.
3. Run `cargo mutants --list` again — the targeted mutants should be **gone** from the list, and only the targeted ones should be gone.

A useful diff:

```bash
cargo mutants --list 2>/dev/null | sort > /tmp/before.txt
# (edit mutants.toml)
cargo mutants --list 2>/dev/null | sort > /tmp/after.txt
diff /tmp/before.txt /tmp/after.txt   # only the lines you intended to remove should appear
```

If a regex looks plausible but matches **nothing** in `--list`, it's dead config — usually a format-mismatch trap.

## Pattern style: line:col vs function-name

Two anchoring strategies, with different trade-offs:

**Function-name-based** (`replace X with Y in <fn>$` or `<T>::<method>`):

- Stable across line-number drift.
- **Fails when multiple operands on the same expression generate identical names** — e.g., `let x = !a && !b;` produces two `delete ! in <fn>` mutants whose names are identical aside from the `:line:col` prefix. A function-name regex would unintentionally exclude both.

**Line:col-anchored** (`<file>:<line>:<col>: <suffix>`):

- Surgical: kills exactly one mutant.
- Fragile: silently breaks on line/column shifts. Always pair with a comment explaining what's at that location and why it's equivalent, so a future editor can re-anchor after a refactor.

Rule of thumb: prefer function-name when the mutant name is unique within its function. Fall back to line:col when multiple equivalent positions share a name. Group line:col patterns under a clearly labeled "fragile / line-anchored" section in `mutants.toml` to signpost the maintenance burden.

## `exclude_re` vs `#[mutants::skip]`

Both suppress mutants. They are not interchangeable.

| Use `exclude_re` (config) when | Use `#[mutants::skip]` (attribute) when |
| -- | -- |
| The fn or expression has **specific** mutations that are equivalent, but others are still in scope | The fn is wholly equivalent (e.g., a stub, or all paths inside it are invariants under all operator mutations) |
| You want surgical line:col anchoring | You want function-level granularity and don't care about precision |
| The fn is downstream code you don't want to annotate | You own the fn and want the rationale to live next to the code |

`#[mutants::skip]` requires a regular `mutants` dependency (not dev-dependency, since the attribute lives on non-test code). `exclude_re` requires no dependency.

For **optimization-gate predicates** — predicates whose `with true` is dangerous (false-positive enables an unsafe shortcut) but `with false` is safe (false-negative falls back to a slower, correct path) — prefer **direct unit tests on the predicate** over either skip mechanism. A unit test pins the predicate's spec rather than papering over the asymmetry, and it kills both `with true` and `with false` mutants in one assertion.

## Equivalent mutant criteria

A mutant is "equivalent" when it cannot be distinguished from the original by any test that respects the program's specification. Common categories:

- **Optimization-only**: a predicate that gates a fast path; the mutant disables the fast path but the slow path is correct (e.g., `is_identity_perm -> false` always physically permutes — slower but correct).
- **Unreachable**: code path the type system / parser guarantees never fires (e.g., a `0`-arity match arm in code that always parses ≥1 input).
- **Default-equivalent values**: a real type whose `Default` matches the function's return on the documented domain (e.g., `<Scalar for f64>::im` returning `0.0` is the same as `Default::default()` for the real subset).
- **Same-output-different-path**: two implementations of the same operation produce identical numerical output by design (e.g., `transpose-then-GEMM` and `GEMM-with-trans-flag` over the same data).
- **Tie-breaking-only**: a comparison whose ordering doesn't affect downstream observable state (e.g., `>` vs `>=` when picking the max of equal values).

When you label a mutant equivalent, **document the reason next to the regex**. Equivalence claims rot when the surrounding code changes; a comment lets a future editor decide whether the claim still holds.

## When `missed` doesn't mean "untested"

A mutant in `missed.txt` means **the test suite passed when the mutation was applied**. That can mean:

1. **Spec gap** — there is no test that observes the mutated behavior at all.
2. **Test gap** — tests exist but use degenerate inputs (size-1, zero, identity) that don't visit the mutated path.
3. **Equivalent mutant** — every observable behavior is preserved by the mutation; the test suite is correct to pass.

Distinguish them before reaching for `exclude_re`. The default is to **kill the mutant by writing a stronger test**, not to exclude it. Reach for `exclude_re` only when you can articulate why no test can distinguish the mutation.

A pattern: when both `with true` and `with false` survive on the same predicate, that's almost always two different reasons (one is a coverage gap, one is genuinely equivalent). Don't bulk-exclude — handle each direction independently.

## Killing surviving mutants — type-axis parametrization

When the stronger-test response above must cover multiple trait impls of an identical algebraic property (e.g., `Scalar` for `f32` / `f64` / `Complex<f32>` / `Complex<f64>`), the right shape is a generic test parameterized over the type, not N copy-paste functions.

```rust
fn conj_involutive<T: Scalar>(x: T) {
    assert_eq!(T::conj(T::conj(x)), x);
}

#[test] fn conj_involutive_f32() { conj_involutive::<f32>(1.5); }
#[test] fn conj_involutive_f64() { conj_involutive::<f64>(1.5); }
#[test] fn conj_involutive_c32() { conj_involutive::<Complex<f32>>(Complex::new(1.5, 2.5)); }
#[test] fn conj_involutive_c64() { conj_involutive::<Complex<f64>>(Complex::new(1.5, 2.5)); }
```

This is **type-axis** parametrization, not test-logic abstraction. The algebraic identity is the same statement for all `T`; only the type varies. Per-type copy-paste of the same `assert_eq!` is duplication along a single axis, not the "tests document behavior independently" pattern that argues against DRY-in-tests.

Reserve this for properties that genuinely hold across the type set with the same shape. If `f32` and `f64` need different tolerances, or `Complex` needs an additional `im` check, write the test fully per type — type-axis parametrization is only the right tool when the property is the same statement for every `T`.

## `mutants.toml` knobs

Beyond `exclude_re`:

| Key | Purpose |
| -- | -- |
| `examine_re` | Allowlist: only test mutants whose names match. Inverse of `exclude_re`. |
| `examine_globs` / `exclude_globs` | File-pathname filters (independent of mutant names). |
| `timeout_multiplier` | Multiply baseline test time. Default 5.0; for FFI-heavy crates 2.0 is often enough and saves cycles. |
| `additional_cargo_args` / `test_tool` | Customize the test runner invocation. |
| `minimum_test_timeout` | Floor for the auto-tuned timeout, in seconds. |

`timeout_multiplier` should be tuned only after observing actual baseline test time; setting it too low produces false-positive timeouts (`timeout.txt` entries that aren't really runaway).

## Audit workflow

When inheriting an existing `mutants.toml`, audit it:

1. `cargo mutants --list-skipped` — every line is a mutant currently being suppressed.
2. For each `exclude_re` entry, verify it appears as a reason in `--list-skipped`. Entries that don't appear are dead config (the regex doesn't match any current mutant).
3. For each entry that does match, re-evaluate the equivalence claim against the current code.
4. Remove dead entries; rewrite or re-anchor entries whose claims no longer hold.

A regex that worked when written can rot in two ways: the underlying code changed (mutant no longer exists), or cargo-mutants' name format evolved between versions. Both produce silent dead patterns.
