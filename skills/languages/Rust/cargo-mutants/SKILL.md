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
| `cargo mutants --list` | Print every mutant name **after** `exclude_re` filtering — what a run under the current config will test; a new exclude is checked against the stripped universe instead (see **Verification protocol**) |
| `cargo mutants --list --workspace --config <stripped-toml>` | Print mutants using `<stripped-toml>` (a copy of `mutants.toml` with `exclude_re` emptied, every other key kept) — the **validation universe** for checking a new exclude and for checking that existing `exclude_re` anchors still match; diff against `--list --workspace` to see exactly what `exclude_re` removed |
| `cargo mutants --list --workspace --config <stripped-toml> --exclude-re='<pattern>'` | Add the pattern back on top of the stripped universe — a live pattern shrinks that universe by at least one line; the per-pattern liveness cross-check (must run against the stripped config, not the normal one; use the `=` form so a `-`-leading pattern is not read as a flag) |
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
| Trait impl method — replace body with default value | `replace <impl <Trait> for <X>>::<method> -> <Ret> with <default>` | `replace <impl ComputeBackend for NativeBackend>::is_available -> bool with true` |
| Trait default method body — replace body with default value | `replace <Trait>::<method> -> <Ret> with <default>` | `replace ComputeBackend::is_available -> bool with true` |

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

**Before adding any `exclude_re` entry**, prove it matches the intended mutant(s) and only those. Measure it against the validation universe — every mutant in scope of the config with `exclude_re` emptied, across the whole workspace — not against `cargo mutants --list`. That listing is already filtered by the existing excludes, so a sibling one of them removes never shows, and in a workspace whose root is itself a package it lists only the root package, so a sibling in a member package never shows either.

1. Build the stripped config, `/tmp/mutants-noexclude.toml`: a copy of `.cargo/mutants.toml` with `exclude_re = []`, every other key kept (see **Pre-run anchor validation** for why no other key may go). For a crate's first exclude, with no `mutants.toml` yet, the stripped config is an empty file, since `--config` on a missing file fails.
2. Write a second copy of the stripped config, `/tmp/mutants-candidate.toml`, whose `exclude_re` holds only the new entry, exactly as it will appear in `mutants.toml` — so its TOML encoding is checked too (see **Pattern style**).
3. List both with `--workspace` and take the removed set, the universe minus the kept listing. It must hold exactly the intended mutants, at least one. Then add the entry to `mutants.toml`.

```bash
rm -f /tmp/universe.sorted /tmp/kept.sorted
cargo mutants --list --workspace --config /tmp/mutants-noexclude.toml > /tmp/universe.raw && test -s /tmp/universe.raw && sort /tmp/universe.raw > /tmp/universe.sorted || { echo "universe listing failed or empty"; exit 1; }
cargo mutants --list --workspace --config /tmp/mutants-candidate.toml > /tmp/kept.raw && sort /tmp/kept.raw > /tmp/kept.sorted || { echo "candidate listing failed"; exit 1; }
test -f /tmp/universe.sorted && test -f /tmp/kept.sorted && test -z "$(comm -13 /tmp/universe.sorted /tmp/kept.sorted)" || { echo "a listing is missing, or the kept listing holds mutants the universe lacks"; exit 1; }
comm -23 /tmp/universe.sorted /tmp/kept.sorted   # the removed set: only the intended mutants may appear
```

The listings keep stderr, so a config that fails to parse prints its error, and a failed or empty listing writes no sorted file, so the comparison cannot read an empty or earlier listing as its result — whether the lines run as one script or one at a time. `--list` prints in source order, so both sides are sorted before `comm`. Drop `--workspace` if the project is not a workspace.

If the removed set is **empty**, the pattern is dead config — usually a format-mismatch trap or a TOML encoding slip. If it holds more than the intended mutants, narrow the pattern per **Pattern style**.

## Pre-run anchor validation

