---
name: done-check
description: >
  Walk through a fixed checklist of universal quality rules and self-assess
  whether the current diff satisfies each, before declaring a task complete
  or before requesting external review. Use this skill when the user says
  "done check", "ready to commit", "are we done?", "done?", or asks to
  verify whether universal quality rules are being followed before claiming
  completion. Single-pass audit — runs once per invocation.
---

# Done-Check

## Procedure

1. **Identify the diff under audit.** Cover all four sources so recently-
   added implementation files are not missed:

   ```bash
   git log --oneline @{upstream}..HEAD                       # committed
   git diff @{upstream}..HEAD                                # committed content
   git diff --cached                                         # staged
   git diff                                                  # unstaged
   git ls-files --others --exclude-standard                  # untracked paths
   ```

   Read the contents of any untracked file relevant to the audit (their
   paths alone do not let you check anything).

2. For each item below, answer the question against the diff. Mark each
   as:
   - **✅ pass** — confidently satisfied; the **Evidence** cell records
     what makes you confident (a command run, a manual check, a
     `file:line` read, or `not run: <reason>`)
   - **⚠ concern** — cite the diff location and what to fix
   - **⊘ N/A** — state why the rule does not apply

3. If any **⚠** remains, fix before proceeding.

4. Report the audit table.

## Checklist

### 1. Invariant derivation (when fixing)

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

### 2. Purpose verification

The change must accomplish its stated purpose, not just compile and
pass existing tests. Exercise the new behavior end-to-end against an
input that exposes the purpose.

**N/A:** strictly mechanical changes (rename, file move, formatting).

### 3. Pattern audit

If a pattern was copied from existing code (sibling module, prior
wrapper, parallel type), evaluate (a) whether the source pattern is
itself correct, and (b) whether the source's context applies to the
current usage. Inheriting a pattern's bugs OR misapplying a correct
pattern to a different context are both concerns.

**N/A:** no pattern was reused; the change is a fresh design.

### 4. Scope discipline

Review findings and design concerns must be evaluated against the
code's actual role, not narrowed to the originating task. Dismissing
a real defect with "out of scope for this issue" is a concern.

**N/A:** no findings or concerns were raised during the work.

### 5. Behavior coverage

Tests must exercise the **implemented behavior**, not just trip the
code paths. Cover both representatives of the realistic input space
and the corner cases the implementation handles — neither alone is
sufficient. Identity matrix only, size-1 only, all-zero or all-equal
only, diagonal-only when the implementation handles general matrices:
these do not visit the behavior the change introduced. (Size-1 / 1×1
is often itself a corner case, not a representative.)

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

### 6. Implementation guards

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

### 7. Impact / caller verification

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

### 8. Test execution

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

### 9. Completion hygiene

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

### 10. Architectural boundary integrity

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

### 11. Textual-drift sweep

Renames, removals, and module-structure changes have to be
threaded through every textual surface that names them. Going
through only the primary identifier (the function definition,
the type, the moved file) is not enough — secondary surfaces
keep referring to the old shape and silently rot.

For each rename / removal in the diff:

- `rg <old-identifier>` over the touched crate(s).  Resolve every
  remaining hit: panic / `expect` / `assert!` messages, error
  format strings, inline comments, doctest code blocks, rustdoc
  links, error-variant `detail` strings, `format!` payloads,
  README / module-level prose.
- For each `mod` / `pub mod` add / remove / rename: re-read the
  parent module's `//!` (or equivalent) docstring against the
  current set of children.  Stale "lands in a subsequent phase",
  "currently exposes X" claims after Y was added are concerns.
- For each removed item: confirm no docstring elsewhere still
  references it.

Naming-as-claim is **also** in scope: a new identifier whose
name asserts a property the implementation does not in fact
provide — e.g. `random_right_canonical_*` that calls
`canonicalize(_, 0)` and produces `Mixed { center: 0 }` instead
— is a concern.  Helpers that wrap a parametrized API call
should be named after the parameter values they pin, not after
the operational role they happen to serve.

**Concern conditions:**

- A renamed / removed identifier is still mentioned by its old
  name in a comment, panic message, error string, doctest, or
  module-level prose
- A `mod` add / remove / rename leaves the parent module's
  module-level docstring stale
- A new identifier's name claims a property the implementation
  does not enforce / does not produce

**N/A:** the diff renames / removes nothing, adds / removes /
renames no modules, and adds no identifiers whose name
encodes a behavioral claim.

## Output format

```
self-audit: <commit-range or "uncommitted">

| # | Item                          | Result | Evidence                                | Note                                           |
|---|-------------------------------|--------|-----------------------------------------|------------------------------------------------|
| 1 | Invariant derivation          | ⚠      | read: src/foo.rs:42                     | <what's wrong / what to fix>                   |
| 2 | Purpose verification          | ✅     | manual: ran example with input X        |                                                |
| 3 | Pattern audit                 | ✅     | re-derived f32 path; sibling f64 ok     |                                                |
| 4 | Scope discipline              | ⊘ N/A  |                                         | no findings dismissed                          |
| 5 | Behavior coverage             | ✅     | cargo test (incl. error_path tests)     |                                                |
| 6 | Implementation guards         | ⚠      | read: src/foo.rs:120                    | new invariant only commented, no assert        |
| 7 | Impact / caller verification  | ⊘ N/A  |                                         | no public symbol changed                       |
| 8 | Test execution                | ✅     | cargo test: 84 passed, 0 failed         |                                                |
| 9 | Completion hygiene            | ✅     | cargo clippy clean, cargo fmt --check   |                                                |
|10 | Architectural boundary        | ⊘ N/A  |                                         | no new imports / dep edges / pub widening      |
|11 | Textual-drift sweep           | ✅     | rg <old-name>; parent //! re-read       |                                                |
```

If any ⚠ remains, fix before proceeding. State concretely what will
change. Do not proceed until concerns are resolved or the user
explicitly waives them with reasoning.
