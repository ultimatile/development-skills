---
name: done-check
description: Single-pass audit of the current diff against the applicable quality rule sets before declaring a task complete or requesting external review.
---

# Done-Check

Post-hoc audit against the current diff. This skill is the **runner**; item definitions live in the rule-set SSOTs it applies — `quality-list` for universal code quality, and `authoritative-text-rules` for text the agent executes as instructions. Update the owning SSOT, not this file, when adding or modifying items.

## Procedure

0. **Resolve the active rule sets.** Resolve two absolute paths first, and use them everywhere below: `<RULES_ROOT>`, the repo / package root holding the `skills/quality-list/` and `skills/authoritative-text-rules/` directories, and `<TARGET_ROOT>`, the project under audit (cwd). They coincide only when the rule sets are vendored inside the target; in a marketplace or symlinked install they differ, and every read of a rule file — main context's as much as a subagent's — resolves against `<RULES_ROOT>`.

   `quality-list` always applies: its base items live in `<RULES_ROOT>/skills/quality-list/SKILL.md`, and language-specific addenda at `<RULES_ROOT>/skills/quality-list/lang-<language>.md` realize them concretely. `authoritative-text-rules` applies conditionally, by the firing rule in Step 2.

   Detect language from the project's `CLAUDE.md` `Language:` declaration; otherwise auto-detect from diff file extensions (`.rs` → rust, `.cpp`/`.cc`/`.cxx`/`.h`/`.hpp` → cpp, `.py` → python, `.ts`/`.tsx` → typescript, `.go` → go, etc.). Multi-language projects detect every present language; each matching addendum applies. Missing addendum → base rules only for that language (not a concern). Step 0 only **detects** the language(s); it routes nothing. Each consumer that applies `quality-list` — the Step 2 mechanical subagent and the Step 3 contextual pass — loads every matching addendum file itself.

1. **Identify the diff under audit.** Cover all four sources so recently-added implementation files are not missed:

   ```bash
   git log --oneline @{upstream}..HEAD                       # committed
   git diff @{upstream}..HEAD                                # committed content
   git diff --cached                                         # staged
   git diff                                                  # unstaged
   git ls-files --others --exclude-standard                  # untracked paths
   ```

   Read the contents of any untracked file relevant to the audit (paths alone do not let you check anything).

