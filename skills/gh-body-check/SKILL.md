---
name: gh-body-check
description: >
  Per-item audit of a drafted GitHub issue / PR body against
  `gh-body-conventions`. Use this skill before show-for-approval on
  any drafted body, before applying delta edits to an existing body,
  or directly to audit an already-filed body. Delegates mechanical
  items to a fresh-context subagent so the author's blindspot for
  what their own draft literally says is neutralized. Returns
  ✅ / ⚠ / ⊘ N/A per item; any unresolved ⚠ blocks the caller.
---

# GH Body Check

Runner for `gh-body-conventions`. Mirrors the `done-check` ↔ `quality-list` relationship: the conventions file is SSOT for the rules; this file is the procedure that applies them, item by item, with each result recorded explicitly rather than collapsed into a "ran the cold re-read ✓" assertion.

## When to use

Before any GitHub issue / PR body (or in-review reply) is shown for approval or filed. Callers' "Laundering pass" resolves to this skill. Direct invocation is also supported — to audit an already-filed body (`gh issue view <N> --json body -q .body` or `gh pr view <N> --json body -q .body`).

Two audit lanes: **mechanical (M-items)** delegated to a fresh-context subagent (literal body + rule text only), and **contextual (C-items)** kept in main context (needs chat / plan / repo awareness). Author bias toward intent over literal text is what makes the subagent split load-bearing.

## Procedure

### 1. Prepare the body and target metadata

Write the body to a temp file the subagent can read:

```bash
BODY_FILE=$(mktemp -t gh-body-check-XXXXXX.md)
cat > "$BODY_FILE" <<'EOF'
<the drafted body, exactly as it will be filed>
EOF
```

Determine:

