---
name: todo-check
description: Preflight sweep of quality-list items, and of authoritative-text-rules when the planned scope calls for it, before or during implementation. Framed as 'what to set up so done-check's rows pass at the end'.
---

# Todo-Check

Forward-looking preflight against the planned change. This skill is the **runner**; item definitions live in the rule-set SSOTs it applies — `quality-list` for universal code quality, and `authoritative-text-rules` for text the agent executes as instructions. Update the owning SSOT, not this file, when adding or modifying items.

`done-check` asks: "Did the diff satisfy item N?" `todo-check` asks: "What does item N require us to set up so the diff will satisfy it?" On `quality-list` the two apply the same mechanical / contextual lane split (its Item lanes section): mechanical-lane items go to a fresh-context subagent (Step 2), contextual-lane items stay in main context (Step 3). Both also apply `authoritative-text-rules` when the change calls for it — `done-check` on its own diff-path firing rule at its Step 2, `todo-check` on the scope-description firing rule at Step 3 below. There the two runners diverge on receiver: `done-check` spawns a second fresh-context subagent, testing the finished text against the item bodies' literal readings; `todo-check` reads those items in main context so the writer holds them while the plan is still revisable. `done-check`'s independent fresh-context audit is unchanged by this reading here.

## Procedure

0. **Resolve the active rule set.** Resolve two absolute paths first, and use them everywhere below: `<SKILLS_DIR>`, the directory holding this skill's own directory, and `<TARGET_ROOT>`, the project this preflight is for (cwd). Every read of a rule file — main context's as much as the subagent's — resolves against `<SKILLS_DIR>`, so both paths are resolved here and carried, never re-derived downstream.

   `<SKILLS_DIR>` is `${CLAUDE_SKILL_DIR}/..`.

   Base items live in `<SKILLS_DIR>/quality-list/SKILL.md`; language-specific addenda at `<SKILLS_DIR>/quality-list/lang-<language>.md` realize them concretely. Verify `<SKILLS_DIR>/quality-list/SKILL.md` is present here, before anything reads it. A rule set that is not there halts, reporting the file looked for and the directory looked in, so that whoever reads the halt can tell a wrong `<SKILLS_DIR>` from a rule set that is not installed.

   Detect language from `<TARGET_ROOT>/CLAUDE.md`'s `Language:` declaration — the target's, never one found beside the rule files; otherwise auto-detect from the extensions of the files the work will likely touch — taken from the plan or task description, since Step 0 runs before Step 1 formalizes the scope (`.rs` → rust, `.cpp`/`.cc`/`.cxx`/`.h`/`.hpp` → cpp, `.py` → python, `.ts`/`.tsx` → typescript, `.go` → go, etc.). Multi-language projects detect every present language; each matching addendum applies. Missing addendum → base rules only for that language (not a concern). Step 0 only **detects** the language(s); it routes nothing. Each consumer — the Step 2 mechanical subagent and the Step 3 contextual pass — loads every matching addendum file itself.

1. **Describe the planned change.** State in plain terms what the change will do: the files / modules it will touch, the behavior it will change, the public symbols / schemas / contracts it will move, and the invariants it introduces or modifies. Capture what is already decided; leave the rest unstated — an unsettled fact surfaces as a `? unknown` row below, not a guess. State the language(s) Step 0 detected here too, so the subagent applies the same addenda the contextual lane does rather than re-deriving them from a scope description that may name modules without file extensions. **Do not pre-classify the change against individual items** — the subagent (Step 2) and the contextual pass (Step 3) read each item's body and decide applicability themselves; the scope description is a plain account of the change, not a per-item trigger checklist.

   `todo-check` also runs mid-implementation. When earlier units are already materialized on disk, name their inspectable revision range in the scope description too, so the subagent reads the real code instead of treating the tree as unwritten. Name a **committed** range only when earlier units are already committed; it takes a **root** on `diff-root`'s consumer contract, halt included, and that skill's per-command conversion. A run with no committed units names no such range and so needs no root — a preflight runs against work that does not exist yet, and its scope description, not the repository, is what says how much of it is written. `done-check` has no equivalent case: it audits work that exists, and whether that work includes commits is what a root decides rather than something the audit may assume. The working-tree commands below still apply in that case.

   ```bash
   git log --oneline <root-rev>..HEAD           # committed units
   git diff <root-rev>...HEAD                   # committed content
   git diff --cached                        # staged
   git diff                                 # unstaged
   git ls-files --others --exclude-standard # untracked paths
   ```

   State that this range is **part of the change under preflight**, not pre-existing baseline to reuse from — a helper just added there is a candidate for `duplication-extraction`'s search, not an existing helper the search should call.