2. **Spawn the fresh-context auditors.** Authors read intent; a fresh-context subagent reads literal text — removes the doc-vs-code drift blindspot. One auditor always runs, for `quality-list`'s mechanical / literal items. A second runs conditionally, for `authoritative-text-rules`, per the firing rule at the end of this step.

   **Main context MUST NOT load a purely-mechanical `quality-list` item body, and MUST NOT load any `authoritative-text-rules` item body.** Each subagent reads its own SSOT's index and the bodies it needs in its own fresh context, deriving its item set from that index; main only composes the prompts (diff + resolved paths) and dispatches. Main reads the contextual-lane `quality-list` bodies it audits in Step 3, and may read either SSOT's index — that is how Step 3 selects contextual items and how Step 4 predicts the authoritative-text row set.

   Both prompts below carry the two absolute paths Step 0 resolved; a subagent needs both.

   **Auditor 1 — `quality-list` mechanical lane.** Always dispatched. Use the `Agent` tool with `subagent_type: "general-purpose"` and a prompt of the following shape:

   ```
   You are auditing a diff under the `quality-list` quality rules.
   You have NO access to the conversation history that produced this
   diff and MUST NOT speculate about author intent. Judge purely from:

   - the literal text of the diff (provided below)
   - the literal text of the relevant `quality-list` item files (read
     them yourself from the paths below)
   - the literal text of the codebase at <TARGET_ROOT> you can read
     with your tools

   First read <RULES_ROOT>/skills/quality-list/SKILL.md and consult its
   Items index. Select every item whose lane is `mechanical`,
   including the mechanical half of any dual-lane item (an entry
   tagged `mechanical (+ contextual half)`, e.g.
   ported-code-attribution). Read each selected item's
   <RULES_ROOT>/skills/quality-list/items/<slug>.md in full and audit
   it.

   Also load every language addendum at
   <RULES_ROOT>/skills/quality-list/lang-<lang>.md that exists for a
   detected project language — a multi-language diff has one per
   present language, and you must load them all (see Step 0 of
   done-check for the detection rule).

   Return one verdict per item, from the three defined in Step 4 of
   <RULES_ROOT>/skills/done-check/SKILL.md; read that step's verdict
   sentence, which states what backs each of the three.

   Pay particular attention to `paired-artifact-drift`'s "new-comment
   claim sweep" and "cold-read pass" sub-rules: extract every numeric
   literal, identifier, property claim, and behavioral guarantee
   (never-raises / always-returns / totality) from new / modified
   comments, and verify each against the code — for a guarantee, trace
   every exception or non-conforming-return source in the function
   body, not just one representative case. Do not assume an
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
   - one row per item, labelled with that item's slug exactly as the
     Items index spells it, carrying Result + Evidence + Note
   - a final list of any cross-cutting concerns spanning multiple
     items
   ```

   Embed only the diff and the two resolved absolute paths in the prompt. The diff is all four sources Step 1 identified — committed, staged, unstaged, and the contents of every relevant untracked file. **Do not embed item body text** — the subagent reads the item files itself, keeping the main context free of the rule text.

   **Firing rule for auditor 2.** Dispatch the authoritative-text auditor when any path in the diff could be text an agent executes as instructions — markdown paths are the usual case. **Dispatch when unsure.**

   The rule approximates because it has to: `authoritative-text-rules`' membership predicate is a property of a file's *content*, while a dispatch decision is available only over the diff's *paths*. No path-level test is exact, so the only real choice is which way it errs. It errs toward dispatching: a missed dispatch is an audit that silently did not happen, while a needless one costs one subagent that returns `⊘ N/A` rows. Deciding authoritatively which files qualify is that SSOT's Scope section, applied to file contents inside the subagent — main decides only whether to ask.

   **Auditor 2 — `authoritative-text-rules`.** Dispatched only when the firing rule fires. Same tool and `subagent_type`, with a prompt of the following shape:

   ```
   You are auditing a diff under the `authoritative-text-rules` rules.
   You have NO access to the conversation history that produced this
   diff and MUST NOT speculate about author intent. Judge purely from:

   - the literal text of the diff (provided below)
   - the literal text of the `authoritative-text-rules` item files
     (read them yourself from the paths below)
   - the literal text of the codebase at <TARGET_ROOT> you can read
     with your tools, including any file the audited text references
     as rule content

   First read <RULES_ROOT>/skills/authoritative-text-rules/SKILL.md.
   Consult its Items index; the items you must return a row for are
   exactly the ones listed there. Then apply its Scope section to
   every path in the diff and keep the files that qualify as
   authoritative text. If none qualify, return one ⊘ N/A row per
   indexed item and stop. Otherwise read each indexed item's
   <RULES_ROOT>/skills/authoritative-text-rules/items/<slug>.md in
   full before auditing it.

   Audit only the qualifying files. A diff that also carries code is
   audited for that code under a separate rule set you are not running
   here; do not report on it.

   Return one verdict per item, from the three defined in Step 4 of
   <RULES_ROOT>/skills/done-check/SKILL.md; read that step's verdict
   sentence, which states what backs each of the three. On a concern,
   add one thing that sentence does not ask for: the clause of the
   item you are applying, quoted. Whoever triages your rows cannot
   open these item bodies, so an unquoted rule leaves the concern
   unjudgeable.

   Each item's Sweep is a procedure, not a description: run it and
   report what it turned up. Where an item states a tie-break against
   a sibling item, apply it rather than reporting the same defect
   twice.

   Report concisely (under 600 words):
   - one row per item, labelled with that item's slug exactly as the
     Items index spells it, carrying Result + Evidence + Note
   - a final list of any cross-cutting concerns spanning multiple
     items
   ```

   Embed the same four-source diff and the same two resolved paths. **Do not embed item body text.**

   Each dispatched subagent runs in parallel with main-context step 3 below; do not block waiting on any of them unless step 4 requires the result.

