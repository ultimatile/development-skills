# Test execution [contextual]

The relevant test suite was actually run, the results were observed, and any failures were investigated. "Compiles clean" or "existing tests pass without re-running them" is not pass.

If a baseline (pre-existing failures recorded before implementation began) exists, distinguish new failures from pre-existing ones. New regressions are concerns regardless of the project's prior state.

**Build-preset coverage on signature changes.** When the diff changes a public function signature in a way that requires every caller to be updated (parameter add / remove / reorder, type substitution, strong-typedef wrapping over a previously-raw type), test execution must cover **all production build presets** that the project ships — not just the development preset. Feature-flag-gated source files (e.g., BP-on, MPI-on, GPU-on test suites that only build under the corresponding preset) are common sites where compile failures from the migration go unobserved when only the dev preset is exercised. The relevant question is: "for every preset listed in the project's preset / build-config registry, does the touched API still compile?" — with strong-typedef migrations the type system is the verification mechanism, so a code path that does not get built passes the type check vacuously and silently keeps old call forms. Building under the alternative presets is the only way to surface those.

**Concern conditions:**

- Tests were not actually executed against the diff
- Tests fail and the failures were not investigated
- New regressions vs baseline are present and not addressed
- Signature-changing diff was tested only under the development preset; feature-flag-gated presets (BP-on, MPI-on, GPU-on, etc.) were not built, leaving compile failures in flag-gated code unobserved

**N/A:** truly mechanical changes (rename, formatting, file move) where there is no test surface to exercise.