2. **Spawn a fresh-context preflight subagent for the mechanical items.** A fresh context removes the author's blindspot for what the planned scope actually implies, and keeps the item-body rule text out of main context.

   **Main context MUST NOT load a purely-mechanical item's body** (the dual-lane `ported-code-attribution` body is the one exception, read in Step 3 for its contextual half). The subagent reads the index and those bodies in its own fresh context — it derives the mechanical-lane item set from the index itself; main only composes the prompt (scope description + the resolved paths) and dispatches.

   The prompt carries the two absolute paths Step 0 resolved; the subagent needs both.

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

   First read <SKILLS_DIR>/quality-list/SKILL.md and
   consult its Items index. Select every item whose lane is
   `mechanical`, including the mechanical half of any dual-lane item (an
   entry tagged `mechanical (+ contextual half)`, e.g.
   ported-code-attribution — handle only its declared-port signal; the
   undeclared-port signal is main context's job, but still return a row
   for the item even when its declared half is ⊘ N/A, so the coverage
   check sees it). Read each selected item's
   <SKILLS_DIR>/quality-list/items/<slug>.md in full.

   Where an item body or addendum spells a detection command
   containing `<root-rev>`, substitute the revision form
   `diff-root` derives from the root given below, not the root
   itself. When no root is given, that command does not run —
   follow the rule in <SKILLS_DIR>/quality-list/SKILL.md.

   The language(s) Step 0 detected are stated below; load each
   corresponding addendum at
   <SKILLS_DIR>/quality-list/lang-<lang>.md that exists,
   loading them all when more than one applies. If none are stated, fall
   back to the `Language:` line of <TARGET_ROOT>/CLAUDE.md — that file
   and no other CLAUDE.md, whatever its location — then to the file
   extensions in the scope description. No language found, or a
   detected language with no addendum file, is not a concern —
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

   Embed the scope description (Step 1), the language(s) Step 0 detected, the root when Step 1 named a range, and the two resolved paths. The root is what an item body's or addendum's detection command needs to name a range. **Do not embed item body text** — the subagent reads the item files itself.

   Start Step 3 immediately rather than waiting; the two run in parallel. Block on the subagent's return once you reach Step 4.

