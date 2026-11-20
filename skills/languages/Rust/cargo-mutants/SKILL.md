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
| `cargo mutants --list` | Print every mutant name **after** `exclude_re` filtering — your single source of truth for valid regex targets when authoring a new exclude |
| `cargo mutants --list --config <stripped-toml>` | Print mutants using `<stripped-toml>` (a copy of `mutants.toml` with `exclude_re` emptied, every other key kept) — the **validation universe** for checking that existing `exclude_re` anchors still match; diff against `--list` to see exactly what `exclude_re` removed |
| `cargo mutants --list --config <stripped-toml> --exclude-re='<pattern>'` | Add the pattern back on top of the stripped universe — a live pattern shrinks that universe by at least one line; the per-pattern liveness cross-check (must run against the stripped config, not the normal one; use the `=` form so a `-`-leading pattern is not read as a flag) |
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

## Pre-run anchor validation

`exclude_re` anchors rot between runs: a change to the printed name a pattern matches can kill that pattern — a renamed or deleted function, a moved or renamed file under a path prefix, or a cargo-mutants version whose name format differs — and any line or column shift breaks a `file:line:col` anchor. Mutation runs are infrequent (heavy, costly triage), so nothing visits the config between them — the invariant that matters is **the excludes are valid at the moment a run starts**. Validate them just before a run. This is a consumption-time activity, not a per-diff obligation: a refactor that shifts lines does not have to fix the anchors immediately, only the next run does.

This is a different check from the Verification protocol above: that one confirms a *newly authored* exclude takes effect (its target disappears from `--list`); this one confirms *already-authored* excludes have not since gone stale. The two use different commands because `--list` cannot answer the second question, as below.

Validate each `exclude_re` against the mutants that **would exist without `exclude_re`** — not against `cargo mutants --list`:

- `cargo mutants --list` is **post-`exclude_re`**. A live entry removes its own targets, so grepping `--list` for a live pattern returns zero hits — indistinguishable from a stale pattern that matches nothing. Validating against `--list` flags every working entry as stale.
- `--no-config` is also wrong: it drops config-generated mutants. A `-> Result` fn with `error_values` set yields `replace <fn> -> <Ret> with Err(<value>)` mutants that vanish under `--no-config`, so an exclude targeting one is falsely flagged stale.

Build the universe by stripping only `exclude_re`, keeping every other key:

```bash
# 1. Copy the config and empty its exclude_re (keep error_values / examine_re / etc.).
cp .cargo/mutants.toml /tmp/mutants-noexclude.toml
# edit /tmp/mutants-noexclude.toml so that: exclude_re = []
# 2. The validation universe: every mutant in scope of the config, minus the exclude filter.
#    Add --workspace so a member crate's mutants are listed (an unscoped --list shows only
#    the root package when the root is itself a package). Drop --workspace if not a workspace.
#    Do NOT suppress stderr — a config-parse or build failure must surface, not silently
#    leave an empty universe that makes every pattern look stale.
cargo mutants --list --workspace --config /tmp/mutants-noexclude.toml > /tmp/universe.txt
test -s /tmp/universe.txt || { echo "empty universe (the run failed?) — fix before validating"; exit 1; }
# 3. Each exclude_re pattern must match at least one line. rg uses the same Rust regex
#    crate as cargo-mutants, so the match semantics agree (BRE grep does not).
#    Use `rg --` so a pattern beginning with `-` (e.g. `-> bool with true`) is not read as a flag.
rg -- '<pattern>' /tmp/universe.txt
```

The universe must cover **every package any `exclude_re` targets** — staleness is a global property, so the universe has to be at least as broad as the set of excludes you are validating. In a multi-crate workspace, pass `--workspace` (and enumerate `--package` if some members are excluded from the default set): an unscoped `cargo mutants --list` lists only the root package when the root is itself a package, so a valid exclude for a member crate would read as stale. Do not *narrow* the universe with `--file` or a single `--package` — that drops the out-of-scope excludes and falsely flags them stale. An anchor counts as matching nothing only if it matches nothing in this complete set, regardless of which scoped run later consumes it.

