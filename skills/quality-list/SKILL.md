---
name: quality-list
description: >
  Single source of truth for universal code-quality items. This file
  defines each item's intent, concern conditions, and N/A criteria.
  Code-quality audit and preflight skills reference items by number;
  do not duplicate the rule text into them. Update items here, and
  referencing skills pick up the change automatically.
---

# Quality List (SSOT)

This skill is **a definition file, not a runnable procedure**. Skills that audit or preflight against universal code-quality apply these items by reference. When an item changes here, referencing skills pick up the change automatically; do not copy these rules into them.

## Audit lanes

Each item is tagged for which audit lane it belongs to in `done-check`'s split between fresh-context subagent audit and main-context audit:

- **mechanical** — judgable from literal diff text + literal code text + literal rule text alone, with no need for conversation history, plan context, or actual command execution. Delegated to a fresh-context subagent in `done-check` Step 2 to neutralize the author's blindspot for what their own comments and code actually say (vs what they meant them to say).
- **contextual** — requires plan / intent / review history that only the main context has, OR requires running a command against the working tree to gather evidence. Stays in main context.

Tags are listed inline on each item below.

---

## 1. Invariant derivation (when fixing) [contextual]

For any fix in response to a bug, review finding, or failing test classified as **invariant-bearing**, derive complete necessary-and-sufficient conditions from first principles before committing. Incremental "patch the symptom" fixes are concerns.

Representative invariant-bearing classes: boundary conditions, type / unit / width conversions, numerical computation, concurrency, state transitions, protocol or spec contracts, external API contracts, data persistence consistency, security / permission boundaries.

**N/A:** the change is a typo, stale comment, doc tweak, or other surface fix where the conclusion is self-evident from the diff.

## 2. Purpose verification [contextual]

The change must accomplish its stated purpose, not just compile and pass existing tests. Exercise the new behavior end-to-end against an input that exposes the purpose.

**N/A:** strictly mechanical changes (rename, file move, formatting).

## 3. Pattern audit [contextual]

If a pattern was copied from existing code (sibling module, prior wrapper, parallel type), evaluate (a) whether the source pattern is itself correct, and (b) whether the source's context applies to the current usage. Inheriting a pattern's bugs OR misapplying a correct pattern to a different context are both concerns.

**N/A:** no pattern was reused; the change is a fresh design.

## 4. Scope discipline [contextual]

Review findings and design concerns must be evaluated against the code's actual role, not narrowed to the originating task. Dismissing a real defect with "out of scope for this issue" is a concern.

**N/A:** no findings or concerns were raised during the work.

## 5. Behavior coverage [mechanical]

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

## 6. Implementation guards [mechanical]

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

## 7. Impact / caller verification [mechanical]

If the change has a planned impact list (from research or design notes), verify it against the actual diff:

- Every caller listed as affected has been updated (gap = missed impact)
- No caller has been modified that wasn't in the impact list (gap = scope creep)

When no formal impact list exists, manually trace the public symbol's callers and confirm each remains consistent with the change.

**Concern conditions:**

- A listed caller was not updated
- A caller was updated but is not in the impact list (or the deviation is not justified)
- Public symbol changed but no caller trace was performed

**N/A:** the change touches no symbol with cross-module callers (internal helper with single use site, isolated test, etc.).

## 8. Test execution [contextual]

The relevant test suite was actually run, the results were observed, and any failures were investigated. "Compiles clean" or "existing tests pass without re-running them" is not pass.

If a baseline (pre-existing failures recorded before implementation began) exists, distinguish new failures from pre-existing ones. New regressions are concerns regardless of the project's prior state.

**Build-preset coverage on signature changes.** When the diff changes a public function signature in a way that requires every caller to be updated (parameter add / remove / reorder, type substitution, strong-typedef wrapping over a previously-raw type), test execution must cover **all production build presets** that the project ships — not just the development preset. Feature-flag-gated source files (e.g., BP-on, MPI-on, GPU-on test suites that only build under the corresponding preset) are common sites where compile failures from the migration go unobserved when only the dev preset is exercised. The relevant question is: "for every preset listed in the project's preset / build-config registry, does the touched API still compile?" — with strong-typedef migrations the type system is the verification mechanism, so a code path that does not get built passes the type check vacuously and silently keeps old call forms. Building under the alternative presets is the only way to surface those.

