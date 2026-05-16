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

## Why this skill exists separately

The author of a body has just drafted it and is strongly primed to read what they *meant* rather than what they *wrote*. This is the same failure mode `done-check` Step 2 addresses by delegating literal-text items to a fresh-context subagent. A self-administered cold re-read in the author's own context recurrently passes drafts that contain the exact leak shapes `gh-body-conventions` enumerates — hard-wrapped paragraphs, local filesystem paths, private skill names, Phase / Step numbers, chat-tone scaffolding — because the author reads the intent, not the text.

Splitting the audit into a separate skill that

1. delegates mechanical items to a fresh-context subagent (no chat history, no draft motivation, no priming),
2. records each rule's result explicitly in a table the author can inspect, and
3. blocks the caller until any ⚠ is resolved or explicitly waived,

reduces author-blindspot misses to the cases that are genuinely contextual (the C-items below, which need project / chat awareness the subagent does not have).

## When to use

Invoke this skill before any GitHub issue / PR body (or in-review reply) is shown for approval or filed. A "Laundering pass" step in a caller skill resolves to running this skill. Direct user invocation is also supported — to audit an already-filed body (fetched with `gh issue view <N> --json body -q .body` or `gh pr view <N> --json body -q .body`).

Do not treat the cold re-read as a self-contained step in the caller — the explicit per-item record produced here is the audit artifact.

## Audit lanes

Two lanes, identical in spirit to `done-check`'s split:

- **mechanical (M-items)** — judgable from the literal body text plus the literal rule text. No chat / plan / project context needed. Delegated to a fresh-context subagent.
- **contextual (C-items)** — requires chat history, the plan, repo-specific state, or the surrounding work session. Stays in main context.

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
You are auditing a drafted GitHub <issue|pr> body against the
`gh-body-conventions` rule set. You have NO access to the
conversation history that produced this draft and MUST NOT
speculate about author intent. Judge purely from:

- the literal text of the body (provided below)
- the literal text of `gh-body-conventions` (provided below)
- the literal text of the mechanical items M1-M10 (provided below)

For each mechanical item, return one row:

- ✅ pass — with the detection that was run and its result
- ⚠ concern — with the specific line number(s) and the offending
  substring, quoted verbatim
- ⊘ N/A — using only the item's own N/A criterion as stated

Run each detection command literally on $BODY_FILE. Do not skip a
detection because a hit "looks intentional" — your job is to
surface the literal hit. Whether it is a true positive is decided
in the caller's context, not yours.

Report concisely (under 500 words):

| Item | Status | Evidence |
| ---- | ------ | -------- |
| M1   | ...    | ...      |
...
| M10  | ...    | ...      |
```

### Mechanical items

For each M-item, the subagent runs the listed detection and reports the result.

**M1. Hard-wrap pattern.** Within any paragraph (consecutive non-blank lines, excluding code fences, tables, lists, blockquotes, headings, frontmatter), if two or more lines end without sentence-terminating punctuation AND have widths clustered in a narrow band somewhere in [50, 85] columns, flag the paragraph as hard-wrapped.

The canonical hard-wrap signature: every non-last line of the paragraph is "about the same length, ending mid-clause". `awk 'NF{print length}' "$BODY_FILE"` plus reading the line endings makes this judgable mechanically. ⚠ lists the paragraph's first line and the column band.

**M2. Local filesystem paths.** `rg -nP '(^|[^A-Za-z0-9_])(/Users/|/home/[a-z][^/]*/|/scratch/|/work/|/tmp/|~/)' "$BODY_FILE"`. Any hit outside fenced code blocks → ⚠.

**M3. Private skill / workflow names.** Enumerate the current set of installed skill names with `ls {.,~}/.claude/skills 2>/dev/null | sort -u` (covers both repo-local and user-global installs). For each name in the resulting list, `rg -nF "<name>" "$BODY_FILE"`. Any literal hit outside fenced code blocks → ⚠.

The list is regenerated at audit time so added / renamed / removed skills are picked up automatically without manual updates to this item.

(These names are author-side workflow tools; an external reader cannot resolve them and they signal private surface bleed.)

**M4. Phase / Step numbering.** `rg -nP '\b(Phase|Step|フェーズ|ステップ)\s*[0-9]+(\.[0-9]+)?\b' "$BODY_FILE"`. Any hit → ⚠ unless the body declares itself an umbrella sub-issue (look for `umbrella` / `parent: #N` / `sub-issue of #N` style line near the top, case-insensitive). Umbrella sub-issues legitimately use Phase / Step numbering because the umbrella itself made that structure public.

