---
name: todo-check
description: Preflight sweep of quality-list items before or during implementation, framed as 'what to set up so done-check passes at the end'. Dual of done-check.
---

# Todo-Check

Forward-looking preflight against the current scope. Item definitions live in `quality-list`; this skill is the **runner**. Update `quality-list`, not this file, when adding or modifying items.

`done-check` asks: "Did the diff satisfy item N?" `todo-check` asks: "What does item N require us to set up so the diff will satisfy it?"

## Procedure

0. **Resolve the active rule set.**

   The base rule set lives in `quality-list/SKILL.md`. Language-specific addenda live alongside it as `quality-list/lang-<language>.md` and supplement the base rules with triggers, mitigation idioms, and mechanical detection patterns for the language. Items themselves stay language-neutral in the base file; addenda only realize them concretely.

   Detection order for the project language:

   1. Check the project's `CLAUDE.md` (or equivalent contributor / agent-guidance file) for a `Language:` declaration line (e.g., `Language: cpp`). If present, load `quality-list/lang-<value>.md`.
   2. Otherwise, auto-detect from file extensions present in the scope (or the work's likely-touched files): `.cpp` / `.cc` / `.cxx` / `.h` / `.hpp` / `.hh` → `cpp`; `.rs` → `rust`; `.py` → `python`; `.ts` / `.tsx` → `typescript`; `.go` → `go`; etc.
   3. Multi-language projects: load every matching `lang-*.md` (one per language present).

   If a detected language has no `lang-<lang>.md`, fall back to the base rules only. Missing addenda are not a concern — they just mean no curated language realizations exist yet.

   The active rule set = base items plus, for each item with content in the loaded addendum, that addendum's section. The preflight framing in Step 2 considers both.

1. **Identify the work scope.** Pull from the plan if one exists, otherwise from the current task description. Determine:

   - What files / modules will change
   - What public symbols, schemas, or contracts will move
   - What invariants the change introduces or modifies
   - Whether a research plan with `Inconclusive / Deferred items` exists (relevant to `discovery-surfacing`)

2. **Process every item in preflight mode.** Read `quality-list/SKILL.md`'s Items index to get the authoritative item set, and process every item in it. For each item, Read its `quality-list/items/<slug>.md` body — plus every applicable `lang-<lang>.md` addendum section (per Step 0) — **before** deciding its status; the body plus addenda define the applicability criterion and hold the item's full detail, and the active-vs-N/A verdict comes from applying that criterion to the change's scope. Process items one at a time, reading each body as you reach it. The per-item Preflight framing quick reference below is a compressed mnemonic, **not** an applicability authority: consult it for the setup framing once the body has decided the item applies — never to decide applicability itself. An index item with no row is handled from its body alone, which is read regardless.

   For each item, determine one of:

   - **△ active — set up needed**: this item will apply to the finished diff; record what to set up *now* so the audit will pass later. Output the concrete preflight action (test fixture variants to include, guard locations to plan, paired-artifact surfaces to update, probes to thread through, etc.).
   - **⊘ N/A**: the item's own N/A criterion already excludes the scope. State why.
   - **? unknown**: the body has been read, but applicability turns on a scope fact not yet settled (what the change will actually touch); record the scope check that would decide it.

3. Resolve every **?** before declaring preflight done — either promote to △ with a concrete setup action, or downgrade to ⊘ with a reason.

4. Report the preflight table. Hand the △ rows to the implementation step as setup actions.

## Preflight framing per item (quick reference)

These are how each `quality-list` item reads in preflight mode — a compressed mnemonic of the lens-shift from the item's audit question to a preflight setup action. A row is **not** the applicability authority and decides nothing: Step 2 reads each item's body (`quality-list/items/<slug>.md`) plus any applicable `lang-<lang>.md` addendum for every item, and that — with the `quality-list/SKILL.md` index as the item set — decides whether an item applies. Because Step 2 always reads the body, a stale row cannot cause a wrong status decision or a dropped item; and its setup framing is the uniform lens-shift this skill applies to every item (reframing the item's requirement as a setup action), re-derivable from the body. Keep rows concise; consult one for its setup framing once the body has marked the item active.

- **`invariant-derivation`** — Before patching, derive the full necessary-and-sufficient condition from first principles. List it in the plan.
- **`purpose-verification`** — Identify the input that exposes the purpose end-to-end. Plan to exercise it before declaring done.
- **`pattern-audit`** — Plan to re-derive any reused sibling pattern's correctness in the current context before relying on it.
- **`scope-discipline`** — Resolve to evaluate findings on their merits, not narrowed to the originating task.
- **`behavior-coverage`** — Design fixtures now with the smallest non-trivial parameters per axis, covering happy + error paths, via a generic helper for type-parametric semantics.
- **`implementation-guards`** — Plan `assert!` locations for new invariants, sibling-method consistency reviews, constructor validations, and validation ordering.
- **`impact-verification`** — Build the impact list now, before editing, and trace public-symbol callers if no formal list exists.
- **`test-execution`** — Plan which test commands will be run, and capture the pre-existing failure baseline before any edit.
- **`completion-hygiene`** — Plan which lint / format / type-check / build commands will be run. Note any debug artifacts to strip.
- **`architectural-boundary`** — Identify any new imports / dep edges / `pub` widenings the change will introduce; plan to check them against the project's boundary rules.
- **`escape-hatch-necessity`** — Plan to derive any workaround's necessity before using it, treating it as a last resort rather than a default.
- **`paired-artifact-drift`** — List now every textual surface a primary-identifier edit must propagate to, and plan the sweep before editing the primaries.
- **`docstring-drift`** — List the docstring / comment / README surfaces describing any behavior the change alters, and plan a cold-read re-verification of each against the new behavior, with an execution probe where the behavior becomes library-owned.
- **`discovery-surfacing`** — Extract any research plan's `Inconclusive` items into a watch list for the implementation phase.
- **`ported-code-attribution`** — Plan the attribution surface for any ported external implementation before it lands.
- **`signature-change-regression`** — Plan a mitigation now for any function-signature change.
- **`public-doc-durability`** — Plan the denylist sweep up front for any `README.md` / `docs/**/*.md` the change touches. Use `file-pubdoc` for fresh writes.
- **`public-api-surface`** — Plan the surface-diff baseline now (e.g. a `cargo public-api` snapshot) for any public-API-surface change, and a symmetry check across the public surfaces of parallel implementations.

## Output format

```
preflight: <task / unit description>

| Item                          | Status   | Setup action / N/A reason                              |
|-------------------------------|----------|--------------------------------------------------------|
| invariant-derivation          | △ active | derive condition for <invariant> from <constraint>     |
| behavior-coverage             | △ active | fixtures: 3-site MPS bulk variant, non-square 2×3 ...  |
| implementation-guards         | △ active | assert! at <site>; review siblings <a>, <b>            |
| paired-artifact-drift         | △ active | sweep: examples/foo.rs, README.md, doctests in <mod>   |
| discovery-surfacing           | △ active | watch: inconclusive[1] probe at <site>; branches X/Y   |
| scope-discipline              | ⊘ N/A    | no findings raised yet                                 |
| architectural-boundary        | ⊘ N/A    | no new imports / dep edges / pub widening              |
```

Hand the △ rows forward as the implementation setup.