**Concern conditions:**

- Tests were not actually executed against the diff
- Tests fail and the failures were not investigated
- New regressions vs baseline are present and not addressed
- Signature-changing diff was tested only under the development preset; feature-flag-gated presets (BP-on, MPI-on, GPU-on, etc.) were not built, leaving compile failures in flag-gated code unobserved

**N/A:** truly mechanical changes (rename, formatting, file move) where there is no test surface to exercise.

## 9. Completion hygiene [contextual]

Project-standard format / lint / type-check / build commands ran clean against the diff. Use the project's actual commands; examples:

- Rust: `cargo clippy --all-targets -- -D warnings`, `cargo fmt --check`, `cargo build`
- C / C++: `clang-tidy`, `clang-format --dry-run -Werror`, build clean
- Python: `ruff check`, `ruff format --check` (or `black --check`), `mypy`
- TypeScript / JavaScript: `tsc --noEmit`, `eslint`, `prettier --check`

Debug-only artifacts removed: `dbg!`, trace `println!` / `print(...)` / `console.log`, commented-out code, scratch files.

**Pre-commit constraint response.** When a pre-commit hook rejects the commit due to a per-file size or line-count threshold, the correct response is **file split first, content trim only when the trimmed text is genuinely redundant** — repeated boilerplate, overlong heredocs, copy-pasted scaffolding. Removing load-bearing docstrings, comments, structural code, or test cases just to slip under the threshold is a concern. It converts a structural violation (the unit is too large) into silent information loss (the documentation that would have explained the unit is gone).

**Concern conditions:**

- Lint / format / type-check / build commands were not run, or they reported issues
- Debug-only output left in the diff
- Pre-commit hook size / line-count rejection was resolved by trimming load-bearing content (docstrings, comments, structural code, test cases) instead of by splitting the unit

**N/A:** documentation-only changes with no code touched.

## 10. Architectural boundary integrity [mechanical]

If the project has an architectural rule about dependency direction or module boundaries — layered ordering, hexagonal / clean inward-pointing, a documented module DAG, a public / internal split — verify the diff respects it:

- New imports / `use` / `#include` cross a boundary in the disallowed direction.
- New package dep entry creates a disallowed edge.
- New `pub` / `export` widens access beyond what the rule allows.

**Concern conditions:**

- Diff introduces an import / dep edge contradicting the rule
- Public exposure widened beyond the rule

**N/A:** the project has no architectural rule, or the diff introduces no relevant imports / dep edges / public symbols.

## 11. Textual / paired-artifact drift sweep [mechanical]

Renames, removals, and module-structure changes have to be threaded through every textual surface that names them. Going through only the primary identifier (the function definition, the type, the moved file) is not enough — secondary surfaces keep referring to the old shape and silently rot.

**Same-crate sweep.** For each rename / removal in the diff:

- `rg <old-identifier>` over the touched crate(s). Resolve every remaining hit: panic / `expect` / `assert!` messages, error format strings, inline comments, doctest code blocks, rustdoc links, error-variant `detail` strings, `format!` payloads, module-level prose.
- For each `mod` / `pub mod` add / remove / rename: re-read the parent module's `//!` (or equivalent) docstring against the current set of children. Stale "lands in a subsequent phase", "currently exposes X" claims after Y was added are concerns.
- For each new public callsite that produces, returns, or attaches behavior to an existing public type (new function / method, added trait implementation, added subclass / extension, etc.):
  - Re-read that type's own definition-level docstring against the current producer set. Definition-level docstrings often list producers / consumers / sources of an instance (e.g. "raised by X", "returned by X", "produced by X", "consumed by X") and silently rot when the list grows.
  - **Additionally, run a file-scoped grep over the shared type's source file for the existing sibling's identifier.** When a sibling function / method / handler / impl already exists, that file frequently names it in surfaces that are *not* the type's primary docstring:
    - doc cross-references / link macros (rustdoc `[`X`]`, Sphinx `:func:`X``, JSDoc `{@link X}`, KDoc `[X]`, etc.)
    - user-facing message strings (formatter / `__str__` / `Display` output, error messages, log lines, exception messages)
    - per-case docs inside enumerated types (enum variants, sum-type cases, discriminated-union members)
    - example or "raised by" / "returned by" snippets in module-level / namespace-level prose Each hit must be evaluated for whether the new sibling should also be named. Patching only the surfaces an external review tool happens to flag is the failure mode this bullet exists to prevent — review iterations on shared-type docs typically cluster by surface kind (link macros one round, message strings the next, format payloads the round after) and converge slowly without a proactive grep.
