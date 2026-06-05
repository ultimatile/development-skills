---
name: done-check
description: Single-pass audit of the current diff against quality-list items before declaring a task complete or requesting external review.
---

# Done-Check

Post-hoc audit against the current diff. Item definitions live in `quality-list`; this skill is the **runner**. Update `quality-list`, not this file, when adding or modifying items.

## Procedure

0. **Resolve the active rule set.** Base items live in `quality-list/SKILL.md`; language-specific addenda at `quality-list/lang-<language>.md` realize them concretely.

   Detect language from the project's `CLAUDE.md` `Language:` declaration; otherwise auto-detect from diff file extensions (`.rs` → rust, `.cpp`/`.cc`/`.cxx`/`.h`/`.hpp` → cpp, `.py` → python, `.ts`/`.tsx` → typescript, `.go` → go, etc.). Multi-language projects load every matching addendum. Missing addendum → base rules only for that language (not a concern). Pass both base + addendum into the Step 2 subagent prompt.

1. **Identify the diff under audit.** Cover all four sources so recently-added implementation files are not missed:

   ```bash
   git log --oneline @{upstream}..HEAD                       # committed
   git diff @{upstream}..HEAD                                # committed content
   git diff --cached                                         # staged
   git diff                                                  # unstaged
   git ls-files --others --exclude-standard                  # untracked paths
   ```

   Read the contents of any untracked file relevant to the audit (paths alone do not let you check anything).

2. **Spawn a fresh-context auditor for the mechanical / literal items.** Authors read intent; a fresh-context subagent reads literal text — removes the doc-vs-code drift blindspot.

   **Main context MUST NOT load the item bodies.** The subagent reads them in its own fresh context; main only composes the prompt (slug list + diff + repo path) and dispatches.

   Use the `Agent` tool with `subagent_type: "general-purpose"` and a prompt of the following shape:

   ```
   You are auditing a diff under the `quality-list` quality rules.
   You have NO access to the conversation history that produced this
   diff and MUST NOT speculate about author intent. Judge purely from:

   - the literal text of the diff (provided below)
   - the literal text of the relevant `quality-list` item files (read
     them yourself from the paths below)
   - the literal text of the codebase you can read with your tools

   Read each item file in full under <REPO>/skills/quality-list/items/:
   behavior-coverage.md, implementation-guards.md, impact-verification.md,
   architectural-boundary.md, paired-artifact-drift.md,
   ported-code-attribution.md, signature-change-regression.md,
   public-doc-durability.md, public-api-surface.md.

   Also load the language addendum at
   <REPO>/skills/quality-list/lang-<lang>.md if it exists for the
   detected project language (see Step 0 of done-check for the
   detection rule).

   For each of these items return one of:

   - ✅ pass — with concrete evidence (file:line, identifier, or
     literal-text match) that the rule is satisfied
   - ⚠ concern — with the specific diff location and what the
     literal text says that violates the rule
   - ⊘ N/A — using only the item's own N/A criterion as stated

   Pay particular attention to `paired-artifact-drift`'s "new-comment
   claim sweep" and "cold-read pass" sub-rules: extract every numeric
   literal, identifier, and property claim from new / modified
   comments, and verify each against the code. Do not assume an
   inconsistency was "intended" — if the literal text says one thing
   and the code does another, that is a ⚠.

   For `ported-code-attribution`, grep the diff for textual signals —
   "ported from", "derived from", "based on", "adapted from", "from
   $project", and any external project name in new comments — and
   verify that any such signal is matched by an attribution comment
   naming source URL, upstream copyright, and license. If a NOTICE /
   THIRD_PARTY-style file is added or modified, follow the upstream
   URL it cites and confirm the upstream actually has the file the
   derivative claims to mirror.

   Report concisely (under 600 words):
   - one row per item with Result + Evidence + Note
   - a final list of any cross-cutting concerns spanning multiple
     items
   ```

   Embed only the diff (committed + staged + unstaged) and the resolved `<REPO>` absolute path in the prompt. **Do not embed item body text** — the subagent reads the item files itself, keeping the main context free of the rule text.

   The subagent runs in parallel with main-context steps 3 below; do not block waiting for it unless step 4 requires the result.