3. **Process the contextual items in main context.** Read `<SKILLS_DIR>/quality-list/SKILL.md`'s Items index and select every item whose lane is `contextual`, including the contextual half of dual-lane items — `ported-code-attribution`'s undeclared-port signal is main's job because it needs the conversation / research history the subagent lacks. These need plan / intent / review history, or command-execution planning against the working tree.

   For each selected contextual item, `Read` its `<SKILLS_DIR>/quality-list/items/<slug>.md` body — plus every `lang-<lang>.md` addendum section for a language Step 0 detected, self-loaded here — before deciding its status. Read only the contextual-lane bodies — plus `ported-code-attribution`'s own body, which the undeclared-port half is decided from even though the item is index-tagged `mechanical (+ contextual half)` — not a purely mechanical-lane item's body. For each, determine one of:

   - **△ active** — this item will apply to the finished diff; record the concrete setup action to do *now* (fixture variants, guard locations, paired-artifact surfaces, probes to thread through).
   - **⊘ N/A** — the item's own N/A criterion excludes the scope. State why.
   - **? unknown** — the body is read, but applicability turns on a scope fact not yet settled; record the scope check that would decide it.

   **Firing rule for `authoritative-text-rules`.** After processing the `quality-list` contextual items, apply this rule set when Step 1's scope description names a path whose location could hold text an agent executes as instructions — skill bodies; rule / item definition files; `CLAUDE.md`, `AGENTS.md`; files under `.claude/rules/`, `.claude/commands/`, `.claude/agents/`, or the equivalents other tools define — or describes new content of that kind. **Fire when unsure.**

   The rule approximates because it has to: `authoritative-text-rules`' membership predicate is a property of a file's *content*, while the scope description names only anticipated *paths and content descriptions*. It errs toward firing: a missed fire is a silently-skipped preflight, while a needless one costs one main-context pass returning ⊘ N/A rows. Deciding authoritatively which surfaces qualify is that SSOT's Scope section, applied within the pass below — Step 3 decides only whether the preview runs.

   When the firing rule fires, verify `<SKILLS_DIR>/authoritative-text-rules/SKILL.md` is present, on the same terms Step 0 verified `quality-list`: absent halts the same way. Step 0 having found `quality-list` under this `<SKILLS_DIR>` narrows the cause — the directory is the right one, so what is missing is the rule set itself. A run whose firing rule did not fire takes no such check: an uninstalled rule set the preflight was never going to touch does not halt the preflight.

   Then read `<SKILLS_DIR>/authoritative-text-rules/SKILL.md`'s Items index; for every item it lists, `Read` its `<SKILLS_DIR>/authoritative-text-rules/items/<slug>.md` body before deciding status. Apply that SSOT's Scope section to Step 1's paths and content descriptions to decide which surfaces qualify; a fired preview whose surfaces all fall outside that Scope section returns ⊘ N/A rows for the whole set. For each item, determine △ active / ⊘ N/A / ? unknown on the same terms as the `quality-list` contextual items above.

   The authoritative-text items are read in main context because the writer is who must hold their guarantees while drafting; a fresh-context subagent lacks the plan intent that decides which setup fits.

4. **Merge results.** Integrate the mechanical-lane rows the subagent returned with the contextual-lane rows (Step 3) into a single table.

   ```
   domain: every item in the `<SKILLS_DIR>/quality-list/SKILL.md` Items index

   coverage — the subagent's returned mechanical rows against the
   mechanical-lane slug set the index predicts. This applies to a
   full-set dispatch; a narrowed single-item return (Step 5) is exempt:
     exactly one row per predicted slug,
     and no others                        → proceed
     any other return (a slug missing,
     duplicated, or outside the predicted
     set), first occurrence               → re-dispatch Step 2 with the
                                            prompt unchanged; re-check
     any other return, after that
     re-dispatch                          → surface to the user; do not
                                            proceed with the mechanical
                                            lane incomplete, and do not
                                            emit the table

   row rendering — one row per item, in index order:
     single-lane item                     → that lane's verdict
     dual-lane, either half △             → △ active; name which half
     dual-lane, both halves ⊘             → ⊘ N/A
     dual-lane, otherwise                 → ?
   ```

   A half left `?` at merge time carries its scope check forward to Step 5, so the half's own setup action is not lost behind an active status.

   When Step 3's authoritative-text firing rule fired, append its rows below the `quality-list` rows above, one per item in the `<SKILLS_DIR>/authoritative-text-rules/SKILL.md` Items index, in that index's order. These rows take no coverage check, on the same terms main-context contextual-lane rows take none: main selects them from the index directly, with no return to compare against.

   If the subagent returned a discrepancy list, adjudicate each: correct the affected row's setup action to match what the subagent found, or — if the scope description was right and the subagent's codebase read was the mistaken side — note that resolution instead rather than rewriting the row.