- For each removed item: confirm no docstring elsewhere still references it.
- **For each *invariant-operator or quantifier change*** (e.g. a documented relation flips from `==` to `>=` / `<=`, from `exact equality` to `at least` / `at most`, from `length nconv` to `length min(nconv, nev)`, from `for all` to `for first N`, from `nev <= ncv` to `nev + 2 <= ncv`), grep for the OLD operator / quantifier paired with the relevant identifier across **every** surface — docstrings, README / docs prose, test assertions, error messages, log payloads. The literal-text sweep must include variants the primary pattern misses: message-suffixed assertions (`assert_eq!(x, y, "explanation")` after `assert_eq!(x, y)`), chained / format-string variants, partial-match continuations (`X.field, Y`). A `replace_all` over the strict literal will silently skip the suffixed / chained forms. Iteration-clustered review findings on a single invariant — multiple reviewer rounds each surfacing a new old-pattern hit in a different file — are the typical signal that this sweep was incomplete on the first pass.
- **For each *deleted code block within a function body*** (loop removed, branch dropped, intermediate variable inlined away), re-read every comment **inside the same function** against the post-deletion control flow. Authors routinely visually skim past comments that sit immediately above or below the deletion site during a structural change, leaving them describing a flow that no longer exists ("the V_canon column-reorder absorbs the permutation" after the permutation loop was deleted; "in the next step we shift cz back" after the shift was hoisted out). The rg-by-identifier sweep catches this only when the deleted code introduced a *named* artifact; structural deletions need an explicit re-read of the function-local commentary.

**Naming-as-claim.** A new identifier whose name asserts a property the implementation does not in fact provide — e.g. `random_right_canonical_*` that calls `canonicalize(_, 0)` and produces `Mixed { center: 0 }` instead — is a concern. Helpers that wrap a parametrized API call should be named after the parameter values they pin, not after the operational role they happen to serve.

**New-comment claim sweep (author-blindspot mitigation).** Authors read what they meant their comments to say; reviewers read the literal text. The two diverge silently. For every comment / docstring **newly added or modified** in the diff, perform a literal-vs-code cross-check before marking item 11 ✅. This is the lane that catches "comment says `rel_tol = 1e-9` but code uses `1e-4`" / "doc says `SU(2)` but generator produces `U(2)`" / "doc says `V_g^T H_2 V_g` but code computes `V_g^† H_2 V_g`" / "doc says `simultaneously diagonalizes` but code only does so up to a clustering tolerance" — all of which are the author's intent leaking past the literal text.

For each new / modified comment, extract:

- **Numeric literals** (`1e-9`, `tol = 1e-12`, `m >= 2`, `O(1e-4)`, threshold names with values). Cross-check that every such number appears verbatim somewhere in the same translation unit / module / file scope. If the comment names a `tol` value, the corresponding `constexpr` / `const` / parameter should use the same literal.
- **Identifiers and code-like spans** (function names, variable names, type names, mathematical notation like `V_g^T`, `V^†`, `M^*`, `\dagger`, `^T`, conjugate vs transpose). For each, verify the code it refers to is spelled / behaves the same way. `^T` vs `^†` / `transpose` vs `adjoint` are easy to slip when the operands are real (so the two coincide numerically) but the comment is read literally.
- **Set / distribution / property claims** (`SU(2)`, `Haar`, `traceless`, `unitary`, `Hermitian`, `non-zero trace`, `simultaneously diagonalizes`, `orthogonal`, `non-degenerate`, `uniformly distributed`, `bounded`, `monotone`, `convergent`). For each, verify the code provably enforces the claim or — if it only enforces the claim *up to a tolerance / under a precondition* — verify the qualifier is in the comment too. "X is Hermitian" in a comment over code that constructs X by independent accumulations of `(a,b)` and `(b,a)` is a concern unless the code also enforces symmetry (e.g., mirrors a triangle); the qualifier ("up to ULP-level noise" or "after explicit symmetrization") must be present or the construction must enforce the claim structurally.