3. **Audit the contextual items in main context.** These need information the subagent does not have:

   - `invariant-derivation`, `purpose-verification`, `scope-discipline`, `discovery-surfacing` — need plan / intent / review history
   - `test-execution`, `completion-hygiene` — need actual command execution against the working tree
   - `pattern-audit` — needs awareness of which patterns were consciously copied vs independently reinvented

   For each, `Read` only the corresponding `quality-list/items/<slug>.md` file — do not load the full index or the mechanical-lane items. The seven contextual-lane reads together are far smaller than the legacy single-file load.

   `ported-code-attribution` is dual-lane: the subagent handles the *declared* case (literal grep for "ported from" / "derived from" / external project names → verify attribution); main context handles the *undeclared* case where the conversation history shows research surfaced an external implementation that the diff structurally mirrors but no comment names. If research identified an upstream reference and the diff looks like it followed it, demand attribution even if no comment marks the port. Read `items/ported-code-attribution.md` for both halves.

   Mark each as **✅ pass**, **⚠ concern**, or **⊘ N/A** with evidence as in step 4 below.

4. **Merge results.** When the subagent (step 2) returns, integrate its mechanical-lane rows with main-context's contextual-lane rows into a single table (one row per item, dual-lane items rendered once with both half-results merged). For each ⚠ from the subagent, decide:

   - **True positive** — fix before proceeding (same as a main-context ⚠).
   - **False positive due to missing context** — note explicitly why (e.g., "user explicitly approved the boundary deferral in conversation"); the subagent's literal interpretation is wrong because it lacked context, but this should be rare and worth paper-trailing. Do NOT silently override — false-positive classification is itself a triage step that the user can challenge.

   Each result is ✅ / ⚠ / ⊘ N/A (definitions per Step 2's prompt). Evidence cell records the basis (command run, manual check, `file:line`, or `not run: <reason>`).

5. If any ⚠ remains, fix before proceeding. State concretely what will change. Do not proceed until concerns are resolved or the user explicitly waives them with reasoning.

6. Report the audit table.

**When to skip the subagent (step 2).** Pure renames, formatting-only changes, or file moves with no content change — the subagent step is wasted overhead. Any prose / comment / docstring / log / error string add or modify → run the subagent.

## Output format

```
self-audit: <commit-range or "uncommitted">

| Item                          | Result | Evidence                                | Note                                           |
|-------------------------------|--------|-----------------------------------------|------------------------------------------------|
| invariant-derivation          | ⚠      | read: src/foo.rs:42                     | <what's wrong / what to fix>                   |
| purpose-verification          | ✅     | manual: ran example with input X        |                                                |
| pattern-audit                 | ✅     | re-derived f32 path; sibling f64 ok     |                                                |
| scope-discipline              | ⊘ N/A  |                                         | no findings dismissed                          |
| behavior-coverage             | ✅     | cargo test (incl. error_path tests)     |                                                |
| implementation-guards         | ⚠      | read: src/foo.rs:120                    | new invariant only commented, no assert        |
| impact-verification           | ⊘ N/A  |                                         | no public symbol changed                       |
| test-execution                | ✅     | cargo test: 84 passed, 0 failed         |                                                |
| completion-hygiene            | ✅     | cargo clippy clean, cargo fmt --check   |                                                |
| architectural-boundary        | ⊘ N/A  |                                         | no new imports / dep edges / pub widening      |
| paired-artifact-drift         | ✅     | rg <old-name>; parent //! re-read       |                                                |
| discovery-surfacing           | ⊘ N/A  |                                         | no plan exists                                 |
| ported-code-attribution       | ⊘ N/A  |                                         | no external code ported                        |
| signature-change-regression   | ⊘ N/A  |                                         | no signature change to public APIs             |
| public-doc-durability         | ✅     | rg local-paths / version literals in MD | README / docs/ scrub against authoritative srcs|
| public-api-surface            | ⊘ N/A  |                                         | no public API change, no parallel siblings     |
```

Item slugs and order must follow the index in `quality-list/SKILL.md` exactly. The table is generated from the list, not maintained independently.