5. **Resolve every `?` before declaring preflight done.**

   ```
   domain: every unsettled scope check — the one behind a `?` row that
           is not a dual-lane row, and one per unsettled half of any
           dual-lane row, which can therefore carry two. Each check
           has a single settlement path; settle them one at a time.

   pass 1 — settle the scope fact, by the lane of the check being settled:
     mechanical lane, and the subagent
     stated a verdict per answer to its
     scope check                          → settle the fact; read the
                                            matching verdict off. If the
                                            settled answer is not one it
                                            enumerated, take the arm below
     mechanical lane, otherwise           → narrowed re-dispatch (below)
     contextual lane, or an
     authoritative-text row               → settle the scope check Step 3
                                            recorded, in main context

   pass 2 — record the outcome:
     settled, `?` row that is not a
     dual-lane row                        → △ with a concrete setup action
                                          | ⊘ with a reason
     settled, a half of a dual-lane row   → add that half's own setup action
                                            to the row's Setup action cell,
                                            or note the half N/A there with
                                            its reason, alongside whatever
                                            the other half already put there.
                                            The row's status is then Step 4's
                                            row-rendering rule over its two
                                            half-statuses, so a row already
                                            rendered △ stays △
     could not be settled at preflight
     time                                 → surface to the user, naming what
                                            the row already carries; do not
                                            declare preflight done, and do not
                                            emit the table

   always: never read a purely-mechanical item's body in main context.
   always: a setup action that names a command to run (e.g.
           `public-api-surface`'s `cargo public-api` baseline) is still a
           planning action — state that the command runs before
           implementation, don't run it now.
   ```

   **Narrowed re-dispatch.** Re-dispatch the subagent with the Step 2 prompt narrowed to that one item — replace its "Select every item whose lane is `mechanical`…" sentence with "Process only `<slug>`", or for `ported-code-attribution` with "Process only `ported-code-attribution`'s declared-port signal (the undeclared-port signal stays main context's job)", keeping the sentence after it that tells the subagent to read the selected item's body in full. Its single-item return is exempt from Step 4's whole-set coverage check.

6. **Report the preflight table.** Hand the △ rows to the implementation step as setup actions.

## Preflight framing per item (quick reference)

These are how each item reads in preflight mode — a compressed mnemonic of the lens-shift from the item's audit question to a preflight setup action. A row is **not** the applicability authority and decides nothing: Step 3 reads each item's body (`<SKILLS_DIR>/quality-list/items/<slug>.md` for a `quality-list` item, `<SKILLS_DIR>/authoritative-text-rules/items/<slug>.md` for an authoritative-text one) plus any applicable addendum, and that — with the index as the item set — decides whether it applies. Consult a row for its setup framing once the body has marked the item active.

This list covers the `quality-list` contextual-lane items (and the contextual half of the dual-lane item) that Step 3 processes in main context, and the `authoritative-text-rules` items that Step 3 processes in main context when the firing rule fires. Mechanical-lane `quality-list` items have no row *in this quick reference* (they still get a row in the final preflight table, per Step 4): the subagent never reads this file, so a mnemonic for it would have no consumer.

**For `quality-list` items (contextual-lane and the contextual half of the dual-lane item):**

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

**For `authoritative-text-rules` items (when the preview fires):**

- **`case-space-totality`** — Before writing condition→outcome authoritative text, enumerate the domain axes the rule branches on; plan for each cell to reach exactly one outcome and for mirrored cases to be treated symmetrically or excluded with a reason.
- **`single-reading`** — Before writing sentences in authoritative text, plan to hold the ambiguity-guard checkpoints during drafting; the item body holds the catalogue.
- **`clause-composition`** — Before editing a clause in a rule set holding more than one unit, plan the rule-set fix that the inbound + outbound reference sweep runs over; the item body defines the search-key derivation.
- **`executor-fitness`** — Before writing a step that names an executor, list what the step will demand and quote the written definition of the executor's inputs; plan to reconcile any gap before writing the step.
- **`consumer-closure`** — Before emitting a value or imposing an obligation, freeze the emitted-value / obligation list up front and plan to identify each consuming step or receiver.

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

Emit one row per item in the `<SKILLS_DIR>/quality-list/SKILL.md` Items index, in index order, followed — when Step 3's authoritative-text firing rule fired — by every item in the `<SKILLS_DIR>/authoritative-text-rules/SKILL.md` Items index, in that index's order. The rows above illustrate the format and the status vocabulary (△ active / ⊘ N/A), not the full set. `? unknown` is a working state that Step 5 resolves, so it never appears in the final table. Only a preflight that reaches Step 6 emits a table at all; every halt above ends it without one, however many such halts the steps above come to hold. The table merges the mechanical-lane rows (Step 2's subagent) with Step 3's main-context rows (`quality-list` contextual + any `authoritative-text-rules` rows Step 3 loaded when the firing rule fired), per Step 4. Hand the △ rows forward as the implementation setup.