The check is mechanical, not heuristic: if the comment names a specific value / identifier / property, the code must back it up at the level of literal text. Vague hand-waving that has no extractable claim is fine; specific assertions are the failure surface.

**Cold-read pass.** After the literal-vs-code sweep, re-read each new / modified comment as if you had never seen the code — trying to construct what the code would have to do to make the comment true. If the construction differs from what the code actually does, the comment is misleading regardless of whether any specific literal is wrong.

**Scope check.** A source-file comment / docstring describes the present-tense behavior of the unit it sits on — what the code does now, what invariants hold, what failure modes to expect. It does **not** describe (a) cross-function or cross-method design rationale (e.g., "while sibling X uses procedure Y, this one uses procedure Z because of decision W"), (b) change history (e.g., "after PR #N rewrote this, the path now uses ..."), or (c) comparison to alternative designs / rejected options that are themselves documented at their own sites (commit message, PR description, tracking issue, changelog). Information at the wrong scope is a defect: it forces a reader asking *what this unit does* to follow trails to understand *why the design is what it is*, and the trails then rot independently of the code. The cold-read pass above catches **misleading** claims; the scope check catches **misplaced** ones — comments that are factually correct but belong to a different surface and audience.

Mechanical detection of misplaced content in a new / modified per-unit comment:

- Comparative phrases naming sibling functions / methods / classes / modules: "while X does Y", "unlike X, this Z", "matches / mirrors X" (when the match is incidental rather than a maintained invariant), "X also does this but with Y procedure".
- Decision-history phrases: "we chose / picked / adopted ...", "option (X) / option (Y)", "the SSOT decision", "the design intent", "scoped to a follow-up".
- Cross-surface rationale that names other surfaces by role: "see the commit message for ...", "the umbrella discusses ...", "as noted in the PR".
- Tuning / rewrite-history phrases: "after the PR #N rewrite", "we used to ...", "previously this ...".
- **Deletion-site tombstones** — comments whose present-tense subject is the *absence* of code at this site rather than the behavior of the code at this site: "X is handled at parse time in ...", "X is enforced in ...", "X happens elsewhere", "X now lives in ...", "X moved to ...", "no longer ...", "is no longer required because ...", "reaching this point means X (a meta-statement explaining what the removed guard would have done)". The fingerprint is: paraphrasing the comment yields "I am telling you why the code that used to be here isn't here." These appear after a refactor removes a guard / validation / branch and the author adds an explanatory note pointing the reader to where the behavior now lives. The diff already shows the deletion, and the commit message names the rationale; an in-source pointer is a tombstone that rots independently and forces every future reader to context-switch. **Delete the comment, do not commit it.**

Each such phrase is a candidate ⚠ — flag it and either trim the comment to present-tense behavior or move the content to the appropriate surface (commit message, PR body, umbrella issue, changelog). A claim that justifies *the current code choice in a way the reader cannot re-derive from the code alone* may stay; everything else moves.

**Hyperlink completeness on source surfaces.** If a source-file comment must reference a GitHub issue / PR (e.g., for a forward-looking TODO that depends on resolution elsewhere), use the **full URL**, not bare `#N`. GitHub auto-links `#N` only inside PR descriptions, issue descriptions, and commit messages — **not in source-file comments rendered by the source viewer**. A bare `#5` in a `.jl` / `.rs` / `.py` comment is dead text: the reader sees the literal string and has to manually navigate. A full URL is clickable and self-resolving.

**Same-repo paired artifacts.** API / schema / contract changes ripple beyond the crate. Sweep these surfaces in the same repo:

- `examples/` — sample code referencing the changed API
- `bench/` — benchmarks referencing it
- doctests anywhere in the repo
- `README.md` / top-level docs / `docs/` prose
- `CLAUDE.md` if it documents the changed surface
- migration / schema files if the change affects persistence
- generated artifacts that should be regenerated (e.g., protobuf, bindgen output)
- **the PR description itself**, if a PR is open or imminent. PR bodies routinely re-state numeric tolerances, identifier names, and structural claims from the code's docstrings (`atol ≈ 2.2e-12` in the PR body vs `≈ 2.2e-10` in the docstring). The PR body and the code are separately editable surfaces; whenever a numeric literal, identifier, or property claim from the code appears in the PR body, the two must agree at the level of literal text.