Zero hits means a stale anchor — fix it before running. First find, in the universe, the mutants the entry targets — those its equivalence comment names, or, where the comment names none, those its reason covers — tracing each by the code it mutates, since a rename or move changes its printed name; when none of them is current, or the entry has no comment giving a reason, remove the entry — without a reason it carries no equivalence claim. Otherwise the remedy depends on the anchor's kind, not on what made it stale. Replace a `file:line:col` anchor with a name pattern per **Pattern style** — or remove it where Pattern style leaves the mutant unexcluded — rather than giving it a fresh coordinate, which only sets up the next stale anchor. Re-point a name pattern (stale after, e.g., the function or its file renamed or moved, or a change in cargo-mutants' name format) to the current names of the targeted mutants that remain (and path, where the pattern names one), narrowed per **Pattern style** where it would also match a mutant the entry does not target. Then re-assess each targeted mutant's equivalence claim through **Equivalence soundness**: kill with a test each mutant whose claim fails, and remove the entry where that is every mutant it targets, or narrow it per **Pattern style** to the rest.

A nonzero match is necessary but not sufficient. Confirm the matched mutants are the ones the adjacent equivalence comment describes: a moved `file:line:col` coordinate, for one, can match a **different** identically named mutant and silently exclude the wrong target — the same "intended mutant(s) and only those" requirement as the Verification protocol. The cargo-mutants-native cross-check is to add the pattern back on top of the stripped universe: `cargo mutants --list --config <stripped-toml> --exclude-re='<pattern>'` should drop exactly the mutants the pattern is meant to exclude — at least one line, and more when the anchor intentionally covers several (a function-name anchor over a multi-mutant function). An entry with no comment giving a reason resolves as a stale one. Where the comment names no mutant, first name in it the mutants in the universe its reason covers. Then compare the removed lines against the intended target set, not against a fixed count; where they differ, or the anchor is `file:line:col`, resolve the entry as a stale one. Run it against the stripped config, not the normal one — under the normal config the pattern's own targets are already filtered out, so it would never shrink. Use the `--exclude-re=<pattern>` (equals) form: cargo-mutants rejects a space-separated value beginning with `-` (e.g. `-> bool with true`) as an unknown flag.

## Pattern style

Anchor an `exclude_re` entry by name — the mutation and its function (e.g., `replace X with Y in <fn>` or `replace <T>::<method> -> <Ret> with <default>`) — not by `file:line:col`. A position stops pointing at its mutant as soon as an edit before it shifts its line or column — it then matches nothing, and the equivalent mutant comes back as missed, or matches a different identically named mutant — and cargo-mutants reports neither.

When a function-name pattern would also match a mutant it is not meant to exclude, narrow it by where that mutant is:

- **In another file:** prefix the path of the excluded mutant's file (`crates/core/src/solver\.rs:.*replace \+ with \* in step$`). Unlike a position, a path survives edits inside the file.
- **In the same file, in a function whose name starts with the target's:** anchor the end of the function name — with `$` after `in <fn>`; in a whole-body name, by keeping the `->` or `with` that cargo-mutants prints right after it (`replace foo -> u32 with 0`, `replace foo with ()`). (An unanchored prefix is right only when every function it matches is meant to be covered — a pattern ending `in foo` meant for `foo_dense` and `foo_bsp`.)
- **In the same function** — e.g., `let x = !a && !b;` produces two `delete ! in <fn>` mutants whose names are identical aside from their position: move the equivalent expression into a small helper of its own and name the helper in the pattern. The moved mutant's name then ends `in <helper>` (here `delete ! in <helper>`).

Where none of these tells the target apart by name — the code cannot be changed, or another function in the file prints the same name — leave the mutant unexcluded rather than anchoring it by position.

## `exclude_re` vs `#[mutants::skip]`

Both suppress mutants; **Responding to an equivalent mutant** decides when to use one. They are not interchangeable. Where two rows point different ways, the `exclude_re` column wins.

