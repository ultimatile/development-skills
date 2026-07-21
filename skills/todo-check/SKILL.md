---
name: todo-check
description: Preflight sweep of quality-list items before or during implementation, framed as 'what to set up so done-check passes at the end'. Dual of done-check.
---

# Todo-Check

Forward-looking preflight against the current scope. Item definitions live in `quality-list`; this skill is the **runner**. Update `quality-list`, not this file, when adding or modifying items.

`done-check` asks: "Did the diff satisfy item N?" `todo-check` asks: "What does item N require us to set up so the diff will satisfy it?" Mirrors `done-check`'s mechanical/contextual lane split (`quality-list/SKILL.md`'s Item lanes section): mechanical-lane items delegate to a fresh-context subagent (barring a narrow skip case Step 2 defines), contextual-lane items stay in main context.

## Procedure

0. **Resolve the active rule set.**

   The base rule set lives in `quality-list/SKILL.md`. Language-specific addenda live alongside it as `quality-list/lang-<language>.md` and supplement the base rules with triggers, mitigation idioms, and mechanical detection patterns for the language. Items themselves stay language-neutral in the base file; addenda only realize them concretely.

   Detection order for the project language:

   1. Check the project's `CLAUDE.md` (or equivalent contributor / agent-guidance file) for a `Language:` declaration line (e.g., `Language: cpp`). If present, note that `quality-list/lang-<value>.md` applies.
   2. Otherwise, auto-detect from file extensions present in the scope (or the work's likely-touched files): `.cpp` / `.cc` / `.cxx` / `.h` / `.hpp` / `.hh` → `cpp`; `.rs` → `rust`; `.py` → `python`; `.ts` / `.tsx` → `typescript`; `.go` → `go`; etc.
   3. Multi-language projects: note every matching `lang-*.md` (one per language present) — this step only identifies which addenda apply; it does not load them.

   If a detected language has no `lang-<lang>.md`, fall back to the base rules only. Missing addenda are not a concern — they just mean no curated language realizations exist yet.

   Step 0 only **detects** the language(s); it routes nothing. Each consumer — the Step 2 mechanical subagent and the Step 3 contextual pass — loads every matching addendum file itself.

1. **Identify the work scope.** Pull from the plan if one exists, otherwise from the current task description. Determine:

   - What files / modules will change — name concrete file paths, not just abstract module descriptions; say explicitly whether any of them is `README.md`, `docs/**/*.md`, or another top-level `*.md` (relevant to `public-doc-durability`, a mechanical item whose applicability turns entirely on this planned fact)
   - Which language(s) Step 0 already detected — state the result directly (e.g. "rust, per `CLAUDE.md`'s `Language:` line"); Step 2's subagent uses this stated fact when given, rather than needing to re-derive it, falling back to its own detection (per Step 2) only when this is left unstated
   - What public symbols, schemas, or contracts will move, and — where already known — a plain description of how the change's behavior differs from before (relevant to `impact-verification`, a mechanical item — describe it in your own words; the subagent maps this onto that item's own taxonomy itself, since main does not read mechanical item bodies)
   - What invariants the change introduces or modifies
   - Whether the change renames or removes any identifier/module that other surfaces reference, or changes any function/method's parameter list at all, in-unit or not — Step 2's skip decision needs every such change regardless of call-site location; whether the call sites live outside the touched unit is a further fact needed only for `signature-change-regression`'s own applicability (and for `paired-artifact-drift`, renames/removals generally)
   - What new constructs are planned that resemble existing scaffolding or patterns, each construct's purpose, and any deliberate-independence rationale (relevant to `duplication-extraction`); for a new/changed implementation intentionally parallel to an existing sibling, whether a symmetric public surface is intended or an asymmetry is domain-justified and why (relevant to `public-api-surface`)
   - What external implementations, if any, were referenced during research or planning, even if not (yet) copied verbatim (relevant to `ported-code-attribution`)
   - Whether a research plan with `Inconclusive / Deferred items` exists (relevant to `discovery-surfacing`)
   - Any other structural fact a mechanical item might need to decide applicability or shape a setup action — new dependency edges the change will introduce (relevant to `architectural-boundary`), the test axes/parameters new or changed behavior should be exercised across (relevant to `behavior-coverage`), etc. Capture what's already decided; leave the rest for `? unknown` rather than guessing

   Write this down as a short **scope description** — it serves both Step 2 and Step 3 below, but plays a different role for each: for Step 2's subagent, it's the bounded, self-contained artifact received in place of a diff, for the *upcoming* work this preflight is planning — todo-check also runs mid-implementation (per this skill's own description), where earlier units may already have a real, materialized diff on disk; when that's the case, name it here too (e.g. "units 1-2 already committed, touching src/foo.rs and src/bar.rs") so the subagent can inspect it directly at `<TARGET_ROOT>` instead of treating the whole codebase as unwritten; for Step 3, it's a written anchor alongside the fuller plan / conversation / research history Step 3 already has independent access to. A field left unknown at this point is legitimate, not a blocking gate on this step: Step 2's subagent may still resolve a given mechanical item's applicability from the rest of the scope description plus its own codebase reading, and Step 3 draws on that fuller history regardless of what got captured here — so only an item whose own applicability genuinely turns on the missing fact, unresolvable from either source, surfaces as a `? unknown` row below.

2. **Spawn a fresh-context preflight subagent for the mechanical-lane items.** Mirrors `done-check` Step 2: a fresh-context subagent removes the author's blindspot for what the planned scope actually implies, and keeps the item-body rule text out of main context.

   **When to skip this subagent.** Check this first, before dispatching anything. Skip only when EITHER holds:

   - The change is formatting-only: no semantic content change at all (whitespace, table padding, list renumbering, or an equivalent purely-cosmetic diff) — which by definition already carries no identifier rename, no parameter-list change, and no new doc content, so nothing further to check.
   - It is a file move/rename that touches no identifier, module, or import/module path any other surface references or depends on — checked against the whole public surface, not just in-repo callers: moving or renaming any `pub` (or otherwise externally-visible) symbol's declared path always fails this branch even with zero in-repo references, since external consumers aren't repo-searchable — changes no function/method's parameter list *at all* (any change, not just removal/reorder/substitution — don't try to replicate `signature-change-regression`'s exact carve-out here either, for the same staleness-avoidance reason as the `*.md` case below), and touches no `*.md` file at all (don't try to replicate `public-doc-durability`'s own carve-outs here — treating every `*.md` touch as disqualifying is deliberately broader than that item's actual N/A criteria, so it errs toward running the subagent rather than copying and risking staleness against that item's own scope).

   Failing either test always runs the subagent, even when the rest of the change is otherwise trivial: a referenced rename/removal, a module path change, or a removed symbol is `paired-artifact-drift`'s own trigger; a moved/renamed public symbol's path is additionally `public-api-surface`'s own trigger, regardless of in-repo caller count; any parameter-list change to a function/method whose call sites live outside the touched unit is (a superset of) `signature-change-regression`'s own trigger; touching any `*.md` file with the change otherwise NOT qualifying as formatting-only (i.e. failing to skip via the first branch too) is `public-doc-durability`'s trigger surface (a superset of its actual scope, deliberately, per above) — a genuinely formatting-only edit to a `*.md` file (table padding, list renumbering) still skips via the first branch, since it changes no content for that item to catch.

   When either branch holds, mark every mechanical-lane item ⊘ N/A directly — including the dual-lane item's mechanical half (its contextual half is unaffected; Step 3 still produces that independently) — and do not spawn the subagent at all. Enumerate this set from the `quality-list/SKILL.md` index's lane tags alone (mechanical, plus the mechanical half of the dual-lane entry), the same index read Step 2 would otherwise dispatch the subagent to consult, never from any item's body. Proceed to Step 3 regardless — the skip only removes the subagent dispatch, not Step 3's own contextual-lane processing.

   Otherwise, dispatch. **Main context MUST NOT load a mechanical item's body itself to decide that item's applicability — that is the subagent's job**, once dispatch is warranted; the skip path above decides the change as a whole, not any one item's criterion, so it's a separate, category-level call, not an exception to this rule. The subagent reads the index and those bodies in its own fresh context — it derives the mechanical-lane item set from the index itself; main only composes the prompt (scope description + the two resolved paths below) and dispatches. (Step 3 below reads the dual-lane item's body too, separately, for its contextual half — a different purpose than deciding mechanical-lane applicability.)

   Resolve two absolute paths before composing the prompt: `<QUALITY_LIST_ROOT>`, the repo/package root that *contains* the `skills/quality-list/` directory (not that directory itself — every path below is `<QUALITY_LIST_ROOT>/skills/quality-list/...`), and `<TARGET_ROOT>`, the actual project this preflight is for (cwd) — the two coincide only when `quality-list` is vendored inside the project being preflighted; in a typical marketplace / symlinked install they differ, and the subagent needs both.

   Use the `Agent` tool with `subagent_type: "general-purpose"` and a prompt of the following shape:

   ```
   You are running a PREFLIGHT (not an audit) against a planned change,
   under the `quality-list` quality rules. You have NO access to the
   conversation history that produced this scope and MUST NOT speculate
   about author intent beyond the scope description below. If the scope
   description names files as already committed/materialized (this can
   happen — todo-check also runs mid-implementation, between units),
   treat that named diff as part of the change under preflight, not as
   pre-existing baseline to reuse from — e.g. a newly-added helper
   there is a candidate for `duplication-extraction`'s search, not an
   existing helper the search should call. Judge purely from:

   - the literal scope description (provided below): files / modules
     that will change; public symbols / schemas / contracts that will
     move, and their character of change if stated; invariants the
     change introduces or modifies; whether any referenced
     identifier/module is renamed or removed, or a parameter list
     changed for call sites outside the touched unit; planned
     constructs resembling existing patterns, their purpose, and any
     deliberate-independence rationale, including whether a
     symmetric public surface is intended for a parallel
     implementation; external implementations referenced during
     planning; and any other structural fact the scope description
     states.
     Treat the scope description's own characterizations of EXISTING
     code or patterns (e.g. "sibling X already exposes a symmetric
     surface", "no helper for this exists yet") as the author's
     working hypothesis, not settled fact — that much is checkable, so
     sanity-check it against what you can independently read in the
     codebase, and flag a discrepancy in your report rather than
     silently adopting the author's framing. A characterization of the
     PLANNED, not-yet-written change itself (a stated shift kind, a
     stated deliberate-independence rationale for a new construct) has
     no existing code to check against — take it as given, the only
     source available for something that doesn't exist yet
   - the literal text of the relevant `quality-list` item files (read
     them yourself from the paths below)
   - the literal text of the existing codebase at <TARGET_ROOT> that
     you can read with your tools (e.g. to find existing helpers,
     current callers, current paired-artifact surfaces)

   First read <QUALITY_LIST_ROOT>/skills/quality-list/SKILL.md and
   consult its Items index. Select every item whose lane is
   `mechanical`, including the mechanical half of any dual-lane item
   (an entry tagged `mechanical (+ contextual half)`, e.g.
   ported-code-attribution — handle only its declared-port signal; the
   undeclared-port signal is main context's job). Read each selected
   item's <QUALITY_LIST_ROOT>/skills/quality-list/items/<slug>.md in
   full.

   Determine the language(s) as follows, then — regardless of which
   branch below resolved it, and for every language found when more
   than one applies — load each corresponding
   <QUALITY_LIST_ROOT>/skills/quality-list/lang-<lang>.md addendum in
   full, if that file exists (a detected language with no such file
   is not a concern — just proceed on base rules for it, same as no
   language found at all): use the language(s) the scope description states Step 0
   already detected, if it states any — this is a claim about the
   existing project, not the planned change, so it's as checkable as
   any other existing-code characterization: if it looks inconsistent
   with the scope description's own file extensions, note that as a
   discrepancy too, per the report format below. Otherwise check
   `<TARGET_ROOT>/CLAUDE.md` (or an equivalent contributor /
   agent-guidance file at <TARGET_ROOT>) yourself for a `Language:`
   line — never `<QUALITY_LIST_ROOT>/CLAUDE.md`, since
   `<QUALITY_LIST_ROOT>` is not necessarily <TARGET_ROOT> and reading
   it there would not reliably reach the target project's actual
   `CLAUDE.md`. Absent that too,
   infer the language(s) yourself from the file extensions in the
   scope description's files/modules list (standard
   extension-to-language mapping — e.g. `.rs` → Rust, `.py` →
   Python). No language found by any branch → base rules only; this
   is not a concern.

   For each of these items return one of:

   - △ active — this item will apply to the finished diff; state the
     concrete preflight setup action (test fixture variants, guard
     locations, paired-artifact surfaces to sweep, existing-helper
     search results, etc.), grounded in the scope description and
     anything you find by reading the codebase at <TARGET_ROOT>.
   - ⊘ N/A — using only the item's own N/A criterion as stated
   - ? unknown — the body has been read, but applicability turns on a
     scope fact not given to you; state exactly what scope check would
     decide it, AND the resulting verdict (with its setup action or
     N/A reason) for each possible answer to that check — so the
     unknown can be resolved later from the fact alone, without a
     second read of this item's body

   Report concisely:
   - one row per item with Status + Setup action / N/A reason / scope
     check needed — for `? unknown`, this row must include the
     per-branch verdicts required above, not the scope check alone
   - a final list of any discrepancies between the scope description's
     own characterizations and what you found by reading the codebase
     yourself, and any other cross-cutting concerns spanning multiple
     items
   ```

   Embed only the scope description (from Step 1) and the two resolved paths, `<QUALITY_LIST_ROOT>` and `<TARGET_ROOT>`, in the prompt. **Do not embed item body text** — the subagent reads the item files itself.

   When dispatch happened (the skip path above didn't fire), start Step 3 immediately rather than waiting for the subagent to finish first — the two run in parallel. Step 4 does need the subagent's actual returned rows, not merely the fact that it was dispatched, so block on the subagent's return (together with Step 3's result) once you reach Step 4, even though Steps 2 and 3 themselves ran concurrently.