**User-visible-concept spread (drip-mitigation).** A user-visible concept — an output / log key (`peak_bp_sweep=`, `level=info`), a CLI flag (`--debug_bp_diagnostics`), a CLI option's *description text* (the `add_option` / `add_flag` help string), a runtime warning or error message string, a test format-string assertion (`out.find( "X=") != npos`) — typically lives across many surfaces at once. Adding such a concept, renaming it, or changing its semantics ripples beyond the producer code. Sweep these surfaces in the same fix iteration:

- the producer site (the code that emits it)
- CLI help text — the `add_option` / `add_flag` *description* string that ships with `--help`. This is a user-facing contract, distinct from `docs/` prose and routinely overlooked when prose is updated in isolation.
- runtime warning / error / log strings that name the concept
- regression-test format-string assertions — tests that lock the surface to a specific spelling. Every key the production path emits must be in the assertion set for the diagnostic format to be regression-guarded; partial assertion sets silently allow later additions to drift.
- the PR description and **commit messages staged for the current fix iteration**. Commit messages are immutable post-push, so a rename / wording change must be picked up before the next `git commit`.

Repeated review rounds that each surface a single new finding pointing to a different paired artifact (CLI help text, then docs, then test assert, then commit message, etc.) are the typical signal that this sweep was incomplete: each round finds another surface that still describes the prior shape. The mechanical version of this sweep is `rg <concept-name>` (case-sensitive, with and without the trailing `=` / `:` separator as appropriate) over the touched directories plus the staged commit messages and PR body — exhaustive enumeration is preferable to selectively patching the surfaces an external reviewer happens to flag.

**Cross-repo paired artifacts (opt-in).** If the repo declares external paired artifacts (e.g., a reference implementation in another language, a client library expected to track this API, a published spec), check them as well. Without an explicit declaration this lane is N/A — do not invent paired repos.

**Concern conditions:**

- Renamed / removed identifier still mentioned by its old name in any same-crate textual surface
- `mod` add / remove / rename leaves the parent module's docstring stale
- New producer / consumer / extension of a public type leaves the type's definition-level docstring stale (e.g. "raised by X" / "returned by X" / "consumed by X" that omits the new callsite)
- New identifier's name claims a property the implementation does not enforce / does not produce
- New / modified comment names a specific numeric literal, identifier, set / distribution / property, or mathematical notation that does not match the code (e.g. `rel_tol = 1e-9` in a comment vs `1e-4` in code; `SU(2)` in a comment vs `U(2)` from the generator; `V_g^T` in a comment vs `V_g^†` in code without a real-V_g qualifier; `simultaneously diagonalizes` without the clustering-tolerance qualifier when the code only does so up to tolerance)
- New / modified comment makes a claim that a cold-read of the comment alone would lead a reader to expect different behavior than the code actually produces
- Same-repo paired artifact (`examples/`, `README.md`, doctest, migration) references the old API and was not updated
- A code block was deleted inside a function and a same-function comment still describes the deleted control flow / variable / intermediate result
- A code block (guard, branch, validation, redundant check) was deleted and an *explanatory tombstone comment* was added at the deletion site pointing the reader to where the behavior now lives ("X is handled at parse time", "X is enforced in run_cli", "X moved to ...", "no longer needed because ..."). The diff and commit message own that rationale; the in-source comment is a tombstone candidate and should be deleted
- A source-file comment references a GitHub issue / PR by bare `#N` instead of a full URL (source viewers do not auto-link `#N`, so the reference is dead text)
- The PR description and the code disagree on a numeric literal, identifier, or property claim that appears in both
- A user-visible concept (output key, CLI flag, runtime warning, log key, error message string, test format-string assertion) was added / renamed / re-spelled in one surface but a sibling surface (CLI help text, docs, doxygen, regression-test asserts, staged commit message) still names the prior shape
- Declared cross-repo paired artifact diverged and was not updated or re-declared as deferred

**N/A:** the diff renames / removes nothing, adds / removes / renames no modules, adds no identifiers whose name encodes a behavioral claim, adds / modifies no comments that make extractable claims (specific numbers, identifiers, properties, or notation), and touches no API / schema / contract surface paired artifacts could mirror.

## 12. Discovery surfacing (plan-vs-actual) [contextual]

If a research plan exists for this work, every divergence between the plan and the implementation must trace to one of:

- A `confirmed` outcome of an `inconclusive` item's `probe` (with the resolved branch followed)
- A `deferred` item reaching its `resolution-point`
- An explicit re-plan note added to the plan or surfaced to the user