| Use `exclude_re` (config) when | Use `#[mutants::skip]` (attribute) when |
| -- | -- |
| The fn or expression has **specific** mutations that are equivalent, but others are still in scope | The fn is wholly equivalent (e.g., a stub, or all paths inside it are invariants under all operator mutations) |
| The fn is downstream code you don't want to annotate | You own the fn and want the rationale to live next to the code |

`#[mutants::skip]` requires a regular `mutants` dependency (not dev-dependency, since the attribute lives on non-test code). `exclude_re` requires no dependency.

For **optimization-gate predicates** — predicates whose `with true` is dangerous (false-positive enables an unsafe shortcut) but `with false` is safe (false-negative falls back to a slower, correct path) — the `with true` mutant is a coverage gap to kill with a test of the predicate, and the `with false` mutant goes to **Responding to an equivalent mutant**.

## Equivalent mutant criteria

A mutant is "equivalent" when it cannot be distinguished from the original by any test that respects the program's specification. Common categories:

- **Optimization-only**: a predicate that gates a fast path; the mutant disables the fast path but the slow path is correct (e.g., `is_identity_perm -> false` always physically permutes — slower but correct).
- **Unreachable**: code path the type system / parser guarantees never fires (e.g., a `0`-arity match arm in code that always parses ≥1 input). "Unreachable under the current test or feature configuration" does **not** qualify — reachability under a supported config (or a test you could write) only refutes *this* unreachable rationale; the mutant is a coverage gap only if a specification-respecting test can then distinguish it, and may still be equivalent under one of the other criteria here (see **Equivalence soundness**).
- **Default-equivalent values**: a real type whose `Default` matches the function's return on the documented domain (e.g., `<Scalar for f64>::im` returning `0.0` is the same as `Default::default()` for the real subset).
- **Same-output-different-path**: two implementations of the same operation produce identical numerical output by design (e.g., `transpose-then-GEMM` and `GEMM-with-trans-flag` over the same data).
- **Tie-breaking-only**: a comparison whose ordering doesn't affect downstream observable state (e.g., `>` vs `>=` when picking the max of equal values).

When you exclude a mutant as equivalent, **document which mutant it is and why it is equivalent next to the regex** or the `#[mutants::skip]` attribute. Equivalence claims rot when the surrounding code changes; a comment lets a future editor decide whether the claim still holds.

## When `missed` doesn't mean "untested"

A mutant in `missed.txt` means **the test suite passed when the mutation was applied**. That can mean:

1. **Spec gap** — there is no test that observes the mutated behavior at all.
2. **Test gap** — tests exist but use degenerate inputs (size-1, zero, identity) that don't visit the mutated path.
3. **Equivalent mutant** — every observable behavior is preserved by the mutation; the test suite is correct to pass.

Distinguish them before reaching for `exclude_re`. The default is to **kill the mutant by writing a stronger test**, not to exclude it. Reach for `exclude_re` only when you can articulate why no test can distinguish the mutation — and stress-test that articulation against the **Equivalence soundness** checks before trusting it; a claim that survives goes to **Responding to an equivalent mutant**.

A pattern: when both `with true` and `with false` survive on the same predicate, that's almost always two different reasons (one is a coverage gap, one is genuinely equivalent). Don't bulk-exclude — handle each direction independently.

## Equivalence soundness

The criteria above define *what* equivalence is; the checks below stress-test an equivalence claim before you add an equivalence `exclude_re`. They are **falsification attempts** — each tries to expose the mutant as a killable coverage gap — and they are **necessary, not sufficient**: clearing all of them rules out the common coverage-gap signatures, not every one. Crucially, **absence from `caught.txt` is never itself evidence of equivalence**: a mutant you are weighing sits in `missed.txt`, so it is absent from `caught.txt` by definition, whether it is a true equivalent or an as-yet-uncovered coverage gap. The exclusion bar therefore stays the positive standard from **When `missed` doesn't mean "untested"**: you must be able to **prove** that *no* specification-respecting test can distinguish the mutation — a type/parser guarantee of unreachability, an algebraic same-output identity, or an exhaustive argument over a finite input domain. A distinguishing-input search that came up empty only raises confidence: on a non-exhaustively-searchable domain it never establishes that no distinguishing input exists. These checks narrow and pressure that proof; they do not replace it.

