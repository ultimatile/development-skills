---
name: todo-check
description: >
  Preflight (forward-looking) sweep of the universal quality items defined
  in `quality-list`, used before or during implementation to set up the
  work so the items will pass when `done-check` runs at the end. Use this
  skill when the user says "todo check", "preflight", "before I implement",
  or invokes it from `implement-el` between units. Dual of `done-check`:
  same item set, but framed as "what do I need to set up?" instead of
  "did the diff satisfy this?".
---

# Todo-Check

Forward-looking preflight against the current scope. Item definitions live in `quality-list`; this skill is the **runner**. Update `quality-list`, not this file, when adding or modifying items.

`done-check` asks: "Did the diff satisfy item N?" `todo-check` asks: "What does item N require us to set up so the diff will satisfy it?"

Both skills walk the same list. Both reference `quality-list`.

## When to use

- Immediately before implementation begins, against the plan / spec.
- Between units inside `execution-loop` or `implement-el` when the next unit changes the active item set (e.g., a unit introduces a new public API → items 7, 11 become active).
- Before adding or designing tests, when item 5 (behavior coverage) is the constraint to honor.

It is acceptable to invoke `todo-check` more than once during a task. `done-check` runs once at the end as the audit.

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
   - Whether a research plan with `Inconclusive / Deferred items` exists (relevant to item 12)

2. **Read `quality-list`** and process every item in **preflight mode**. For each item, determine one of:

   - **△ active — set up needed**: this item will apply to the finished diff; record what to set up *now* so the audit will pass later. Output the concrete preflight action (test fixture variants to include, guard locations to plan, paired-artifact surfaces to update, probes to thread through, etc.).
   - **⊘ N/A**: the item's own N/A criterion already excludes the scope. State why.
   - **? unknown**: cannot decide without more reading; record what would need to be checked to decide.

3. Resolve every **?** before declaring preflight done — either promote to △ with a concrete setup action, or downgrade to ⊘ with a reason.

4. Report the preflight table. Hand the △ rows to the implementation step as setup actions.

## Preflight framing per item (quick reference)

These are how each `quality-list` item reads in preflight mode. The authoritative rule is in `quality-list`; this is just the lens shift.

- **1. Invariant derivation** — Before patching, derive the full necessary-and-sufficient condition from first principles. List it in the plan.
- **2. Purpose verification** — Identify the input that exposes the purpose end-to-end. Plan to exercise it before declaring done.
- **3. Pattern audit** — If you intend to copy a pattern from a sibling, plan to re-derive its correctness in the current context before reusing it.
- **4. Scope discipline** — Resolve to evaluate findings on their merits, not narrowed to the originating task.
- **5. Behavior coverage** — Design fixtures with the smallest non-trivial parameters per axis. For each parameter, ask "is this the trivial case?" If so, plan a non-trivial variant. Plan happy + error path coverage; plan generic helpers for type-parametric semantics. For tensor-network code, plan ≥3 sites so a bulk tensor is exercised.
- **6. Implementation guards** — Plan `assert!` locations for new invariants, sibling-method consistency reviews, constructor validations.
- **7. Impact / caller verification** — Build the impact list now, before editing. Trace public-symbol callers if no formal list exists.
- **8. Test execution** — Plan which test commands will be run, and capture the pre-existing failure baseline before any edit.
- **9. Completion hygiene** — Plan which lint / format / type-check / build commands will be run. Note any debug artifacts to strip.
- **10. Architectural boundary integrity** — Identify any new imports / dep edges / `pub` widenings the change will introduce; plan to check them against the project's boundary rules.
- **11. Textual / paired-artifact drift sweep** — List every textual surface that will need updating: same-crate `rg` targets, parent module docstrings, `examples/`, `bench/`, doctests, `README.md`, `CLAUDE.md`, migrations / schemas, declared cross-repo paired artifacts. Plan the sweep before editing primary identifiers.
- **12. Discovery surfacing** — If a plan exists, extract its `Inconclusive` items into a watch list. During implementation, any unexpected fact must match a watch-list branch or trigger halt.
- **13. License compliance for ports** — If any unit's research surfaced an external implementation as a reference, plan the attribution surface (in-source comment block citing project / file / URL / copyright / license, or a top-level `THIRD_PARTY.md`) before the port lands.
- **14. Silent semantic regression on signature change** — If a unit changes the signature of a function whose call sites live outside its own translation unit (parameter removal / reorder / type substitution), plan one of: (a) a `= delete;` sentinel overload for the old signature shape, (b) a strong typedef over the affected parameter(s) so the implicit-conversion edge is structurally absent, or (c) an exhaustive call-site sweep across the project (including every preprocessor / build-config branch) verifying no old-form call compiles under the new signature. The lang addendum (`lang-<lang>.md`) lists the language's actual conversion semantics; plan against those.

## Output format

```
preflight: <task / unit description>

| #  | Item                              | Status     | Setup action / N/A reason                              |
|----|-----------------------------------|------------|--------------------------------------------------------|
| 1  | Invariant derivation              | △ active   | derive condition for <invariant> from <constraint>     |
| 5  | Behavior coverage                 | △ active   | fixtures: 3-site MPS bulk variant, non-square 2×3 ...  |
| 6  | Implementation guards             | △ active   | assert! at <site>; review siblings <a>, <b>            |
| 11 | Textual / paired-artifact drift   | △ active   | sweep: examples/foo.rs, README.md, doctests in <mod>   |
| 12 | Discovery surfacing               | △ active   | watch: inconclusive[1] probe at <site>; branches X/Y   |
| 4  | Scope discipline                  | ⊘ N/A      | no findings raised yet                                 |
| 10 | Architectural boundary            | ⊘ N/A      | no new imports / dep edges / pub widening              |
```

Hand the △ rows forward as the implementation setup. The same items will be re-checked by `done-check` at the end of the task.