Silent ad-hoc divergence — patching an unexpected fact during implementation without recording how it relates to the plan — is a concern. The plan's `Inconclusive / Deferred items` section is the only sanctioned channel for mid-implementation surprises.

**Plan-enumeration completeness.** When the plan enumerates discrete artifacts to produce — test sub-cases, error variants, files to add, API methods to expose, fixture builders, sub-tasks in a checklist — every listed item must have a corresponding artifact in the diff.

The default audit semantics for a plan enumeration is **exhaustive**: an N-item list demands N matching artifacts in the diff, mapped 1-to-1. Plan authors who intend a list to be **representative** (a sample, not the full set) must declare that inline (`(representative)` / `(illustrative)` / equivalent annotation on the list). Without an explicit annotation, the audit treats the list as exhaustive.

This is the inverse failure mode of the silent-extra-divergence concern above: instead of the implementation adding work the plan did not anticipate, the implementation silently ships fewer artifacts than the plan promised. Both are plan-vs-actual concerns and both must be surfaced to the user before merge — either by completing the missing artifacts, marking them deferred with a follow-up, or annotating the plan list as representative.

**Concern conditions:**

- Implementation diverges from the plan and the divergence is not traceable to a listed `inconclusive` probe outcome, a `deferred` resolution, or an explicit re-plan note
- Plan had `Inconclusive` items but none were probed during implementation (verify whether the probe was actually needed; if yes, this is incomplete work)
- Plan was retroactively edited to match the implementation without user-visible surfacing
- Plan enumerated N discrete artifacts (without `(representative)` annotation) but the diff contains fewer than N, with no deferral note explaining the gap

**N/A:** there is no plan (ad-hoc edit, typo fix, no preceding research phase).

## 13. License compliance and attribution for ported code [mechanical]

Code reused from an external project — whether copied verbatim, ported line-for-line into a different language, or transcribed with cosmetic changes (renames, rephrased structure, dropped scaffolding) — carries the source project's license obligations into the derivative. The audit asks two distinct questions:

1. **Is the source license compatible with this project's license?** The combinatorics of permissive ↔ permissive, permissive ↔ copyleft, and proprietary ↔ anything are well-defined; the concern is forgetting to do the check, not picking the wrong answer once you look.
2. **Are the upstream license's specific obligations satisfied?** Common requirements: retain copyright notice, name the source project, list modifications, propagate any upstream NOTICE-file content, retain license text. The exact set varies (Apache-2.0 § 4(b)–(d) is the most-discussed reference, MIT requires retention of copyright + permission text, BSD has the no-endorsement clause, etc.).

**Detection.** The structural signals that a diff contains ported code:

- A comment that says "ported from", "derived from", "based on", "from $project", or names another project as source.
- New identifiers, function shapes, or algorithm structure that match a known upstream pattern that the author admits to having referenced during research / planning. (When research surfaced a specific external implementation as a reference and the diff structurally mirrors it, treat as a port even if no comment says so explicitly.)
- A research-phase note ("ported $func from $project") that has no matching attribution comment in the diff.

**Verification, when a port is identified.**

- **License compatibility.** Confirm the source license. Permissive → permissive (Apache-2.0, MIT, BSD, ISC, etc.) is generally fine with attribution; copyleft (GPL, AGPL, MPL, EPL, LGPL) into a permissive project usually is *not*. If unsure, escalate.
- **Attribution surface.** A comment block on or above the ported declarations naming: (1) the upstream project, (2) the source file / URL, (3) the upstream copyright line, (4) the license name and version. For a single helper an in-source comment is sufficient; for many helpers from one source, a top-level attribution surface (`THIRD_PARTY.md`, `NOTICE`, etc.) may be cleaner.
- **Modifications enumerated.** Apache-2.0 § 4(b) and the MIT/BSD "preserve the notice" lanes both expect the reader to be able to tell what the derivative changed. Either an inline "Notable changes from upstream" list or a clear "ported as-is, modulo language rephrase" statement.
- **Upstream NOTICE / NOTICE-equivalent.** If the upstream license triggers a NOTICE-propagation clause (Apache-2.0 § 4(d) is the common one), **fetch the upstream NOTICE file and verify it exists before claiming compliance**. A NOTICE file in the derivative that cites a non-existent upstream NOTICE is worse than none — it implies upstream content the derivative cannot reproduce.