`exclude_re` anchors rot between runs: a renamed or deleted function, or a removed expression, kills a name anchor, a moved file kills an anchor carrying the file's path, and any line shift kills a `file:line:col` anchor an inherited config may still hold. Mutation runs are infrequent (heavy, costly triage), so nothing visits the config between them — the invariant that matters is **the excludes are valid at the moment a run starts**. Validate them just before a run. This is a consumption-time activity, not a per-diff obligation: a refactor that shifts lines does not have to fix the anchors immediately, only the next run does.

This is a different check from the **Verification protocol** above, over the same universe: that one confirms a *newly authored* exclude removes exactly its intended targets; this one confirms *already-authored* excludes have not since gone stale. Neither can be answered from `cargo mutants --list`, as below.

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

The universe must cover **every package any `exclude_re` targets** — staleness is a global property, so the universe has to be at least as broad as the set of excludes you are validating. In a multi-crate workspace, pass `--workspace` (and enumerate `--package` if some members are excluded from the default set): an unscoped `cargo mutants --list` lists only the root package when the root is itself a package, so a valid exclude for a member crate would read as stale. Do not *narrow* the universe with `--file` or a single `--package` — that drops the out-of-scope excludes and falsely flags them stale. An anchor is stale only if it matches nothing in this complete set, regardless of which scoped run later consumes it.