**M5. Chat-tone scaffolding.** Two patterns:

1. Explicit chat references: `rg -niP '(as we discussed|as discussed in chat|following up (on|from) chat|前回(の|.)?(チャット|セッション)|先ほど(の|.)?(チャット|議論))' "$BODY_FILE"`. Any hit → ⚠.
2. Loose hedges that suggest chat origin: `ちなみに`, `たぶん`, `わからないけど`, `maybe`, `I think`, `not sure if`, `kinda`, `sort of`. Flag when not part of an evidenced argument (a sentence like "not sure if X holds at N > 100 because the constant factor in the bound becomes …" is fine; a bare "not sure if this is right" is ⚠).

**M6. Language consistency.** If target language is English: `rg -nP '[\p{Hiragana}\p{Katakana}\p{Han}]' "$BODY_FILE"` and flag any hit outside fenced code blocks → ⚠. If target language is Japanese: skip (mixed JP / EN is acceptable in JP bodies). Hits inside fenced code blocks are ⊘ N/A (code examples may legitimately contain JP identifiers / strings).

**M7. Unicode math characters in prose.** `rg -nP '[\x{0370}-\x{03FF}\x{2200}-\x{22FF}\x{2A00}-\x{2AFF}\x{2020}\x{2021}]' "$BODY_FILE"` outside fenced code spans / code blocks. Any hit in prose → ⚠ (rule: `gh-body-conventions` § Math — Unicode math in prose is the user's strongest formatting dislike; use `` $`\alpha`$ `` instead of `α`).

**M8. Heredoc-corrupted code spans.** `rg -nF '\`' "$BODY_FILE"` (literal backslash-backtick) and, in non-LaTeX contexts, `rg -nF '\$' "$BODY_FILE"`. These are corruption signatures from reflexive escaping inside single-quoted heredocs. Any hit → ⚠ (rule: `gh-body-conventions` § Authoring via shell heredoc). For draft bodies (pre-file) this is rare; for post-file audits fetched via `gh ... view --json body`, this is a common finding.

**M9. Unresolved placeholders.** `rg -niP '<(TODO|FIXME|owner|repo|placeholder|insert|fill|name|N)>' "$BODY_FILE"`. Any hit → ⚠.

**M10. Line numbers in issue body.** When artifact kind is `issue`: `rg -nP '\b[A-Za-z0-9_./-]+\.(rs|py|ts|tsx|js|jsx|jl|c|cpp|cc|cxx|h|hpp|md|toml|yaml|yml|json|sh|fish)\s*:\s*[0-9]+(\s*[:-]\s*[0-9]+)?\b' "$BODY_FILE"`. Any hit → ⚠ (issue bodies refer to default-branch HEAD implicitly; line numbers rot within hours of the next merge — `gh-body-conventions` § References § Line numbers). When artifact kind is `pr`: ⊘ N/A (PR is anchored to specific commits, so line references within this PR's diff do not rot).

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
| M8   | ⊘ N/A  | (pre-file draft; heredoc corruption shapes inapplicable)       |
| M9   | ✅     | no unresolved placeholders                                     |
| M10  | ⊘ N/A  | (PR body — line refs within own diff are permitted)            |
| C1   | ⚠      | line 18: "the original plan" — resolves only via chat          |
| C2   | ✅     | direct / evidenced tone throughout                             |
| C3   | ✅     | sections (Summary / Changes / Test plan) self-justify          |
| C4   | flag   | chat used "Phase 1.2" 3 turns ago — priming risk               |
```

If any ⚠ remains, fix before proceeding. State concretely what will change. Do not proceed until concerns are resolved or the user explicitly waives them with reasoning.

## What this skill does NOT do

- It does not draft the body — that's the caller (`file-issue` / `file-pullreq`).
- It does not file the issue / PR — that's the caller's responsibility.
- It does not maintain the rule set — `gh-body-conventions` is SSOT. If a new leak shape recurs in practice, update `gh-body-conventions` first, then add the corresponding M-item / C-item here.