**Concern conditions:**

- Diff contains ported code from an external project but no attribution comment / file names the upstream project, source location, upstream copyright, and license.
- Research notes / commit messages name an external project as source, but the in-source attribution does not.
- Upstream license is incompatible with this project's license (e.g., GPL code in an Apache-2.0 project) and the diff does not address the conflict.
- Modifications relative to upstream are not enumerated, and the upstream license requires marking changed files (e.g., Apache-2.0 § 4(b)).
- A NOTICE / THIRD_PARTY file in the diff claims to mirror an upstream NOTICE, but the upstream does not have one (verified by fetching it from the canonical source).
- The naming-as-claim concern from item 11 also fires: the ported code's name asserts a property not in the upstream (e.g., calling a U(2)-sampling helper "Haar"), which can imply distributional guarantees the port does not provide.

**N/A:** the diff contains no ported code from an external project (fresh design or trivial idiom).

## 14. Silent semantic regression on signature change [mechanical]

Signature changes — parameter removal, reorder, or type substitution — can produce a silently miscompiled caller path when the old call form still satisfies the new signature's type rules under the language's conversion semantics. The audit lane is responsible for detecting whether such a path exists *before* the call sites silently take on a different meaning.

The failure mode is structural: a `git diff` that contracts or rewires a function signature leaves the function declaration loudly changed but its callers visually unchanged. If the call sites still compile under the new signature — through implicit conversions, default-argument insertion, narrowing constructors, coercion traits — they are quietly remapped to the new semantics. The old behavior is gone and no compile-time signal points at it.

**Concern conditions:**

- The diff removes, reorders, or substitutes parameters in a public (or otherwise out-of-file-visible) function or method.
- The old call form is still well-typed under the new signature due to language-level conversion / promotion / coercion — i.e., a caller written against the previous signature still compiles, even though its argument is now bound to a *different* parameter slot or *different* parameter type.
- No compile-time signal exists at existing call sites: a developer reading the call site cannot tell whether the call was swept after the signature change or was silently re-routed.

**Mitigation pattern:** introduce a *sentinel* — typically a `= delete;` overload or a `[[deprecated]]` overload — that takes the old signature shape and makes the old call form fail to compile (or loudly warn). The sentinel forces every call site to be touched after the signature change. Strong types over the affected parameters (newtype / phantom-tagged wrappers) achieve the same protection at the type level without an explicit sentinel.

The generic principle is language-agnostic; the actual triggers, mitigation idioms, and mechanical detection patterns depend on the host language's conversion semantics. Concrete realizations live in `lang-<language>.md` next to this file. When `done-check` / `todo-check` resolve the active rule set, the lang-supplement is loaded alongside the base item.

**N/A:** the diff does not remove, reorder, or substitute parameters of any function or method whose call sites live outside the touched translation unit, AND the call sites of any touched function are exhaustively re-verified to type-check under the new signature with no implicit-conversion path from the old form.

## 15. Public-facing documentation durability [mechanical]

Public docs (`README.md`, `docs/**/*.md`, top-level `*.md` other than `CONTRIBUTING.md` / `LICENSE` / `NOTICE` / `CHANGELOG.md`) are a **visitor-facing surface**: the audience is a stranger who landed on the repo, not the author who built it. The audience determines what belongs:

- **What does this project do, and how do I use it** — yes.
- **Why we built it this way / what we tried first / what we read while building** — no, that goes to commit messages, PR descriptions, ADRs, design issues, or `CONTRIBUTING.md`.

LLM-drafted READMEs systematically violate this boundary in predictable ways. The author-vs-visitor distinction is the central principle; each concern condition below is a recurring instance.

**Concern conditions:**

