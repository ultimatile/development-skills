---
name: done-check
description: >
  Walk through the universal quality items defined in `quality-list` and
  self-assess whether the current diff satisfies each, before declaring a
  task complete or before requesting external review. Use this skill when
  the user says "done check", "ready to commit", "are we done?", "done?",
  or asks to verify whether universal quality rules are being followed
  before claiming completion. Single-pass audit — runs once per invocation.
---

# Done-Check

Post-hoc audit against the current diff. Item definitions live in `quality-list`; this skill is the **runner**. Update `quality-list`, not this file, when adding or modifying items.

## Procedure

0. **Resolve the active rule set.**

   The base rule set lives in `quality-list/SKILL.md`. Language-specific addenda live alongside it as `quality-list/lang-<language>.md` and supplement the base rules with triggers, mitigation idioms, and mechanical detection patterns for the language. Items themselves stay language-neutral in the base file; addenda only realize them concretely.

   Detection order for the project language:

   1. Check the project's `CLAUDE.md` (or equivalent contributor / agent-guidance file) for a `Language:` declaration line (e.g., `Language: cpp`). If present, load `quality-list/lang-<value>.md`.
   2. Otherwise, auto-detect from file extensions in the diff: `.cpp` / `.cc` / `.cxx` / `.h` / `.hpp` / `.hh` → `cpp`; `.rs` → `rust`; `.py` → `python`; `.ts` / `.tsx` → `typescript`; `.go` → `go`; etc.
   3. Multi-language projects: load every matching `lang-*.md` (one per language present).

   If a detected language has no `lang-<lang>.md`, fall back to the base rules only for that language. Missing addenda are not a concern condition — they just mean the language has no curated realizations yet.

   The active rule set = base items (from `quality-list/SKILL.md`) plus, for each item that has language-specific content in the loaded addendum, that addendum's section for the item. Pass both into the subagent prompt in Step 2 below so the literal audit sees the language realization, not just the generic principle.

1. **Identify the diff under audit.** Cover all four sources so recently-added implementation files are not missed:

   ```bash
   git log --oneline @{upstream}..HEAD                       # committed
   git diff @{upstream}..HEAD                                # committed content
   git diff --cached                                         # staged
   git diff                                                  # unstaged
   git ls-files --others --exclude-standard                  # untracked paths
   ```

   Read the contents of any untracked file relevant to the audit (paths alone do not let you check anything).

2. **Spawn a fresh-context auditor for the mechanical / literal items (5, 6, 7, 10, 11).** The author of a diff reads what they meant their code and comments to say, not the literal text — the same blindspot that lets reviewers (Copilot, codex) routinely find doc-vs-code drift the author marked ✅. Delegating the literal audit to a subagent that has no access to the conversation history removes that blindspot.

   Use the `Agent` tool with `subagent_type: "general-purpose"` and a prompt of the following shape:

   ```
   You are auditing a diff under the `quality-list` quality rules.
   You have NO access to the conversation history that produced this
   diff and MUST NOT speculate about author intent. Judge purely from:

   - the literal text of the diff (provided below)
   - the literal text of the relevant `quality-list` items (provided
     below)
   - the literal text of the codebase you can read with your tools

   For each of the mechanical items below (`behavior-coverage`, `implementation-guards`, `impact-verification`, `architectural-boundary`, `paired-artifact-drift`, `ported-code-attribution`, `signature-change-regression`, `public-doc-durability`, `public-api-surface`), return one of:

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

   For `ported-code-attribution`, grep the diff
   for textual signals — "ported from", "derived from", "based on",
   "adapted from", "from $project", and any external project name in
   new comments — and verify that any such signal is matched by an
   attribution comment naming source URL, upstream copyright, and
   license. If a NOTICE / THIRD_PARTY-style file is added or
   modified, follow the upstream URL it cites and confirm the
   upstream actually has the file the derivative claims to mirror.

   Report concisely (under 600 words):
   - one row per mechanical item with Result + Evidence + Note
   - a final list of any cross-cutting concerns spanning multiple
     items
   ```

   Embed the actual diff (committed + staged + unstaged) and the full text of the mechanical-lane items from `quality-list/items/` directly in the prompt — the subagent has no access to the parent's context. The mechanical-lane slugs are: `behavior-coverage`, `implementation-guards`, `impact-verification`, `architectural-boundary`, `paired-artifact-drift`, `ported-code-attribution`, `signature-change-regression`, `public-doc-durability`, `public-api-surface`.

   The subagent runs in parallel with main-context steps 3 below; do not block waiting for it unless step 4 requires the result.

3. **Audit the contextual items (1, 2, 3, 4, 8, 9, 12) in main context.** These need information the subagent does not have:

   - `invariant-derivation`, `purpose-verification`, `scope-discipline`, `discovery-surfacing` — need plan / intent / review history
   - `test-execution`, `completion-hygiene` — need actual command execution against the working tree
   - `pattern-audit` — needs awareness of which patterns were consciously copied vs independently reinvented

   `ported-code-attribution` is dual-lane: the subagent handles the *declared* case (literal grep for "ported from" / "derived from" / external project names → verify attribution); main context handles the *undeclared* case where the conversation history shows research surfaced an external implementation that the diff structurally mirrors but no comment names. If research identified an upstream reference and the diff looks like it followed it, demand attribution even if no comment marks the port.

   Mark each as **✅ pass**, **⚠ concern**, or **⊘ N/A** with evidence as in step 4 below.

4. **Merge results.** When the subagent (step 2) returns, integrate its mechanical-lane rows with main-context's contextual-lane rows into a single table (one row per item, dual-lane items rendered once with both half-results merged). For each ⚠ from the subagent, decide:

   - **True positive** — fix before proceeding (same as a main-context ⚠).
   - **False positive due to missing context** — note explicitly why (e.g., "user explicitly approved the boundary deferral in conversation"); the subagent's literal interpretation is wrong because it lacked context, but this should be rare and worth paper-trailing. Do NOT silently override — false-positive classification is itself a triage step that the user can challenge.

   Each result is **✅ pass**, **⚠ concern**, or **⊘ N/A**:

   - **✅ pass** — confidently satisfied; the **Evidence** cell records what makes you confident (a command run, a manual check, a `file:line` read, or `not run: <reason>`)
   - **⚠ concern** — cite the diff location and what to fix
   - **⊘ N/A** — state why the rule does not apply (using the item's own N/A criterion)

5. If any **⚠** remains, fix before proceeding. State concretely what will change. Do not proceed until concerns are resolved or the user explicitly waives them with reasoning.

6. Report the audit table.

**When to skip the subagent (step 2).** For purely mechanical changes where literal-text drift is structurally impossible — pure rename across files, formatting only, file move with no content change — the subagent step is wasted overhead. The skip threshold is narrow: if the diff adds or modifies any prose / comment / docstring / log message / error string, run the subagent.

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

Item slugs and order must follow the index in `quality-list/SKILL.md` exactly. If the list grows or shrinks, update the table accordingly — the table is generated from the list, not maintained independently.

If any ⚠ remains, fix before proceeding. State concretely what will change. Do not proceed until concerns are resolved or the user explicitly waives them with reasoning.