3. **Process the contextual-lane items in main context.** Read `quality-list/SKILL.md`'s Items index and select every item whose lane is `contextual`, including the contextual half of dual-lane items (e.g. `ported-code-attribution`'s undeclared-port signal — main handles this because it needs the conversation / research history the subagent doesn't have, independent of what Step 1's scope description happened to capture). These need the plan / intent / review history that only main context has, or actual command-execution planning against the working tree.

   Read only the contextual-lane item files — including the dual-lane item's own body, read here for its contextual half — not a purely mechanical-lane item's body; deciding mechanical-lane applicability is Step 2's job. For each selected contextual item, read its `quality-list/items/<slug>.md` body — plus every `lang-<lang>.md` addendum section for a language Step 0 identified as applicable, loaded here by Step 3 itself — before deciding its status; the body plus addenda define the applicability criterion. Process items one at a time, reading each body as you reach it.

   For each item, determine one of:

   - **△ active** (set up needed): this item will apply to the finished diff; record what to set up *now* so the audit will pass later. Output the concrete preflight action (test fixture variants to include, guard locations to plan, paired-artifact surfaces to update, probes to thread through, etc.).
   - **⊘ N/A**: the item's own N/A criterion already excludes the scope. State why.
   - **? unknown**: the body has been read, but applicability turns on a scope fact not yet settled (what the change will actually touch); record the scope check that would decide it.

