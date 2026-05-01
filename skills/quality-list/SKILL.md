---
name: quality-list
description: >
  Single source of truth for universal code-quality items used across the
  done-check (post-hoc audit) and todo-check (preflight) skills. This file
  defines each item's intent, concern conditions, and N/A criteria. Other
  skills reference items by number; do not duplicate the rule text in audit
  or preflight skills. Update items here, and the audit/preflight skills
  pick up the change automatically.
---

# Quality List (SSOT)

This skill is **a definition file, not a runnable procedure**. It is
referenced by:

- `done-check` — applies each item as a post-hoc audit against the
  current diff (✅ / ⚠ / ⊘ N/A).
- `todo-check` — applies each item as a preflight before / during
  implementation, asking what to set up so the item will pass.

When you change an item here, both skills pick up the change. Do not
copy these rules into other skills.

---

## 1. Invariant derivation (when fixing)

For any fix in response to a bug, review finding, or failing test
classified as **invariant-bearing**, derive complete necessary-and-
sufficient conditions from first principles before committing.
Incremental "patch the symptom" fixes are concerns.

Representative invariant-bearing classes: boundary conditions, type /
unit / width conversions, numerical computation, concurrency, state
transitions, protocol or spec contracts, external API contracts, data
persistence consistency, security / permission boundaries.

**N/A:** the change is a typo, stale comment, doc tweak, or other
surface fix where the conclusion is self-evident from the diff.

## 2. Purpose verification

The change must accomplish its stated purpose, not just compile and
pass existing tests. Exercise the new behavior end-to-end against an
input that exposes the purpose.

**N/A:** strictly mechanical changes (rename, file move, formatting).

## 3. Pattern audit

If a pattern was copied from existing code (sibling module, prior
wrapper, parallel type), evaluate (a) whether the source pattern is
itself correct, and (b) whether the source's context applies to the
current usage. Inheriting a pattern's bugs OR misapplying a correct
pattern to a different context are both concerns.

**N/A:** no pattern was reused; the change is a fresh design.

## 4. Scope discipline

Review findings and design concerns must be evaluated against the
code's actual role, not narrowed to the originating task. Dismissing
a real defect with "out of scope for this issue" is a concern.

**N/A:** no findings or concerns were raised during the work.

## 5. Behavior coverage

Tests must exercise the **implemented behavior**, not just trip the
code paths. Cover both representatives of the realistic input space
and the corner cases the implementation handles — neither alone is
sufficient. Identity matrix only, size-1 only, all-zero or all-equal
only, diagonal-only when the implementation handles general matrices:
these do not visit the behavior the change introduced. (Size-1 / 1×1
is often itself a corner case, not a representative.)

For tensor-network / structured-data code in particular, the smallest
non-trivial fixture must include at least one bulk (non-edge) unit. A
2-site MPS has only edge tensors; use 3+ sites so a bulk tensor is
exercised. Apply the same rule to other domains: the smallest fixture
that still exercises every code path the change introduced.

When the implementation has error / failure paths (I/O, network,
concurrency, fallible operations, cleanup), tests must cover those
too — not just the happy path.

Contract-style tests (asserting the invariant the implementation
must satisfy, not just its output on one example) automatically
satisfy this. Trivial output-comparison tests on identity inputs do
not.

When multiple types share semantics — and the language / test
framework supports it — generalize via a single type-parametric
helper, not per-type duplication.

**Concern conditions:**

- Behavior was added or changed but no test was added
- Tests only exercise trivial / degenerate inputs (no representative
  case)
- Representative cases tested but corner cases skipped
- Implementation has error / cleanup paths but only the happy path is
  tested
- Multiple near-identical per-type tests instead of a generic helper
- New code populates state (a field, slot, storage, output buffer)
  but no test reads that state directly. Transitive consistency — a
  test that happens to pass through an unrelated helper while the
  new state is never observed — does not satisfy this. For each
  newly written-to location, point to at least one assertion that
  reads it.

