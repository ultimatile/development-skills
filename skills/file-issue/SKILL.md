---
name: file-issue
description: Draft and file a GitHub issue following the user's conventions. Use this skill whenever the user wants to create, draft, or file a GitHub issue, or when an investigation or discussion needs to be captured as a tracked issue. Enforces formatting rules (semantic line breaks, LaTeX math, no local references, English by default, concise but complete) before invoking `gh issue create`.
---

# File Issue

Draft a GitHub issue body that follows the user's conventions, show the draft for approval, then file via `gh`.

## When to use

Whenever the user wants to convert an investigation, bug observation, or design idea into a tracked GitHub issue. Trigger on explicit requests ("file an issue", "issue化して") and also when the conversation naturally calls for capturing a discrete piece of work as an issue.

Skip this skill if the user is just discussing — only invoke when the intent is to actually create the issue.

## Conventions

These rules are non-negotiable defaults. Apply them unless the user overrides explicitly.

### Formatting

- **Semantic line breaks, not column wrapping.** Do NOT hard-wrap to 72/80 columns the way commit message bodies do. Break lines at sentence boundaries, clause boundaries, or paragraph boundaries — wherever the structure of the prose suggests. The reader uses a wide viewport; column-wrapped issue bodies read as random ragged text.
  - One sentence per line, OR
  - One clause per line for long sentences, OR
  - Plain paragraphs with blank-line separation.
- Pick whichever of the three above is most readable for the content; do not mix styles within one section.

### Math

- Use LaTeX notation for mathematical expressions, rendered with GitHub's `$...$` (inline) and `$$...$$` (display) math syntax.
- Plain text inside backticks is fine when the symbol must match a code identifier verbatim (e.g., `` `alpha_t` `` referring to a variable named `alpha_t` in the code).
- Do NOT write raw Unicode math characters (α, β, ⊗, ∑, ∇, †, etc.) in prose. Use `$\alpha$`, `$\otimes$`, `$\sum$`, `$\nabla$`, `$\dagger$` instead. Unicode-math-in-prose is the user's strongest formatting dislike.

### References

- Do NOT cite local file paths, line numbers, local notes, HPC cluster paths, or anything an external reader cannot open.
- If the substance of a local reference matters, inline its content (quote, paraphrase, or reproduce the relevant snippet) so the issue is self-contained.
- External references (arXiv, DOI, public repo URLs, public docs, other issues/PRs in the same or public repos) are fine.
- Cross-repo references to *private* repos are also off-limits — same reason.

### Language

- Default to English for the title and body.
- Use Japanese only when the user explicitly asks for it, or when the surrounding repo's existing issues are predominantly Japanese.

### Length

- Be concise but do not omit explanation. Say what is needed and stop.
- Aim for: problem statement, minimal reproduction or evidence, proposed direction (if any). Skip narrative scaffolding ("As we discussed...", "Following up on..."), restated context the reader can see from the repo, and exhaustive option enumeration when one option is clearly preferred.
- A typical issue is 5–25 lines of body. Longer is fine when warranted (e.g., a design proposal with alternatives) — but every paragraph should be earning its place.

### Exclusions

The body must NOT contain:
- Local filesystem paths (`/Users/...`, `~/...`, absolute paths).
- Line numbers from local files.
- HPC cluster names, hostnames, queue names, or scheduler-specific context that is irrelevant to the upstream reader.
- References to the user's private repos, skills, or workflow internals.
- Phase/step numbers from the working session ("Phase 2 of the umbrella", "Step 3 of the plan") unless the issue is *itself* an umbrella sub-issue where that structure is public.

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

### 3. Show for approval

Present the draft to the user verbatim before filing. Do not file without confirmation.

If the user requests changes, revise and re-show. Do not file partially — the next step runs only after explicit approval.

### 4. File

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

### 5. Report

After filing, show the user:
- The issue number and URL.
- Any follow-up actions (e.g., linking from a parent umbrella issue, mentioning in a PR).