4. **Merge results.** If dispatch happened, check the subagent's return for completeness before merging: no valid rows at all (a terminal failure, or no result), or fewer rows than the mechanical-lane item count the index's lane tags predict (a partial return, silently missing one or more items) — either is a failure, not a clean pass. Re-dispatch it once with the same prompt; if it fails again, halt and surface to the user rather than silently proceeding with the mechanical lane incomplete. Otherwise integrate the mechanical-lane rows — the subagent's returned rows, or, on Step 2's skip path, the directly-marked ⊘ N/A rows — with main-context's contextual-lane rows (Step 3) into a single table, one row per item in index order. For the dual-lane item, render one row from both half-results: △ active if either half reports active — record in the Setup action cell which half(s) triggered it, plus, if the other half is `?`, that half's scope check as an unresolved note so a per-half setup action isn't silently lost even once the row is active; ⊘ N/A only if both halves report N/A; otherwise (neither half is active, and at least one is `?`) render `?`, carrying forward every unresolved half's scope check into Step 5.

   If the subagent returned a discrepancy list (per Step 2's report format), triage it here: for each discrepancy between the scope description's characterization and what the subagent found in the codebase, correct the affected row's Setup action to match what the subagent actually found, or, if the scope description turns out to be right and the subagent's codebase read was mistaken, note that resolution instead. Don't let a returned discrepancy go unconsumed.

5. **Resolve every ? before declaring preflight done** — either promote to △ with a concrete setup action, or downgrade to ⊘ with a reason. Resolve both a row whose overall Status is `?`, and an otherwise-△-active dual-lane row still carrying an unresolved half-note per Step 4 (that note gets resolved too, so its setup action isn't dropped from the final report).

   For a mechanical-lane `?` (Step 3's own contextual `?`s are resolved directly in main context, same as before):

   - First check whether the missing piece is a scope fact Step 1's checklist should have captured but didn't. If the subagent's row already stated the resulting verdict for each answer (per Step 2's `? unknown` requirement), supply the missing fact and read off the matching verdict — no body read needed.
   - Otherwise — the subagent's row didn't state the branch outcomes, or the missing piece needs a codebase-dependent trace (a caller trace, a concept-first helper search) — re-dispatch. Reuse Step 2's prompt verbatim, substituting in the augmented scope description, with one change to the item-selection sentence: for an ordinary mechanical item, replace "Select every item whose lane is `mechanical`, including the mechanical half of any dual-lane item (an entry tagged `mechanical (+ contextual half)`, e.g. ported-code-attribution — handle only its declared-port signal; the undeclared-port signal is main context's job)." with "Process only `<slug>`, the item this scope check concerns."; for `ported-code-attribution` specifically, replace it instead with "Process only `ported-code-attribution`'s declared-port signal; the undeclared-port signal is main context's job.", preserving that carve-out rather than dropping it. Keep the "Read [this] item's `<QUALITY_LIST_ROOT>`/.../items/<slug>.md in full" instruction that follows intact, now referring to that one item. Never read the item's body directly in main context instead.
   - A setup action that itself names a command to run (e.g. `public-api-surface`'s `cargo public-api` baseline) is still a planning action here — state that the command needs to be run before implementation, don't run it now. The mechanical lane's "no command execution" premise governs deciding applicability, not the setup action's own content.

6. **Report the preflight table.** Hand the △ rows to the implementation step as setup actions.

## Preflight framing per item (quick reference)

These are how each `quality-list` item reads in preflight mode — a compressed mnemonic of the lens-shift from the item's audit question to a preflight setup action. A row is **not** the applicability authority and decides nothing: for each contextual-lane item below, Step 3 (not this list) reads the item's body (`quality-list/items/<slug>.md`) plus any applicable `lang-<lang>.md` addendum, and that — with the `quality-list/SKILL.md` index as the item set — decides whether an item applies. (Mechanical-lane items' applicability is decided the same way, by Step 2's subagent, on its own bodies — see the note below the list.) Because bodies are always read, a stale row cannot cause a wrong status decision or a dropped item; and its setup framing is the uniform lens-shift this skill applies to every listed item, re-derivable from the body. Keep rows concise; consult one for its setup framing once the body has marked the item active.

This list covers only the contextual-lane items (and the contextual half of the dual-lane item) that Step 3 processes directly in main context. Mechanical-lane items have no row here: Step 2's subagent never reads this file, so a mnemonic for it would have no consumer and would just be a manual-synchronization surface with no payoff — the subagent derives its setup-action framing independently, straight from each item's own body, every time.

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

Emit one row per item in the `quality-list/SKILL.md` Items index, in index order — the rows above illustrate the format and the reported status vocabulary (△ active / ⊘ N/A), not the full set. `? unknown` is a working state Step 5 always resolves to one of these two before this report is emitted; it never appears in the final table. The table merges the mechanical-lane rows (Step 2's subagent, or its skip path's direct N/As) with Step 3's contextual-lane rows, per Step 4. Hand the △ rows forward as the implementation setup.