- **Artifact kind**: `issue` or `pr` (some items differ — e.g., line numbers are forbidden in issue bodies but permitted within a PR's own diff).
- **Target language**: `English`, `Japanese`, or `matches-repo` (in which case the caller resolves the repo's predominant language from existing artifacts before invoking this skill).

### 2. Mechanical audit (fresh-context subagent)

Use the `Agent` tool with `subagent_type: "general-purpose"`. The subagent must receive only:

- The path to `$BODY_FILE` (or the body text inlined into the prompt).
- The artifact kind and target language.
- The full text of `gh-body-conventions/SKILL.md`.
- The "Mechanical items" section below.

Do **not** pass the chat history, the user's prior messages, the plan, or any context about why the body is being filed. The fresh context is the point — the subagent reads the literal text.

Prompt shape:

```
You are auditing a drafted GitHub <issue|pr> body against
`gh-body-conventions`. You have NO access to the conversation
history. Judge purely from literal text: body, conventions, M1-M10.

For each M-item return one row:
- ✅ pass — detection ran, no hit
- ⚠ concern — line number(s) + offending substring verbatim
- ⊘ N/A — per the item's own N/A criterion

Run each detection literally. Do not skip a hit because it "looks
intentional" — true-positive classification is the caller's job.
Report under 500 words as a Markdown table.
```

### Mechanical items

For each M-item, the subagent runs the listed detection and reports the result.

**M1. Hard-wrap pattern.** Within any paragraph (consecutive non-blank lines, excluding code fences, tables, lists, blockquotes, headings, frontmatter), if two or more lines end without sentence-terminating punctuation AND have widths clustered in a narrow band somewhere in [50, 85] columns, flag the paragraph as hard-wrapped.

The canonical hard-wrap signature: every non-last line of the paragraph is "about the same length, ending mid-clause". `awk 'NF{print length}' "$BODY_FILE"` plus reading the line endings makes this judgable mechanically. ⚠ lists the paragraph's first line and the column band.

**M2. Local filesystem paths.** `rg -nP '(^|[^A-Za-z0-9_])(/Users/|/home/[a-z][^/]*/|/scratch/|/work/|/tmp/|~/)' "$BODY_FILE"`. Any hit outside fenced code blocks → ⚠.

**M3. Private skill / workflow names.** Enumerate installed skills with `ls {.,~}/.claude/skills 2>/dev/null | sort -u` (regenerated each run, so renames are picked up automatically). For each name, `rg -nF "<name>" "$BODY_FILE"`. Any literal hit outside fenced code blocks → ⚠. (Private workflow names don't resolve for external readers.)

**M4. Phase / Step numbering.** `rg -nP '\b(Phase|Step|フェーズ|ステップ)\s*[0-9]+(\.[0-9]+)?\b' "$BODY_FILE"`. Any hit → ⚠ unless the body declares itself an umbrella sub-issue (look for `umbrella` / `parent: #N` / `sub-issue of #N` style line near the top, case-insensitive). Umbrella sub-issues legitimately use Phase / Step numbering because the umbrella itself made that structure public.

**M5. Chat-tone scaffolding.** Two patterns:

1. Explicit chat references: `rg -niP '(as we discussed|as discussed in chat|following up (on|from) chat|前回(の|.)?(チャット|セッション)|先ほど(の|.)?(チャット|議論))' "$BODY_FILE"`. Any hit → ⚠.
2. Loose hedges that suggest chat origin: `ちなみに`, `たぶん`, `わからないけど`, `maybe`, `I think`, `not sure if`, `kinda`, `sort of`. Flag when not part of an evidenced argument (a sentence like "not sure if X holds at N > 100 because the constant factor in the bound becomes …" is fine; a bare "not sure if this is right" is ⚠).

**M6. Language consistency.** If target language is English: `rg -nP '[\p{Hiragana}\p{Katakana}\p{Han}]' "$BODY_FILE"` and flag any hit outside fenced code blocks → ⚠. If target language is Japanese: skip (mixed JP / EN is acceptable in JP bodies). Hits inside fenced code blocks are ⊘ N/A (code examples may legitimately contain JP identifiers / strings).

**M7. Unicode math characters in prose.** `rg -nP '[\x{0370}-\x{03FF}\x{2200}-\x{22FF}\x{2A00}-\x{2AFF}\x{2020}\x{2021}]' "$BODY_FILE"` outside fenced code spans / code blocks. Any hit in prose → ⚠ (rule: `gh-body-conventions` § Math — Unicode math in prose is the user's strongest formatting dislike; use `` $`\alpha`$ `` instead of `α`).

**M8. Unresolved placeholders.** `rg -niP '<(TODO|FIXME|owner|repo|placeholder|insert|fill|name|N)>' "$BODY_FILE"`. Any hit → ⚠.

**M9. Line numbers in issue body.** When artifact kind is `issue`: `rg -nP '\b[A-Za-z0-9_./-]+\.(rs|py|ts|tsx|js|jsx|jl|c|cpp|cc|cxx|h|hpp|md|toml|yaml|yml|json|sh|fish)\s*:\s*[0-9]+(\s*[:-]\s*[0-9]+)?\b' "$BODY_FILE"`. Any hit → ⚠ (issue bodies refer to default-branch HEAD implicitly; line numbers rot within hours of the next merge — `gh-body-conventions` § References § Line numbers). When artifact kind is `pr`: ⊘ N/A (PR is anchored to specific commits, so line references within this PR's diff do not rot).

**M10. Sub-clause line endings.** Dual of M1. M1 catches column-wrap (clustered widths in [50, 85], lines ending mid-clause); M10 catches over-applied "clause-per-line" breaks — any single line ending at a sub-clause boundary is ⚠ (width-agnostic, since a single mid-PP break is sufficient signal).

Forbidden terminal tokens:

- prepositions: `with` `by` `of` `in` `on` `at` `for` `to` `from` `via` `as` `into` `onto` `over` `under` `between` `through` `against` `about` `like` `than`
- coordinating conjunctions: `and` `or` `but` `nor`

Detection command (run on the rstripped body, scoped to non-fenced prose):

```bash
rg -nP '\b(with|by|of|in|on|at|for|to|from|via|as|into|onto|over|under|between|through|against|about|like|than|and|or|but|nor)\s*$' "$BODY_FILE"
```

For each hit outside fenced code blocks, list `L<n>: "...<offending end token>"` (rule: `gh-body-conventions` § Formatting — "Do NOT break below the clause level"). Commas are excluded (too many legitimate uses); comma-heavy over-fragmentation is caught by C2 / C3. Drop hits that fall inside fences, tables, or verbatim quotes.

### 3. Contextual audit (main context)

The mechanical lane catches known leak shapes; the contextual lane catches novel ones. Apply in the caller's (main) context — these C-items need awareness the subagent does not have.

**C1. References resolve from public state.** Every name, number, path, identifier, and term in the body must resolve from the target repo's README, code, prior public issues / PRs, or well-known external standards. Anything that resolves only via chat / private notes / the author's mental model → ⚠ with the offending phrase.

Public-resolvable examples: `#42` (existing issue in target repo, verifiable with `gh issue view 42`), `arxiv:2401.12345`, `RFC 8949`, `cargo-mutants`. Private-only examples: `the original plan`, `Phase 1.2 follow-up`, `as we discussed`, `the linalg refactor` (when no public `linalg-refactor` label / issue / branch exists), `note/.../main.typ`.

**C2. Tone / register.** Public tone is direct, or explicitly tentative with cited evidence. Hedges that came from chat-style uncertainty without evidenced reasoning → ⚠.

**C3. Structure self-justifies.** The body's section structure should justify itself from the work's own logic (problem / repro / proposal for issues; summary / changes / impact / test plan for PRs), not from the author's private workflow. Phrases like "the second half of my session", "after the implementation phase", "in the next chat" are structural leakage even when no Phase / Step number appears. (Numbered leaks are caught by M4; this item catches the un-numbered structural shape.)

**C4. Trigger flag — recent priming risk.** If the chat in the last few turns used private framing — internal Phase / Step numbers, project nicknames, JP clauses in EN context, private path references, "as we discussed" — record this as a priming risk indicator on the report. The main context is at elevated risk of having copied chat phrasing into the draft; re-read C1-C3 more carefully when this flag is set. This is an *advisory* indicator, not a blocking ⚠.

### 4. Merge results

Combine the subagent's M-row table and the main-context C-row table into a single report. For each ⚠ from the subagent, decide in main context:

- **True positive** — fix before proceeding.
- **False positive due to missing context** — record explicitly why (e.g., `the literal "Phase 2" appears inside a quoted external RFC reference, not as an internal milestone label`). False-positive classification is itself a triage step the user can challenge; do not silently override.

### 5. Gate decision

If any unresolved ⚠ remains, do NOT proceed to the caller's next step. Return the report to the caller; the caller must revise the draft and re-run `gh-body-check`. Iterate until no ⚠ remains, or each remaining ⚠ has an inline waiver with a one-line justification (e.g., `M3: "research" appears inside a code-block citing the user's own skill description, not as a private workflow reference`).

### 6. Output format

```
gh-body-check report — target: <issue|pr>, language: <English|Japanese|...>

| Item | Status | Evidence                                                       |
| ---- | ------ | -------------------------------------------------------------- |
| M1   | ⚠      | paragraph @ line 14 hard-wrapped at ~72 columns                |
| M2   | ✅     | rg pattern returned no hits                                    |
| M3   | ⚠      | line 22: "research-and-implement" — private workflow name |
| M4   | ⊘ N/A  | (no Phase / Step tokens present)                               |
| M5   | ✅     | rg pattern returned no hits                                    |
| M6   | ✅     | target English; no CJK characters outside code blocks          |
| M7   | ✅     | no Unicode math in prose                                       |
| M8   | ✅     | no unresolved placeholders                                     |
| M9   | ⊘ N/A  | (PR body — line refs within own diff are permitted)            |
| M10  | ⚠      | paragraph @ line 5: 6 consecutive sub-clause-fragment lines (ending on `with`, `by`, `,`) |
| C1   | ⚠      | line 18: "the original plan" — resolves only via chat          |
| C2   | ✅     | direct / evidenced tone throughout                             |
| C3   | ✅     | sections (Summary / Changes / Test plan) self-justify          |
| C4   | flag   | chat used "Phase 1.2" 3 turns ago — priming risk               |
```

If any ⚠ remains, fix before proceeding. State concretely what will change. Do not proceed until concerns are resolved or the user explicitly waives them with reasoning.

## What this skill does NOT do

Does not draft or file the body (caller's job). Does not maintain the rule set — `gh-body-conventions` is SSOT; update it first, then add the corresponding M-item / C-item here.