**N/A:** the diff is purely mechanical (rename, formatting, file
move) or documentation-only.

## 6. Implementation guards

Invariants that must hold at runtime are encoded as **assertions**
(`assert!` / `debug_assert!` / equivalent), not docstring claims or
comments. When a guard is added to one API method, its paired /
sibling methods get the same guard for consistency. Constructors
validate every parameter they accept at construction time — never
defer validation to a setter or to the caller. Properties that
cannot be reliably inferred from existing fields get an explicit
field, not a heuristic.

**Concern conditions:**

- A new invariant is documented in a comment but not asserted in code
- One sibling method has a guard, others don't
- Constructor accepts a parameter but defers validation downstream
- A piece of state is reconstructed from heuristics on existing
  fields rather than tracked explicitly

**N/A:** the change introduces no new invariants (pure data movement,
simple delegation, formatting).

## 7. Impact / caller verification

If the change has a planned impact list (from research or design
notes), verify it against the actual diff:

- Every caller listed as affected has been updated (gap = missed
  impact)
- No caller has been modified that wasn't in the impact list (gap =
  scope creep)

When no formal impact list exists, manually trace the public symbol's
callers and confirm each remains consistent with the change.

**Concern conditions:**

- A listed caller was not updated
- A caller was updated but is not in the impact list (or the
  deviation is not justified)
- Public symbol changed but no caller trace was performed

**N/A:** the change touches no symbol with cross-module callers
(internal helper with single use site, isolated test, etc.).

## 8. Test execution

The relevant test suite was actually run, the results were observed,
and any failures were investigated. "Compiles clean" or "existing
tests pass without re-running them" is not pass.

If a baseline (pre-existing failures recorded before implementation
began) exists, distinguish new failures from pre-existing ones. New
regressions are concerns regardless of the project's prior state.

**Concern conditions:**

- Tests were not actually executed against the diff
- Tests fail and the failures were not investigated
- New regressions vs baseline are present and not addressed

**N/A:** truly mechanical changes (rename, formatting, file move)
where there is no test surface to exercise.

## 9. Completion hygiene

Project-standard format / lint / type-check / build commands ran
clean against the diff. Use the project's actual commands; examples:

- Rust: `cargo clippy --all-targets -- -D warnings`,
  `cargo fmt --check`, `cargo build`
- C / C++: `clang-tidy`, `clang-format --dry-run -Werror`, build clean
- Python: `ruff check`, `ruff format --check` (or `black --check`),
  `mypy`
- TypeScript / JavaScript: `tsc --noEmit`, `eslint`, `prettier --check`

Debug-only artifacts removed: `dbg!`, trace `println!` / `print(...)` /
`console.log`, commented-out code, scratch files.

**Concern conditions:**

- Lint / format / type-check / build commands were not run, or they
  reported issues
- Debug-only output left in the diff

**N/A:** documentation-only changes with no code touched.

## 10. Architectural boundary integrity

If the project has an architectural rule about dependency direction
or module boundaries — layered ordering, hexagonal / clean
inward-pointing, a documented module DAG, a public / internal split
— verify the diff respects it:

- New imports / `use` / `#include` cross a boundary in the
  disallowed direction.
- New package dep entry creates a disallowed edge.
- New `pub` / `export` widens access beyond what the rule allows.

**Concern conditions:**

- Diff introduces an import / dep edge contradicting the rule
- Public exposure widened beyond the rule

**N/A:** the project has no architectural rule, or the diff
introduces no relevant imports / dep edges / public symbols.

## 11. Textual / paired-artifact drift sweep

Renames, removals, and module-structure changes have to be threaded
through every textual surface that names them. Going through only
the primary identifier (the function definition, the type, the
moved file) is not enough — secondary surfaces keep referring to
the old shape and silently rot.

**Same-crate sweep.** For each rename / removal in the diff:

