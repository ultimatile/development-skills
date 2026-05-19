# Textual / paired-artifact drift sweep [mechanical]

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
