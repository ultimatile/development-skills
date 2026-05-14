---
name: file-issue
description: Draft and file a GitHub issue following the user's conventions. Use this skill whenever the user wants to create, draft, or file a GitHub issue, or when an investigation or discussion needs to be captured as a tracked issue. Enforces formatting rules (semantic line breaks, GitHub/LaTeX-safe math, no local references, English by default, concise but complete) before invoking `gh issue create`.
---

# File Issue

Draft a GitHub issue body that follows the user's conventions, show the draft for approval, then file via `gh`.

## When to use

Whenever the user wants to convert an investigation, bug observation, or design idea into a tracked GitHub issue. Trigger on explicit requests ("file an issue", "issue化して") and also when the conversation naturally calls for capturing a discrete piece of work as an issue.

Skip this skill if the user is just discussing — only invoke when the intent is to actually create the issue.

## Conventions

Apply the rules in `gh-body-conventions` to the title and body. The two issue-specific points to reinforce:

- **Semantic line breaks, not column wrapping.** Most-violated rule on issue bodies — do not hard-wrap at 72/80 the way commit bodies do.
- **Line numbers are forbidden in the issue body.** Issue bodies refer to the default branch's `HEAD` implicitly, which moves; cited line numbers go stale. Inline a code snippet instead. (PR bodies, governed by `file-pullreq`, are different — they are anchored to specific commits, so line refs there do not rot.)

### Length

A typical issue body is 5–25 lines. Longer is fine when warranted (e.g., a design proposal with alternatives), but every paragraph should earn its place. Aim for: problem statement, minimal reproduction or evidence, proposed direction (if any).

## Procedure

### 1. Confirm scope

Before drafting, identify:
- Target repo (`gh repo view` if unclear).
- Whether this is a bug, feature, design discussion, or umbrella sub-issue — the body shape differs.
- Any related issues/PRs to link.

### 2. Draft

Produce a title and body following the conventions above.

**Title** — a single descriptive line under ~70 characters. No leading type prefix unless the repo's existing issues use one.

**Body** — typical structure (adapt as needed):

```
<one-paragraph problem statement using semantic line breaks>

## Context  (optional — only if the reader needs background not visible from the repo)

<minimal context>

## Reproduction / Evidence  (for bugs)

<commands, inputs, observed vs expected, with code blocks where appropriate>

## Proposal  (optional)

<direction, not full implementation>
```

Section headings are optional for short issues — a 5-line body often needs no headings at all.

### 3. Laundering pass — run `gh-body-check`

Run `gh-body-check` against the drafted body. The check delegates mechanical items (hard-wrap, local-path patterns, private skill names, Phase / Step numbering, JP clauses in English bodies, chat-tone scaffolding, Unicode math in prose, unresolved placeholders, line numbers in issue bodies) to a fresh-context subagent — the author has just drafted the text and is primed to read what they meant rather than what they wrote, which has repeatedly let documented exclusions slip past a self-administered cold re-read.

Pass artifact kind `issue` and the target language. The check returns a per-item ✅ / ⚠ / ⊘ N/A table. Mandatory before every `gh issue create` / `gh issue comment`. Any ⚠ blocks step 4; revise the draft and re-run until no unresolved ⚠ remains, or explicitly waive a finding with a one-line justification.

See `gh-body-check/SKILL.md` for the full item list, detection patterns, and the contextual-axis cold re-read covering novel leak shapes.

### 4. Show for approval

Present the laundered draft to the user verbatim before filing. Do not file without confirmation.

If the user requests changes, revise and re-show. Do not file partially — the next step runs only after explicit approval.

### 5. File

```bash
gh issue create \
  --repo <owner>/<repo> \
  --title "<title>" \
  --body "$(cat <<'EOF'
<body>
EOF
)"
```

Always use HEREDOC for the body to preserve formatting and avoid shell escaping issues.

If labels or assignees are appropriate and the user mentioned them, add `--label` / `--assignee` flags. Do not invent labels — only use ones the user named or that are obviously required by the repo's template.

### 6. Report

After filing, show the user:
- The issue number and URL.
- Any follow-up actions (e.g., linking from a parent umbrella issue, mentioning in a PR).
