---
name: gh-body-check
description: Audit a drafted or filed GitHub issue / PR body against gh-body-conventions via a fresh-context subagent. Any unresolved ⚠ blocks the caller.
allowed-tools: Bash(*/gh-body-check/unicode-math-scan.sh:*)
---

# GH Body Check

Two checks: a mechanical Unicode-math scan (one rg invocation), and a cold-reader audit delegated to a fresh-context subagent. `gh-body-conventions` is SSOT for the rules; this file is the procedure.

## When to use

Before any GitHub issue / PR body (or in-review reply) is shown for approval or filed. Callers' "Laundering pass" resolves to this skill. Direct invocation is also supported — to audit an already-filed body (`gh issue view <N> --json body -q .body` or `gh pr view <N> --json body -q .body`).

## Why a cold-reader subagent

The author has just drafted the text. They read what they *meant*, not what the text *literally says*. A fresh-context subagent with no access to the chat history, the plan, or the author's notes is the cleanest implementation of the operative definition of leakage: *a token whose referent cannot be resolved from the target repo's public state.* Whatever the cold reader cannot resolve is, by definition, leakage.

Hard-wrap and sub-clause line endings are out of scope here: `gh-post`'s `detect_hardwrap` rejects hard-wrap at submission, and GitHub's renderer (plus `gh-post`'s auto-format) collapses soft breaks to spaces, so source-side sub-clause shape has no wire or render consequence.

## Procedure

### 1. Prepare the body and target metadata

Write the body to a temp file:

```bash
BODY_FILE=$(mktemp -t gh-body-check-XXXXXX.md)
cat > "$BODY_FILE" <<'EOF'
<the drafted body, exactly as it will be filed>
EOF
```

Determine: artifact kind (`issue` / `pr`), target repo (e.g., `owner/repo` — the cold reader needs this to reason about what counts as "public" for that repo), target language (`English` / `Japanese` / `matches-repo`).

### 2. Unicode math scan

```bash
${CLAUDE_SKILL_DIR}/unicode-math-scan.sh "$BODY_FILE"
```

Exit 0 = clean, 1 = hits found (printed as `line:match`), 2 = usage / environment error. The script wraps the rg regex for the Greek block, the two Mathematical Operators blocks, the Superscripts-and-Subscripts block, the Latin-1 math signs (`±`, `×`, `÷`) and superscripts (`¹`, `²`, `³`), and dagger / double-dagger — `gh-body-conventions` § Math forbids these in prose. Any hit in prose → ⚠ (rule: Unicode math in prose is the user's strongest formatting dislike; use `` $`\alpha`$ `` instead of `α`). Hits inside fenced code blocks (rare — Greek-named identifiers etc.) → ⊘ N/A, judged by main-context inspection of each hit.

### 3. Cold-reader audit (fresh-context subagent)

Invoke `Agent` with `subagent_type: "general-purpose"`. Pass only the body, the target repo name, and the artifact kind. Do NOT pass chat history, the plan, the author's prior messages, or any context about why the body is being filed — the fresh context is the entire point.

Prompt template:

```
You are an external reader of <target-repo>. Your public knowledge
consists of: this repository's README, public issues and PRs,
public code, and well-known external standards (RFCs, arXiv,
language specs). You have no access to: chat history, private
notes, private workflows, local files, or the author's mental
model.

Read the following <issue|PR> body and list every place where a
referent cannot be resolved from that public knowledge. For each
hit, return:
- Quote (the phrase or line, verbatim).
- Why it cannot be resolved from public knowledge.
- Suggested public source to check (if any).

Out of scope: formatting, grammar, math notation, line width,
sub-clause line breaks. Focus purely on "can an external reader
resolve every referent here?"

Do NOT browse the repo or run tools. Judge from the body text alone.

--- body ---
<body content>
--- end body ---
```

Common leak shapes the cold reader will surface (illustrative, not exhaustive — the operative definition above is what governs):

- Local filesystem paths (`/Users/...`, `~/foo`).
- Private skill / workflow names (`/research-and-implement`, etc.).
- Phase / Step numbering from the working session, unless the artifact is itself a sub-issue / sub-PR of a public umbrella.
- Chat-tone scaffolding ("as we discussed", "following up on chat").
- Unresolved placeholders (`<TODO>`, `<owner>`).
- Private project nicknames or unsanctioned shorthand.
- Inline Japanese clauses in an otherwise-English body.

### 4. Merge and gate

Combine the rg hit (if any) and the cold-reader report into a single status. For each cold-reader ⚠, judge in main context — the `finding-triage` SSOT's `actionable` / `false-positive` split applied to a cold-reader concern:

- **True positive** (`actionable`) — fix before proceeding.
- **False positive due to missing context** — record explicitly why (e.g., the cold reader did not recognize a public external reference, or the term is a standard library identifier the reader was unfamiliar with). Per `finding-triage`, false-positive classification is itself a triage step the user can challenge; do not silently override.

Any unresolved ⚠ blocks the caller's next step. Return the report; the caller revises the draft and re-runs `gh-body-check`. Iterate until clean, or each remaining ⚠ has an inline waiver with a one-line justification.

## What this skill does NOT do

Does not draft or file the body (caller's job). Does not maintain the rule set (`gh-body-conventions` is SSOT — update it first, then add the corresponding check here if a new mechanical rule is needed). Does not check hard-wrap (delegated upstream to `gh-post`'s `detect_hardwrap`) or reference anchoring (raw line numbers, broken issue refs — a separate concern that may live in a future reference-validity tool).