3. **Audit the contextual items in main context.** Read `<RULES_ROOT>/skills/quality-list/SKILL.md`'s Items index and select every item whose lane is `contextual`, including the contextual half of dual-lane items (an index entry tagged `mechanical (+ contextual half)`, e.g. ported-code-attribution). These need information the subagent does not have — plan / intent / review history, or actual command execution against the working tree. The groupings below are non-exhaustive illustration; the index is the authoritative set:

   - `invariant-derivation`, `purpose-verification`, `scope-discipline`, `discovery-surfacing` — need plan / intent / review history
   - `escape-hatch-necessity` — needs design intent and codebase context to judge whether a direct fix could replace the workaround (a workaround's *presence* may be grep-visible, but its *necessity* is not literal-text-decidable)
   - `test-execution`, `completion-hygiene` — need actual command execution against the working tree
   - `pattern-audit` — needs awareness of which patterns were consciously copied vs independently reinvented
   - `docstring-drift` — needs the diff's behavior-change context plus an execution probe when the changed behavior is library-owned

   For each selected contextual item, `Read` the corresponding `<RULES_ROOT>/skills/quality-list/items/<slug>.md` file; if a detected language has an addendum section for that item (per Step 0 — e.g. `escape-hatch-necessity`'s Rust realization in `lang-<lang>.md` carries the concrete trigger / detection / mitigation guidance), read every such section too; this contextual pass self-loads every matching addendum itself, one per detected language (Step 0 only detects the languages). Which bodies this pass may open is Step 2's prohibition, stated there and not restated here.

   `ported-code-attribution` is dual-lane: the subagent handles the *declared* case (literal grep for "ported from" / "derived from" / external project names → verify attribution); main context handles the *undeclared* case where the conversation history shows research surfaced an external implementation that the diff structurally mirrors but no comment names. If research identified an upstream reference and the diff looks like it followed it, demand attribution even if no comment marks the port. Read `items/ported-code-attribution.md` for both halves.

   Mark each as **✅ pass**, **⚠ concern**, or **⊘ N/A** with evidence as in step 4 below.

4. **Merge results.** When each dispatched subagent (step 2) returns, integrate three row sources into a single table: auditor 1's `quality-list` mechanical-lane rows, main-context's contextual-lane rows, and — when auditor 2 was dispatched — its `authoritative-text-rules` rows. One row per item; dual-lane items render once with both half-results merged.

   **Coverage check on auditor 2's rows.** Only when it was dispatched. Read `<RULES_ROOT>/skills/authoritative-text-rules/SKILL.md`'s Items index for the predicted slug set — the index, never an item body, and never a slug list written into this file. A return that is exactly one row per predicted slug and no others passes. Any other return — a slug missing, duplicated, or outside the set — gets one re-dispatch of auditor 2 with its prompt unchanged; if the second return still does not match, carry the mismatch as a cross-cutting concern naming the offending slugs. It closes through step 5 like any other concern, so an incomplete rule set blocks completion without introducing an exit of its own.

   Auditor 1's rows carry no equivalent check; that asymmetry is a known gap in this runner, not a property of either rule set.

   For each ⚠ from either subagent, decide — this is the `finding-triage` SSOT's `actionable` / `false-positive` split applied to a fresh-context audit concern:

   - **True positive** (`actionable`) — fix before proceeding (same as a main-context ⚠).
   - **False positive due to missing context** — note explicitly why (e.g., "user explicitly approved the boundary deferral in conversation"); the subagent's literal interpretation is wrong because it lacked context, but this should be rare and worth paper-trailing. Per `finding-triage`, do NOT silently override — false-positive classification is itself a triage step that the user can challenge.

   The rule clause an authoritative-text row quotes is what main context judges the ⚠ against, and in step 5 what it fixes against — main does not open those item bodies at any point. A row that quotes no clause can be neither triaged nor fixed; leave it ⚠ with that noted, and close it through step 5 like any other.

   **The verdicts.** Every result, whatever its source, is exactly one of **✅ pass** (concrete evidence that the rule is satisfied), **⚠ concern** (the location and the literal text that violates the rule), or **⊘ N/A** (the item's own N/A criterion as stated). This sentence is the only definition; Step 2's prompts send subagents here rather than restating it. Evidence cell records the basis (command run, manual check, `file:line`, or `not run: <reason>`).

   **Cross-cutting concerns.** Each auditor also returns concerns spanning several items. They are not rows and do not enter the row domain, but step 5 binds them exactly as it binds a ⚠ row: each must be resolved, waived, or closed as a recorded deferral before proceeding. Report them under the table.

5. If any ⚠ remains, fix before proceeding. State concretely what will change. Do not proceed until each concern is resolved, explicitly waived by the user with reasoning, or closed as a recorded deferral per `finding-triage`'s `defer` — a follow-up issue filed with the user's approval. A deferral closes the concern's handling, not its verdict: the row stays ⚠ with the deferral recorded in its Note.

6. Report the audit table, followed by any cross-cutting concerns and their triage.

## Output format

```
self-audit: <commit-range or "uncommitted">

| Item                          | Result | Evidence                                | Note                                           |
|-------------------------------|--------|-----------------------------------------|------------------------------------------------|
| invariant-derivation          | ⚠      | read: src/foo.rs:42                     | <what's wrong / what to fix>                   |
| behavior-coverage             | ✅     | cargo test (incl. error_path tests)     |                                                |
| test-execution                | ✅     | cargo test: 84 passed, 0 failed         |                                                |
| docstring-drift               | ⊘ N/A  |                                         | diff is text-only; no behavior change          |
| ported-code-attribution       | ⊘ N/A  |                                         | no external code ported                        |
```

The table's row domain is every item in the `quality-list/SKILL.md` Items index, in index order, followed — when step 2's firing rule dispatched auditor 2 — by every item in the `authoritative-text-rules/SKILL.md` Items index, in that index's order. One row per item, and no rows outside the two domains. The rows above illustrate the format and the result vocabulary (✅ pass / ⚠ concern / ⊘ N/A), not the full set. Dual-lane items render once with both half-results merged. Each block is generated from its own index, never maintained as an independent list.