Zero hits means a stale anchor — fix it before running. The remedy depends on the cause: if a line shift moved a `file:line:col` anchor, do not refresh the coordinate, which only sets up the next stale anchor — replace it with a name pattern written per **Pattern style**, carrying the equivalence comment over. Where the anchor was positional because a same-named mutant shares its file, that replacement is a source change and a re-triage of the moved mutant (Pattern style's same-file case), not a config edit. If the function was renamed or deleted, its file moved, or cargo-mutants changed its name format, the named mutant is gone — re-point the pattern to the current mutant name and path or remove it, and re-assess whether the equivalence claim still holds.

A nonzero match is necessary but not sufficient. For a `file:line:col` anchor, confirm the matched mutant is the one the adjacent equivalence comment describes: a moved coordinate can match a **different** identically named mutant and silently exclude the wrong target — the same "intended mutant(s) and only those" requirement as the Verification protocol. Such an anchor takes the same replacement as a stale one. The cargo-mutants-native cross-check is to add the pattern back on top of the stripped universe: `cargo mutants --list --workspace --config <stripped-toml> --exclude-re='<pattern>'` should drop exactly the mutants the pattern is meant to exclude — at least one line, and more when the pattern intentionally covers several (a name several equivalent mutants share, or a pattern without `$` meant to cover several functions). Compare the removed lines against the intended target set, not against a fixed count. Run it against the stripped config, not the normal one — under the normal config the pattern's own targets are already filtered out, so it would never shrink. Use the `--exclude-re=<pattern>` (equals) form: cargo-mutants rejects a space-separated value beginning with `-` (e.g. `-> bool with true`) as an unknown flag.

## Pattern style

An `exclude_re` entry names the mutation and its function: the whole name as cargo-mutants prints it, anchored at both ends.

```text
^[^:]*:[0-9]+:[0-9]+: <name>$
```

- `<name>` is the full printed name, mutation text included (`replace + with * in lanczos_smallest`, `replace is_identity_perm -> bool with false`), escaped as below, with the qualifiers cargo-mutants prints for inline modules and impls (`a::f`, `A::g`, `<impl T for A>::h`; see **Mutant name format**). The file's own module is not part of the name: a `fn foo` in `src/lib.rs` and one in `src/other.rs` both print `in foo`.
- The location prefix, generic in its coordinates, pins the name's start, so a mutant whose name merely contains the target's — a `delete match arm` for a string literal that holds it — is not swept in. `$` pins the end, so `foo_dense` and the nested `foo::inner` are not swept in for `foo`. Drop `$` only when the prefix match is meant to cover several functions (a pattern ending `in foo` meant to cover `foo_dense` and `foo_bsp`).
- `[^:]*` matches any path in a workspace whose paths hold no `:`. Where the target's path, or any other path in the workspace, holds `:`, write the target's escaped path in its place.
- Escape the regex metacharacters in the literal path and name: `.`, `+`, `*`, `?`, `|`, `(`, `)`, `[`, `]`, `{`, `}`, `^`, `$`, `\`.
- In `.cargo/mutants.toml`, write the regex as a TOML literal string, `'...'`, which keeps every `\` as written. When the regex holds a `'`, use a multi-line literal string, `'''...'''`; when it holds `'''`, use a basic string, `"..."`, with each `\` doubled and each `"` written `\"`. A basic string reads `\` as a TOML escape, so `"\."` fails to parse.
- The shell commands this skill shows put a pattern in single quotes (`rg -- '<pattern>'`, `--exclude-re='<pattern>'`), which a pattern holding `'` breaks. Pass such a pattern through a file instead (`rg -f <file>` reads one pattern per line), or check it through the candidate config of the **Verification protocol**.

Do not anchor by position. A `file:line:col` pattern stops matching as soon as an edit shifts the lines above it, and nothing reports the dead entry: the equivalent mutant just comes back as missed in the next run, or the coordinate lands on a different identically named mutant and silently excludes it.

### When the pattern still matches a killable mutant

Under this form, a pattern matches only mutants with the identical printed name. When one of them is killable — **Equivalence soundness** step 1 finds it in `caught.txt`, or it fails the criteria below — narrow by where it is:

- **In another file:** put the escaped path of the excluded mutant's file, as `--list` prints it relative to the workspace root, in place of `[^:]*`, as in `^crates/core/src/solver\.rs:[0-9]+:[0-9]+: replace \+ with \* in step$`. Unlike a position, a path survives edits.

- **In the same file** — the same function, a closure inside it (a closure's mutants take the enclosing function's name), or a same-named block-local function: no pattern separates them. Make a behavior-preserving source change that gives the equivalent mutant a name of its own. Move the equivalent expression into a small helper, which cargo-mutants then names `replace X with Y in <helper>`; or rename a same-named function whose whole-body mutant collides, since moving its body out leaves that mutant under the old name.

  Then triage every mutant of the helper in the helper — the moved one and the helper's own whole-body mutants (`replace <helper> -> bool with true` and the like) — against what the helper itself returns, because the helper can be called on its own. A mutant that was equivalent only through its caller's context, such as a loop bound, is killable there by a direct test: `j + 1 == max_iter` → `j * 1 == max_iter` is equivalent inside `for j in 0..max_iter`, but moved into `fn is_last_iteration(j: usize, max_iter: usize) -> bool`, the call `is_last_iteration(0, 1)` returns `true` and its mutant `false`. Exclude a mutant under the helper's name only if it is still equivalent in the helper.

  Where the code cannot be changed, leave the mutant unexcluded. Reported as missed, it costs a triage each run, whereas an over-matching pattern hides a killable mutant from every run.

## `exclude_re` vs `#[mutants::skip]`

Both suppress mutants, and either one is the exclusion response of **Responding to an equivalent mutant**, reached once removing the code and testing a predicate directly do not fit. They are not interchangeable.

| Use `exclude_re` (config) when | Use `#[mutants::skip]` (attribute) when |
| -- | -- |
| The fn or expression has **specific** mutations that are equivalent, but others are still in scope | The fn is wholly equivalent (e.g., a stub, or all paths inside it are invariants under all operator mutations) |
| The fn is downstream code you don't want to annotate | You own the fn and want the rationale to live next to the code |

`#[mutants::skip]` requires a regular `mutants` dependency (not dev-dependency, since the attribute lives on non-test code). `exclude_re` requires no dependency.

For **optimization-gate predicates** — predicates whose `with true` is dangerous (false-positive enables an unsafe shortcut) but `with false` is safe (false-negative falls back to a slower, correct path) — neither mechanism comes first: see the predicate-test response in **Responding to an equivalent mutant**.

## Equivalent mutant criteria

A mutant is "equivalent" when it cannot be distinguished from the original by any test that respects the program's specification. Common categories:

- **Optimization-only**: a predicate that gates a fast path; the mutant disables the fast path but the slow path is correct (e.g., `is_identity_perm -> false` always physically permutes — slower but correct).
- **Unreachable**: code path the type system / parser guarantees never fires (e.g., a `0`-arity match arm in code that always parses ≥1 input). "Unreachable under the current test or feature configuration" does **not** qualify — reachability under a supported config (or a test you could write) only refutes *this* unreachable rationale; the mutant is a coverage gap only if a specification-respecting test can then distinguish it, and may still be equivalent under one of the other criteria here (see **Equivalence soundness**).
- **Default-equivalent values**: a real type whose `Default` matches the function's return on the documented domain (e.g., `<impl Scalar for f64>::im` returning `0.0` is the same as `Default::default()` for the real subset).
- **Same-output-different-path**: two implementations of the same operation produce identical numerical output by design (e.g., `transpose-then-GEMM` and `GEMM-with-trans-flag` over the same data).
- **Tie-breaking-only**: a comparison whose ordering doesn't affect downstream observable state (e.g., `>` vs `>=` when picking the max of equal values).

When the response to an equivalent mutant is exclusion (see **Responding to an equivalent mutant**), **document the reason next to the `exclude_re` entry or the `#[mutants::skip]` attribute**. Equivalence claims rot when the surrounding code changes; a comment lets a future editor decide whether the claim still holds.

## When `missed` doesn't mean "untested"

A mutant in `missed.txt` means **the test suite passed when the mutation was applied**. That can mean:

1. **Spec gap** — there is no test that observes the mutated behavior at all.
2. **Test gap** — tests exist but use degenerate inputs (size-1, zero, identity) that don't visit the mutated path.
3. **Equivalent mutant** — every observable behavior is preserved by the mutation; the test suite is correct to pass.

Distinguish them before reaching for `exclude_re`. The default is to **kill the mutant by writing a stronger test**, not to exclude it. Reach for `exclude_re` only when you can articulate why no test can distinguish the mutation — and stress-test that articulation against the **Equivalence soundness** checks before trusting it. Even then, exclusion is the response only when removing the code and testing a predicate directly do not fit (see **Responding to an equivalent mutant**).

A pattern: when both `with true` and `with false` survive on the same predicate, that's almost always two different reasons (one is a coverage gap, one is genuinely equivalent). Don't bulk-exclude — handle each direction independently.

## Equivalence soundness

The criteria above define *what* equivalence is; the checks below stress-test an equivalence claim before you act on it (see **Responding to an equivalent mutant**); step 1 checks the candidate pattern when that response is an `exclude_re`. They are **falsification attempts** — each tries to expose the mutant as a killable coverage gap — and they are **necessary, not sufficient**: clearing all of them rules out the common coverage-gap signatures, not every one. Crucially, **absence from `caught.txt` is never itself evidence of equivalence**: a mutant you are weighing sits in `missed.txt`, so it is absent from `caught.txt` by definition, whether it is a true equivalent or an as-yet-uncovered coverage gap. The exclusion bar therefore stays the positive standard from **When `missed` doesn't mean "untested"**: you must be able to **prove** that *no* specification-respecting test can distinguish the mutation — a type/parser guarantee of unreachability, an algebraic same-output identity, or an exhaustive argument over a finite input domain. A distinguishing-input search that came up empty only raises confidence: on a non-exhaustively-searchable domain it never establishes that no distinguishing input exists. These checks narrow and pressure that proof; they do not replace it.

This is also a different axis from anchor validity: the **Verification protocol** and **Pre-run anchor validation** confirm a regex hits the intended mutant, whereas these checks probe whether the mutant it hits is truly unkillable. A pattern can be perfectly anchored and still exclude a killable mutant.

Step 1 is a mechanical, command-checkable assertion. Steps 2–4 are judgment-based heuristics — tells and standards that route the decision, deliberately not hard mechanical gates.

1. **Over-exclusion cross-check (mechanical).** The removed set — the mutants an `exclude_re` pattern strips — must contain nothing the test suite kills. Compute it as a set difference, the way the **Verification protocol** does: list the stripped universe `U` (`cargo mutants --list --workspace --config <stripped-toml>`), list it again with the candidate pattern applied as `K` (the Verification protocol's candidate config, or `cargo mutants --list --workspace --config <stripped-toml> --exclude-re='<pattern>'`), and take `removed_set = U \ K` (`comm -23` over the two sorted listings). `K` is the *kept* set — the universe minus the pattern's targets — so do **not** intersect `K` itself with `caught.txt`; `K` is non-empty for any healthy config and would falsely read as a swarm of over-exclusions. Intersect `removed_set` with `caught.txt`; the intersection must be empty. A mutant in the intersection was killed by some test — so, provided that test is **specification-respecting** (not flaky, and not asserting an implementation detail such as a mock expecting the fast path), the mutant is not equivalent: an over-exclusion, usually a pattern sweeping in a killable sibling, which **Pattern style** narrows. A hit killed only by a flaky or implementation-detail test is the exception — inspect the failing test before ruling the mutant non-equivalent, since equivalence is defined against specification-respecting tests only. Two provenance requirements make the intersection sound:
   - `caught.txt` must come from a run **capable of killing every mutant in `removed_set`** — one that actually tested each, under a configuration in which a distinguishing test, if one exists, would execute and fail. The single failure mode to rule out: any mutant left **untested** by a run-configuration difference is absent from both `caught.txt` and `missed.txt`, so `removed_set ∩ caught.txt` is empty for the trivial reason that it was never exercised — not because it is equivalent (a false pass). Match `U`'s full run configuration: **source revision, workspace/package scope, feature flags, cargo / test arguments, and test tooling**, and empty all `exclude_re` (a stripped-config run) so no pre-existing exclude masks a candidate target. Each common slip — a run with the candidate exclude already applied, a narrower `--file` / single-`--package` scope, a different feature set, a different test filter — reduces to the same untested-mutant defect.
   - Run `--list` at its default `--line-col=true` so both sides carry the `path:line:col:` prefix and the exact-string intersection holds; `caught.txt` always carries that prefix. A `line:col`-stripped bare-name comparison is a fallback only when locations are genuinely unavailable: identical bare names recur at distinct locations, so it over-reports — its hits are suspects to confirm by location, not a clean verdict.
2. **Sibling-asymmetry tell.** If a structurally symmetric sibling of the target is in `caught.txt` while the target is in `missed.txt`, treat the equivalence claim as suspect: a true equivalence usually makes both siblings equivalent, so the asymmetry signals a coverage gap. This is a tell that warrants investigation, not a verdict that the target is killable.
3. **Guard-gates-an-index check.** If the mutated predicate guards a slice or index access (`shape[..n]`, `v[i]`), a mutation that disables the guard may reach the access with an out-of-range value and **panic** instead of returning the guarded error. A panic is observable, so a test feeding such an input kills the mutant — a coverage gap. When the mutated predicate guards an index, flip the default to coverage-gap; the equivalence claim survives only if the index is *otherwise* guaranteed in range (an earlier validation, a type bound), making the guard genuinely redundant. Identify which slice the disabled guard actually reaches and whether its index can exceed the length: the original audit's error was justifying the mutant via `shape[nrow..]` (the empty, product-1 case — which holds only when `nrow == shape.len()`) when the disabled guard in fact reaches `shape[..nrow]`, out-of-range and panicking once `nrow > shape.len()`. `shape[nrow..]` panics on `nrow > shape.len()` too, so neither slice form is automatically safe — pin the actual access and its reachable index range.
4. **Reachability standard.** "Unreachable under the current test or feature configuration" is **not** equivalence. Reachability only disproves the **Unreachable** rationale; it does not by itself prove a coverage gap, because a reachable mutant can still be equivalent under another criterion (optimization-only, default-equivalent, same-output, tie-breaking). A reachable mutant is a coverage gap precisely when a specification-respecting test can **distinguish** it — exhibit an input on which the mutated and original code observably differ. Reachability is necessary but not sufficient: an optimization-only or same-output mutant executes the reachable path yet leaves every observable identical, so it stays equivalent. When you can produce such a distinguishing input — reachable by a supported config, an in-tree fixture, or a test you could write — it is a coverage gap: leave the mutant in scope and kill it (wire the fixture, enable the feature). Only a type- or parser-guaranteed-unreachable path, or a mutation with mathematically identical output, qualifies as equivalent. An optimization-gate predicate shown a coverage gap this way is killed by a test on the distinguishing input, not by an exclude: the direct predicate test of **Responding to an equivalent mutant** when the predicate can be called on its own, otherwise a test of the enclosing function.

Clearing steps 1–4 means no common coverage-gap signature fired; it does **not** discharge the positive argument. If you cannot state why every specification-respecting test must agree with the original — a type/parser unreachability, a proven same-output identity, or an exhaustive argument over the input domain — the default stands: **kill the mutant with a test**, do not exclude it. A distinguishing-input search that merely came up empty is not such an argument.

## Responding to an equivalent mutant

This applies to a mutant whose equivalence the positive argument of **Equivalence soundness** establishes and its steps 2–4 do not refute; step 1 checks the candidate pattern when the response below is exclusion. An equivalent mutant marks a freedom no specification observes, and what to do depends on what that freedom is. Take the first response that fits:

1. **Remove the code.** It fits when the code the mutant changes can be removed without changing any observable behavior — the return value, the state it writes, whether it panics — for any input the function's signature accepts, and without slowing any input: a branch with no effect, a second path no faster than the first. Removing the code is a different edit from the mutation, so it needs its own argument, to the standard **Equivalence soundness** sets, covering the inputs no test reaches. Before the removal, add a test that feeds inputs reaching the code and asserts every observable effect at risk, and run it again after the removal; a removal that changes those effects fails it.
2. **Test the predicate directly.** It fits when the mutation changes only whether an intended optimization runs, the predicate deciding it can be called on its own, and some input of the predicate tells the mutant apart. Test that predicate against its own specification, with inputs that tell each of its mutants apart: a `true` case and a `false` case kill its `with true` and `with false` replacements, and a comparison mutant needs the boundary input (`n < 8` and `n <= 8` differ only at `8`). The same test kills a predicate mutant that **Equivalence soundness** step 4 shows to be a coverage gap. A predicate mutant no input of the predicate tells apart — `n < 8 && n != 8` under `<` → `<=` — is equivalent in the predicate too, and takes the next response.
3. **Exclude it, or leave it in scope.** Anything else — a tie-break, a capacity hint, an optimization decided inline, a default-equivalent value, an arm reached only by inputs the parser never produces — is excluded with the mechanism **`exclude_re` vs `#[mutants::skip]`** selects, an `exclude_re` pattern written per **Pattern style** and cleared by **Equivalence soundness** step 1. Where no pattern isolates the mutant without a source change that cannot be made, leave it unexcluded, as **Pattern style** directs.

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

1. Build the validation universe — a copy of `mutants.toml` with `exclude_re` emptied, every other key kept — and capture it: `cargo mutants --list --workspace --config <stripped-toml> > /tmp/universe.txt` (see **Pre-run anchor validation** for why `--list` and `--no-config` are both the wrong universe).
2. For each `exclude_re` entry, `rg -- '<pattern>' /tmp/universe.txt` (the `--` keeps a `-`-leading pattern from being read as a flag). Entries matching nothing are dead config (the regex matches no current mutant). For each match, confirm it is the intended target, not a same-named mutant a shifted coordinate now points at.
3. For each entry that does match, re-evaluate the equivalence claim against the current code via the **Equivalence soundness** checks.
4. Remove dead entries, rewrite entries whose claims no longer hold, and replace each `file:line:col` anchor with a name pattern written per **Pattern style**.

A regex that worked when written can rot in two ways: the underlying code changed (mutant no longer exists), or cargo-mutants' name format evolved between versions. Both produce silent dead patterns.