- **Local filesystem paths in prose** — `~/`, `/Users/`, `/home/`, `/tmp/`, `/private/tmp/`, `/scratch/`, or any other absolute path that exists only on the maintainer's machine. These have no meaning to repo visitors. Replace with abstract descriptions ("`X` executable on your PATH") or generic placeholders (`body.md`, `<path>`).
- **Version literals in prose** — `v\d+\.\d+\.\d+` or "as of v…", "v0.0.1 ships X", "Currently v…", "Status: v…" when the project has an authoritative manifest (`pyproject.toml`, `Cargo.toml`, `package.json`, `mix.exs`, etc.). The prose drifts on every release; the manifest is single source of truth and the runtime `--version` reads from it.
- **Roadmap / deferred-feature prose** — "Deferred to v…", "Planned features", "Coming soon", "Will support X in vN" prose blocks when the project has an issue tracker. The tracker is single source of truth; duplicating it in README creates a second editing surface that decays. Link to the tracker instead of enumerating.
- **Changelog prose** — "Recent changes", "Latest: …", per-version bullet lists when `CHANGELOG.md` or release tags exist. Same duplication problem.
- **Point-in-time status sections** — "Currently v…", "Now at parity with X", "As of N tests passing", "Migration in progress" prose. These describe transient state and rot immediately after writing.
- **Progress-report / session-log narrative** — "Initially we tried X but switched to Y because …", "After several iterations we settled on …", "The first attempt failed, so …". README is product documentation, not a development diary. Change history lives in commit log, PR descriptions, or post-mortem notes — none of which are README.
- **Implementation rationale dumps ("Why" prose)** — "We chose hatchling because …", "We considered typer but went with argparse since …", "The trade-off was X vs Y, we picked Y". Belongs in ADRs, commit bodies, PR descriptions, or design issues — surfaces a reader actively *seeking* the why will discover. README explains **what** and **how to use**, not **why we picked**. Exception: a one-sentence "why" that frames the project's purpose against an alternative the reader is likely to confuse it with is fine ("unlike X, this is for Y"); anything longer is a decision record in the wrong place.
- **File tree dumps** — `src/`, `tests/`, `docs/` directory listings in README. GitHub's repo view already renders this; duplicating it ages the moment a file moves. Exception: a brief annotated tree that calls out *non-obvious* structure (e.g. "everything in `core/` is no-std; `host/` is the std-only host runtime") earns its place by adding information the file viewer alone cannot show.
- **Reference / bibliography dumps** — "Resources", "References", "Bibliography", "Further reading" sections that exhaustively enumerate what the *author* read while building. The link target audience is the visitor: every link should be one the visitor needs (install docs of dependencies, upstream protocol spec the project implements, related tools the visitor would compare against). Author-side acknowledgments ("inspired by", "thanks to") belong in `CONTRIBUTING.md` or a separate `NOTES.md` / `ACKNOWLEDGMENTS.md`.
- **Companion-tool / setup specifics that name the maintainer's stack** — "Reads the hook at `~/.claude/hooks/foo.sh`", "Registered in my `~/.tmux.conf`", named author / maintainer when the `pyproject` `authors` field already covers it. The README must work for a stranger who runs `git clone` and does not share the maintainer's dotfiles.

**Mechanical detection patterns:**

```bash
# Local paths.
rg -n '(?:~/|/Users/|/home/|/tmp/|/private/tmp/|/scratch/)' README.md docs/**/*.md
# Hardcoded version literals.
rg -nP '\bv\d+\.\d+\.\d+\b' README.md docs/**/*.md
# Author-side / progress-report / roadmap / changelog section headers.
rg -nP '(?im)^#+\s*(Status|Roadmap|Deferred|Planned|Coming\s+soon|Recent\s+changes|Latest|What.?s\s+new|History|Background|Motivation|Why|Rationale|References?|Resources?|Bibliography|Further\s+reading|File\s+tree|Project\s+structure|Directory\s+layout|Acknowledg(e)?ments?)' README.md docs/**/*.md
# Session-log narrative phrasings.
rg -nP '(?i)\b(initially|originally|first[ -]?attempt|we (tried|chose|considered|settled|switched|moved|ended\s+up)|after (several|many)?\s*iteration)' README.md docs/**/*.md
```

A hit on the first pattern is always a concern. Hits on the others are concerns when the listed authoritative source exists (manifest / tracker / CHANGELOG / tags / ADR / commit-message conventions), or when the section's content fits the author-side category above.

**N/A:** the doc surface is internal-only (private wiki, contributor-only design notes, ADRs that name a specific historical decision date), or the duplicated information has no authoritative source elsewhere (in which case the prose **is** the source of truth and rot is not a structural risk). `CHANGELOG.md` / release-note files are themselves the authoritative changelog source and N/A. `CONTRIBUTING.md` is the correct home for author-side acknowledgments and rationale that does not fit README.
