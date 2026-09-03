---
name: gh-body-check
description: Audit a drafted or filed GitHub issue / PR body against gh-body-conventions via a fresh-context subagent. Any unresolved ⚠ blocks the caller.
allowed-tools: Bash(*/gh-body-check/body-math-scan.sh:*)
---

# GH Body Check

Two checks: a mechanical math scan (Unicode-math glyphs, the GitHub-unsupported macro `\operatorname`, and inline math neutralized by an enclosing code span), and a cold-reader audit delegated to a fresh-context subagent.

## Why a cold-reader subagent

The author has just drafted the text. They read what they *meant*, not what the text *literally says*. A fresh-context subagent with no access to the chat history, the plan, or the author's notes, and told not to browse the repo, is the reader `gh-body-conventions` § Exclusions' followability requirement is written for; reachability is settled in step 4, where the repo is in reach.

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

Determine: artifact kind (`issue` / `pr`), target repo (e.g., `owner/repo`) and its default branch, target language (`English` / `Japanese` / `matches-repo`, per `gh-body-conventions` § Language), and for a PR body its head and the branch it merges into.

### 2. Math scan

```bash
${CLAUDE_SKILL_DIR}/body-math-scan.sh "$BODY_FILE"
```

Exit 0 = clean, 1 = hits found (printed as `line:match`), 2 = usage / environment error. It flags the raw Unicode math glyphs, the `\operatorname` macro, and inline math `` $`...`$ `` neutralized by an enclosing code span — all forbidden by `gh-body-conventions` § Math. For a Unicode-glyph or `\operatorname` hit: any hit → ⚠; a hit inside a fenced code block, an inline code span, or prose that merely names the construct → ⊘ N/A, judged by main-context inspection. A code-span-neutralized inline-math hit is NOT auto-dismissed by that inline-code-span exemption — the enclosing code span IS the defect — so judge intent in main context: math a copied display form silently neutralized → ⚠ (fix); a legitimate literal `` $`...`$ `` shown as code or data → ⊘ N/A with a one-line justification.

### 3. Cold-reader audit (fresh-context subagent)

Invoke `Agent` with `subagent_type: "general-purpose"`. Pass only the body, the target repo name, and the artifact kind. Do NOT pass chat history, the plan, the author's prior messages, or any context about why the body is being filed — the fresh context is the entire point.

Prompt template:

```
You are an external reader of <target-repo>. You know that repository
exists and what its name says, and you hold well-known external
standards (RFCs, language specs). You could open its README, its issues
and PRs, and its code — you have not, and you will not. You have
no access to chat history, private notes, private workflows, local
files, or the author's mental model.

Read the following <issue|PR> body and report two kinds of hit:
- a sentence that points at what a text you have not read says instead
  of stating it — name what you would have to open to follow it. A
  sentence that states the substance is not a hit, even where you
  cannot check it from here;
- a token naming something you cannot reach, or cannot tell whether you
  can reach, a placeholder left where a value belongs among them. You
  have opened nothing, so every path, issue or PR number, URL, and
  published identifier is one of these; a standard you hold, or that
  repository's own name, is not.

For each hit, return the phrase or line verbatim and which of the two
it is. A span that is both is one hit carrying both kinds.

Out of scope: formatting, grammar, math notation, line width,
sub-clause line breaks.

Do NOT browse the repo or run tools. Judge from the body text alone.

--- body ---
<body content>
--- end body ---
```

### 4. Merge and gate

Combine the math-scan hit (if any) and the cold-reader report into a single status. Judge each cold-reader ⚠ in main context against `gh-body-conventions` § Exclusions, and take the `finding-triage` SSOT's `actionable` / `false-positive` split from that judgment. An actionable hit takes the edit `finding-triage`'s response selection picks; where that is `fix-in-place` on a sentence that points at another text, the content is whichever of § Exclusions' two forms the claim at issue selects. A hit carrying both kinds is two findings here, one per kind, each taking its own disposition and fix.

Settle the second kind by checking that the referent is where an external reader, as § Exclusions defines one, would find it — not by reading the token — § Exclusions' exemption for a repo-relative path the body proposes to create applying first: a repo-relative path, any position it carries dropped, at the revision the body is about — for a PR body its head (the drafting checkout's `HEAD` until the PR is filed) or its base, present at either being enough, since a body names files the PR removes as well as ones it adds; for an issue body the default branch — an issue or PR number in the repository it names, the target repo for a bare `#N`, a published identifier at its resolver, a URL at itself. A token whose referent is there is a `false-positive`; one whose referent is not is `actionable`. A token of any other form — a bare name, a placeholder, a local path — is judged on § Exclusions' bar directly.

- **True positive** (`actionable`) — fix before proceeding.
- **False positive due to missing context** — record explicitly why (e.g., the token resolved, or it is a bare name the target repo holds). Where one rule disposes of several hits, record them together and name that rule once. Per `finding-triage`, false-positive classification is itself a triage step the user can challenge; do not silently override.

Any unresolved ⚠ blocks the caller's next step. Return the report; the caller revises the draft, re-discharges its evidence claims, and re-runs `gh-body-check`. Iterate until clean, or each remaining ⚠ has an inline waiver with a one-line justification.

## What this skill does NOT do

Does not draft or file the body (caller's job). Does not maintain the rule set (`gh-body-conventions` is SSOT — update it first, then add the corresponding check here if a new mechanical rule is needed). Does not discharge `gh-body-conventions` § Evidence claims: that rule compares the body against the drafting session's record of what ran, which is exactly the context this check's subagent is denied — the caller discharges it in main context before invoking this check. Does not check hard-wrap (delegated upstream to `gh-post`'s `detect_hardwrap`) or reference anchoring (whether a citation is pinned to a fixed revision as `gh-body-conventions` § References requires — the drafter's to check).