This is also a different axis from anchor validity: the **Verification protocol** and **Pre-run anchor validation** confirm a regex hits the intended mutant, whereas these checks probe whether the mutant it hits is truly unkillable. A pattern can be perfectly anchored and still exclude a killable mutant.

Step 1 is a mechanical, command-checkable assertion. Steps 2–4 are judgment-based heuristics — tells and standards that route the decision, deliberately not hard mechanical gates.

1. **Over-exclusion cross-check (mechanical).** The removed set — the mutants an `exclude_re` pattern strips — must contain nothing the test suite kills. Compute it as a set difference, the way **Pre-run anchor validation** diffs to see what a pattern removes: list the stripped universe `U` (`cargo mutants --list --config <stripped-toml>`, plus `--workspace` per that section), list it again with the candidate pattern applied as `K` (`cargo mutants --list --config <stripped-toml> --exclude-re='<pattern>'`), and take `removed_set = U \ K` (e.g. `comm -23` over the two sorted listings). `K` is the *kept* set — the universe minus the pattern's targets — so do **not** intersect `K` itself with `caught.txt`; `K` is non-empty for any healthy config and would falsely read as a swarm of over-exclusions. Intersect `removed_set` with `caught.txt`; the intersection must be empty. A mutant in the intersection was killed by some test — so, provided that test is **specification-respecting** (not flaky, and not asserting an implementation detail such as a mock expecting the fast path), the mutant is not equivalent: an over-exclusion, usually an over-broad function-name anchor sweeping in killable siblings. A hit killed only by a flaky or implementation-detail test is the exception — inspect the failing test before ruling the mutant non-equivalent, since equivalence is defined against specification-respecting tests only. Two provenance requirements make the intersection sound:
   - `caught.txt` must come from a run **capable of killing every mutant in `removed_set`** — one that actually tested each, under a configuration in which a distinguishing test, if one exists, would execute and fail. The single failure mode to rule out: any mutant left **untested** by a run-configuration difference is absent from both `caught.txt` and `missed.txt`, so `removed_set ∩ caught.txt` is empty for the trivial reason that it was never exercised — not because it is equivalent (a false pass). Match `U`'s full run configuration: **source revision, workspace/package scope, feature flags, cargo / test arguments, and test tooling**, and empty all `exclude_re` (a stripped-config run) so no pre-existing exclude masks a candidate target. Each common slip — a run with the candidate exclude already applied, a narrower `--file` / single-`--package` scope, a different feature set, a different test filter — reduces to the same untested-mutant defect.
   - Run `--list` at its default `--line-col=true` so both sides carry the `path:line:col:` prefix and the exact-string intersection holds; `caught.txt` always carries that prefix. A `line:col`-stripped bare-name comparison is a fallback only when locations are genuinely unavailable: identical bare names recur at distinct locations, so it over-reports — its hits are suspects to confirm by location, not a clean verdict.
