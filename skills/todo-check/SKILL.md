---
name: todo-check
description: Preflight sweep of quality-list items before or during implementation, framed as 'what to set up so done-check passes at the end'. Dual of done-check.
---

# Todo-Check

Forward-looking preflight against the planned change. Item definitions live in `quality-list`; this skill is the **runner**. Update `quality-list`, not this file, when adding or modifying items.

`done-check` asks: "Did the diff satisfy item N?" `todo-check` asks: "What does item N require us to set up so the diff will satisfy it?" Same mechanical / contextual lane split as `done-check` (`quality-list/SKILL.md`'s Item lanes section): mechanical-lane items go to a fresh-context subagent (Step 2), contextual-lane items stay in main context (Step 3).

## Procedure

0. **Resolve the active rule set.** Base items live in `quality-list/SKILL.md`; language-specific addenda at `quality-list/lang-<language>.md` realize them concretely.

   Detect language from the project's `CLAUDE.md` `Language:` declaration; otherwise auto-detect from the extensions of the files the work will touch (`.rs` → rust, `.cpp`/`.cc`/`.cxx`/`.h`/`.hpp` → cpp, `.py` → python, `.ts`/`.tsx` → typescript, `.go` → go, etc.). Multi-language projects detect every present language; each matching addendum applies. Missing addendum → base rules only for that language (not a concern). Step 0 only **detects** the language(s); it routes nothing. Each consumer — the Step 2 mechanical subagent and the Step 3 contextual pass — loads every matching addendum file itself.

1. **Describe the planned change.** State in plain terms what the change will do: the files / modules it will touch, the behavior it will change, the public symbols / schemas / contracts it will move, and the invariants it introduces or modifies. Capture what is already decided; leave the rest unstated — an unsettled fact surfaces as a `? unknown` row below, not a guess. State the language(s) Step 0 detected here too, so the subagent applies the same addenda the contextual lane does rather than re-deriving them from a scope description that may name modules without file extensions. **Do not pre-classify the change against individual items** — the subagent (Step 2) and the contextual pass (Step 3) read each item's body and decide applicability themselves; the scope description is a plain account of the change, not a per-item trigger checklist.

   `todo-check` also runs mid-implementation. When earlier units are already materialized on disk, name their inspectable revision range in the scope description too, so the subagent reads the real code instead of treating the tree as unwritten:

   ```bash
   git log --oneline @{upstream}..HEAD      # committed units
   git diff @{upstream}..HEAD               # committed content
   git diff --cached                        # staged
   git diff                                 # unstaged
   git ls-files --others --exclude-standard # untracked paths
   ```

   State that this range is **part of the change under preflight**, not pre-existing baseline to reuse from — a helper just added there is a candidate for `duplication-extraction`'s search, not an existing helper the search should call.

2. **Spawn a fresh-context preflight subagent for the mechanical items.** A fresh context removes the author's blindspot for what the planned scope actually implies, and keeps the item-body rule text out of main context.

   **Main context MUST NOT load the mechanical item bodies.** The subagent reads the index and those bodies in its own fresh context — it derives the mechanical-lane item set from the index itself; main only composes the prompt (scope description + the resolved paths) and dispatches.

   Resolve two absolute paths first: `<QUALITY_LIST_ROOT>`, the repo/package root containing the `skills/quality-list/` directory, and `<TARGET_ROOT>`, the project this preflight is for (cwd) — they coincide only when `quality-list` is vendored inside the target; in a marketplace / symlinked install they differ, and the subagent needs both.

   Use the `Agent` tool with `subagent_type: "general-purpose"` and a prompt of the following shape:

   ```
   You are running a PREFLIGHT (not an audit) against a planned change,
   under the `quality-list` quality rules. You have NO access to the
   conversation history that produced this scope and MUST NOT speculate
   about author intent beyond the scope description below. Judge from:

   - the literal scope description (provided below)
   - if the scope description names an already-materialized revision
     range, the code in that range — treat it as part of the change
     under preflight, not as pre-existing baseline
   - the literal text of the relevant `quality-list` item files (read
     them yourself from the paths below)
   - the literal text of the codebase at <TARGET_ROOT> you can read with
     your tools (existing helpers, current callers, paired-artifact
     surfaces)

   The scope description's characterizations of EXISTING code ("no
   helper for this exists yet", "sibling X already exposes a symmetric
   surface") are the author's working hypothesis — sanity-check them
   against what you can read in the codebase, and flag any discrepancy
   in your report. A characterization of the not-yet-written change
   itself has nothing to check against — take it as given.

   First read <QUALITY_LIST_ROOT>/skills/quality-list/SKILL.md and
   consult its Items index. Select every item whose lane is
   `mechanical`, including the mechanical half of any dual-lane item (an
   entry tagged `mechanical (+ contextual half)`, e.g.
   ported-code-attribution — handle only its declared-port signal; the
   undeclared-port signal is main context's job). Read each selected
   item's <QUALITY_LIST_ROOT>/skills/quality-list/items/<slug>.md in
   full.

   Also load every language addendum at
   <QUALITY_LIST_ROOT>/skills/quality-list/lang-<lang>.md that exists
   for a detected project language, loading them all when more than one
   applies. Determine the language(s) from the scope description if it
   states what Step 0 detected; otherwise from <TARGET_ROOT>/CLAUDE.md's
   `Language:` line (never <QUALITY_LIST_ROOT>/CLAUDE.md); otherwise
   from the file extensions in the scope description. No language found,
   or a detected language with no addendum file, is not a concern —
   proceed on base rules.

   For each selected item return one of:

   - △ active — this item will apply to the finished diff; state the
     concrete preflight setup action (test fixture variants, guard
     locations, paired-artifact surfaces to sweep, existing-helper
     search results, etc.), grounded in the scope description and the
     codebase.
   - ⊘ N/A — using only the item's own N/A criterion as stated.
   - ? unknown — the body is read, but applicability turns on a scope
     fact not given; state the scope check that would decide it AND the
     resulting verdict for each possible answer, so it can be resolved
     later without re-reading the body.

   Report concisely: one row per item with Status + Setup action / N/A
   reason / scope check; then a final list of any discrepancies between
   the scope description and what you read in the codebase.
   ```

   Embed only the scope description (Step 1) and the two resolved paths. **Do not embed item body text** — the subagent reads the item files itself.

   Start Step 3 immediately rather than waiting; the two run in parallel. Block on the subagent's return once you reach Step 4.

3. **Process the contextual items in main context.** Read `quality-list/SKILL.md`'s Items index and select every item whose lane is `contextual`, including the contextual half of dual-lane items — `ported-code-attribution`'s undeclared-port signal is main's job because it needs the conversation / research history the subagent lacks. These need plan / intent / review history, or command-execution planning against the working tree.

   For each selected contextual item, `Read` its `quality-list/items/<slug>.md` body — plus every `lang-<lang>.md` addendum section for a language Step 0 detected, self-loaded here — before deciding its status. Read only the contextual-lane bodies — plus `ported-code-attribution`'s own body, which the undeclared-port half is decided from even though the item is index-tagged `mechanical (+ contextual half)` — not a purely mechanical-lane item's body. For each, determine one of:

   - **△ active** — this item will apply to the finished diff; record the concrete setup action to do *now* (fixture variants, guard locations, paired-artifact surfaces, probes to thread through).
   - **⊘ N/A** — the item's own N/A criterion excludes the scope. State why.
   - **? unknown** — the body is read, but applicability turns on a scope fact not yet settled; record the scope check that would decide it.

4. **Merge results.** When the subagent returns, integrate its mechanical-lane rows with the contextual-lane rows (Step 3) into a single table, one row per item in index order. Confirm the returned rows cover exactly the mechanical-lane slug set the index predicts — a missing or duplicated slug is a failure, not a clean pass; re-dispatch once with the same prompt, and if it fails again, surface to the user rather than proceeding with the mechanical lane incomplete. Render each dual-lane item as one row: △ active if either half is active (note which; if the other half is `?`, carry that unresolved half's scope check forward to Step 5 so its own setup action is not lost behind the active status), ⊘ N/A only if both halves are N/A, otherwise `?`. If the subagent returned a discrepancy list, correct each affected row's setup action to match what it found in the codebase.

5. **Resolve every `?` before declaring preflight done** — promote to △ with a concrete setup action, or downgrade to ⊘ with a reason. Resolve both a row whose overall status is `?` and an unresolved half carried forward from an otherwise-active dual-lane row (Step 4). For a mechanical-lane `?`: if the subagent stated the verdict for each answer to its scope check, settle the fact and read the matching verdict off; otherwise re-dispatch the subagent with the Step 2 prompt narrowed to that one item — replace its "Select every item whose lane is `mechanical`…" sentence with "Process only `<slug>`" (keeping the following read-the-body instruction), which also drops Step 4's whole-set coverage check for that single-item return. Never read the mechanical item's body in main context. A setup action that names a command to run (e.g. `public-api-surface`'s `cargo public-api` baseline) is still a planning action — state that the command runs before implementation, don't run it now.

6. **Report the preflight table.** Hand the △ rows to the implementation step as setup actions.

**When to skip the subagent (Step 2).** Skip only when the planned change is formatting-only — no semantic content change at all (whitespace, list renumbering, table padding). Mark every mechanical-lane item ⊘ N/A directly from the index's lane tags and proceed to Step 3. Anything else runs the subagent; do not try to enumerate which items a rename / signature / doc change would trigger — that is exactly the item-body detail the subagent owns.

## Preflight framing per item (quick reference)

These are how each `quality-list` item reads in preflight mode — a compressed mnemonic of the lens-shift from the item's audit question to a preflight setup action. A row is **not** the applicability authority and decides nothing: Step 3 reads each contextual item's body (`quality-list/items/<slug>.md`) plus any applicable addendum, and that — with the index as the item set — decides whether it applies. Consult a row for its setup framing once the body has marked the item active.

This list covers only the contextual-lane items (and the contextual half of the dual-lane item) that Step 3 processes. Mechanical-lane items have no row: the subagent never reads this file, so a mnemonic for it would have no consumer.

- **`invariant-derivation`** — Before patching, derive the full necessary-and-sufficient condition from first principles. List it in the plan.
- **`purpose-verification`** — Identify the input that exposes the purpose end-to-end. Plan to exercise it before declaring done.
- **`pattern-audit`** — Plan to re-derive any reused sibling pattern's correctness in the current context before relying on it.
- **`scope-discipline`** — Resolve to evaluate findings on their merits, not narrowed to the originating task.
- **`test-execution`** — Plan which test commands will be run, and capture the pre-existing failure baseline before any edit.
- **`completion-hygiene`** — Plan which lint / format / type-check / build commands will be run. Note any debug artifacts to strip.
- **`escape-hatch-necessity`** — Plan to derive any workaround's necessity before using it, treating it as a last resort rather than a default.
- **`docstring-drift`** — List the docstring / comment / README surfaces describing any behavior the change alters, and plan a cold-read re-verification of each against the new behavior, with an execution probe where the behavior becomes library-owned.
- **`discovery-surfacing`** — Extract any research plan's `Inconclusive` items into a watch list for the implementation phase.
- **`ported-code-attribution`** (undeclared-port half) — If research surfaced an external implementation this scope structurally follows but hasn't named, plan the attribution surface now even though no comment names it yet.

## Output format

```
preflight: <task / unit description>

| Item                          | Status   | Setup action / N/A reason                              |
|-------------------------------|----------|--------------------------------------------------------|
| invariant-derivation          | △ active | derive condition for <invariant> from <constraint>     |
| scope-discipline              | ⊘ N/A    | no findings raised yet                                 |
| behavior-coverage             | △ active | fixtures: 3-site MPS bulk variant, non-square 2×3 ...  |
| implementation-guards         | △ active | assert! at <site>; review siblings <a>, <b>            |
| architectural-boundary        | ⊘ N/A    | no new imports / dep edges / pub widening              |
| paired-artifact-drift         | △ active | sweep: examples/foo.rs, README.md, doctests in <mod>   |
| discovery-surfacing           | △ active | watch: inconclusive[1] probe at <site>; branches X/Y   |
```

Emit one row per item in the `quality-list/SKILL.md` Items index, in index order — the rows above illustrate the format and the status vocabulary (△ active / ⊘ N/A), not the full set. `? unknown` is a working state Step 5 resolves before this report is emitted; it never appears in the final table. The table merges the mechanical-lane rows (Step 2's subagent) with Step 3's contextual-lane rows, per Step 4. Hand the △ rows forward as the implementation setup.