- `rg <old-identifier>` over the touched crate(s). Resolve every
  remaining hit: panic / `expect` / `assert!` messages, error
  format strings, inline comments, doctest code blocks, rustdoc
  links, error-variant `detail` strings, `format!` payloads,
  module-level prose.
- For each `mod` / `pub mod` add / remove / rename: re-read the
  parent module's `//!` (or equivalent) docstring against the
  current set of children. Stale "lands in a subsequent phase",
  "currently exposes X" claims after Y was added are concerns.
- For each new public callsite that produces, returns, or attaches
  behavior to an existing public type (new function / method,
  added trait implementation, added subclass / extension, etc.),
  re-read that type's own definition-level docstring against the
  current producer set. Definition-level docstrings often list
  producers / consumers / sources of an instance (e.g. "raised
  by X", "returned by X", "produced by X", "consumed by X") and
  silently rot when the list grows. Same shape as the
  parent-module docstring sweep one bullet up, applied to
  type-level prose.
- For each removed item: confirm no docstring elsewhere still
  references it.

**Naming-as-claim.** A new identifier whose name asserts a property
the implementation does not in fact provide — e.g.
`random_right_canonical_*` that calls `canonicalize(_, 0)` and
produces `Mixed { center: 0 }` instead — is a concern. Helpers that
wrap a parametrized API call should be named after the parameter
values they pin, not after the operational role they happen to serve.

**Same-repo paired artifacts.** API / schema / contract changes
ripple beyond the crate. Sweep these surfaces in the same repo:

- `examples/` — sample code referencing the changed API
- `bench/` — benchmarks referencing it
- doctests anywhere in the repo
- `README.md` / top-level docs / `docs/` prose
- `CLAUDE.md` if it documents the changed surface
- migration / schema files if the change affects persistence
- generated artifacts that should be regenerated (e.g., protobuf,
  bindgen output)

**Cross-repo paired artifacts (opt-in).** If the repo declares
external paired artifacts (e.g., a reference implementation in another
language, a client library expected to track this API, a published
spec), check them as well. Without an explicit declaration this lane
is N/A — do not invent paired repos.

**Concern conditions:**

- Renamed / removed identifier still mentioned by its old name in
  any same-crate textual surface
- `mod` add / remove / rename leaves the parent module's docstring
  stale
- New producer / consumer / extension of a public type leaves the
  type's definition-level docstring stale (e.g. "raised by X" /
  "returned by X" / "consumed by X" that omits the new callsite)
- New identifier's name claims a property the implementation does
  not enforce / does not produce
- Same-repo paired artifact (`examples/`, `README.md`, doctest,
  migration) references the old API and was not updated
- Declared cross-repo paired artifact diverged and was not updated
  or re-declared as deferred

**N/A:** the diff renames / removes nothing, adds / removes /
renames no modules, adds no identifiers whose name encodes a
behavioral claim, and touches no API / schema / contract surface
paired artifacts could mirror.

## 12. Discovery surfacing (plan-vs-actual)

If a research plan exists for this work, every divergence between
the plan and the implementation must trace to one of:

- A `confirmed` outcome of an `inconclusive` item's `probe` (with
  the resolved branch followed)
- A `deferred` item reaching its `resolution-point`
- An explicit re-plan note added to the plan or surfaced to the user

Silent ad-hoc divergence — patching an unexpected fact during
implementation without recording how it relates to the plan — is a
concern. The plan's `Inconclusive / Deferred items` section is the
only sanctioned channel for mid-implementation surprises.

**Concern conditions:**

- Implementation diverges from the plan and the divergence is not
  traceable to a listed `inconclusive` probe outcome, a `deferred`
  resolution, or an explicit re-plan note
- Plan had `Inconclusive` items but none were probed during
  implementation (verify whether the probe was actually needed; if
  yes, this is incomplete work)
- Plan was retroactively edited to match the implementation without
  user-visible surfacing

**N/A:** there is no plan (ad-hoc edit, typo fix, no preceding
research phase).