2. **Sibling-asymmetry tell.** If a structurally symmetric sibling of the target is in `caught.txt` while the target is in `missed.txt`, treat the equivalence claim as suspect: a true equivalence usually makes both siblings equivalent, so the asymmetry signals a coverage gap. This is a tell that warrants investigation, not a verdict that the target is killable.
3. **Guard-gates-an-index check.** If the mutated predicate guards a slice or index access (`shape[..n]`, `v[i]`), a mutation that disables the guard may reach the access with an out-of-range value and **panic** instead of returning the guarded error. A panic is observable, so a test feeding such an input kills the mutant — a coverage gap. When the mutated predicate guards an index, flip the default to coverage-gap; the equivalence claim survives only if the index is *otherwise* guaranteed in range (an earlier validation, a type bound), making the guard genuinely redundant. Identify which slice the disabled guard actually reaches and whether its index can exceed the length: the original audit's error was justifying the mutant via `shape[nrow..]` (the empty, product-1 case — which holds only when `nrow == shape.len()`) when the disabled guard in fact reaches `shape[..nrow]`, out-of-range and panicking once `nrow > shape.len()`. `shape[nrow..]` panics on `nrow > shape.len()` too, so neither slice form is automatically safe — pin the actual access and its reachable index range.
4. **Reachability standard.** "Unreachable under the current test or feature configuration" is **not** equivalence. Reachability only disproves the **Unreachable** rationale; it does not by itself prove a coverage gap, because a reachable mutant can still be equivalent under another criterion (optimization-only, default-equivalent, same-output, tie-breaking). A reachable mutant is a coverage gap precisely when a specification-respecting test can **distinguish** it — exhibit an input on which the mutated and original code observably differ. Reachability is necessary but not sufficient: an optimization-only or same-output mutant executes the reachable path yet leaves every observable identical, so it stays equivalent. When you can produce such a distinguishing input — reachable by a supported config, an in-tree fixture, or a test you could write — it is a coverage gap: leave the mutant in scope and kill it (wire the fixture, enable the feature). Only a type- or parser-guaranteed-unreachable path, or a mutation with mathematically identical output, qualifies as equivalent.

Clearing steps 1–4 means no common coverage-gap signature fired; it does **not** discharge the positive argument. If you cannot state why every specification-respecting test must agree with the original — a type/parser unreachability, a proven same-output identity, or an exhaustive argument over the input domain — the default stands: **kill the mutant with a test**, do not exclude it. A distinguishing-input search that merely came up empty is not such an argument.

## Responding to an equivalent mutant

Once an equivalence claim survives **Equivalence soundness**, decide what to do with the mutant. An equivalent mutant marks a freedom that no specification observes, and the response depends on what that freedom is. Take the first of these that fits:

1. **Remove the code the freedom lives in** when you can change it and its removal changes no input's result, unreachable inputs included, and slows nothing (e.g., a branch with no effect, or a second path no faster than the first).
2. **Test the predicate directly** when the mutant sits in the deciding predicate of an intended optimization and that predicate can be called on its own. A unit test pins the predicate's own specification.
3. **Exclude it** otherwise — a tie-break, a capacity hint, an optimization decided inline, an arm only unreachable inputs reach — with the mechanism **`exclude_re` vs `#[mutants::skip]`** selects (for `exclude_re`, a pattern per **Pattern style**); where Pattern style leaves the mutant unexcluded, it stays in scope.

## Killing surviving mutants — type-axis parametrization

When the stronger-test response of **When `missed` doesn't mean "untested"** must cover multiple trait impls of an identical algebraic property (e.g., `Scalar` for `f32` / `f64` / `Complex<f32>` / `Complex<f64>`), the right shape is a generic test parameterized over the type, not N copy-paste functions.

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

1. Build the validation universe — a copy of `mutants.toml` with `exclude_re` emptied, every other key kept — and capture it: `cargo mutants --list --config <stripped-toml> > /tmp/universe.txt` (see **Pre-run anchor validation** for why `--list` and `--no-config` are both the wrong universe).
2. For each `exclude_re` entry, `rg -- '<pattern>' /tmp/universe.txt` (the `--` keeps a `-`-leading pattern from being read as a flag). Entries matching nothing are dead config (the regex matches no current mutant). Check each entry that matches as **Pre-run anchor validation** checks a nonzero match; step 4 resolves an entry that check resolves as stale.
3. For each entry that does match, re-evaluate the equivalence claim against the current code via the **Equivalence soundness** checks.
4. Resolve each dead entry, each entry the check in step 2 resolves as stale, and each entry with a claim step 3 found false, as **Pre-run anchor validation** resolves a stale one.

A regex that worked when written rots in the ways **Pre-run anchor validation** lists, and cargo-mutants reports none of them.
