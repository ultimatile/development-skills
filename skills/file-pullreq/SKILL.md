---
name: file-pullreq
description: Draft and file a GitHub pull request following the user's conventions. Use this skill whenever the user wants to create, draft, or file a GitHub PR, or when implementation work is ready for review. Enforces formatting rules via `gh-body-conventions` (semantic line breaks, GitHub/LaTeX-safe math, no local references, English by default) and the egel-aligned body skeleton (Summary / Changes / Impact / Test plan / Discovery contract status / Notes) before invoking `gh pr create`.
---

# File Pull Request

Draft a GitHub PR title and body that follow the user's conventions, show the draft for approval, then file via `gh` (or hand off to the review pipeline).

## When to use

Whenever the user wants to convert finished implementation work into a GitHub pull request. Trigger on explicit requests ("PRを作って", "create a PR", "file a PR") and also when called as a gate from `review-pipeline` Phase 2.

Skip this skill if the user is just asking for a diff summary — only invoke when the intent is to actually create or stage the PR.

## Conventions

Apply the rules in `gh-body-conventions` to both the title and body. The two PR-specific points to reinforce:

- **Semantic line breaks, not column wrapping.** This is the user's most-corrected formatting habit on PR bodies — commit-body-style hard wrapping renders as ragged text on GitHub's wide viewport.
- **Line numbers within this PR's own diff are permitted** (the PR is anchored to specific commits, so the references will not rot). Inline review comments are still preferred for line-specific feedback because they render next to the code.

### Length

A typical PR body is 10–40 lines pre-merge, plus the Phase 4a plan-vs-actual delta when added. Trivial fixes can be much shorter; major features or multi-file refactors can be longer. Every section in the skeleton below should earn its place — a one-line fix needs neither Impact nor Discovery contract sections.

### Title

A single descriptive line under ~70 characters. Use a conventional commit prefix (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, etc.) when the surrounding repo's existing PR titles use one; otherwise no prefix.

## Procedure

### 1. Confirm scope

Before drafting, identify:

- **Target repo and base branch.** `gh repo view` and `git symbolic-ref --short refs/remotes/origin/HEAD` if unclear.
- **Linked issue.** Read the issue body and comments — especially the `research-eg` plan comment, if the work passed through `/research-and-implement-egel`. The plan is the source of truth for Changes / Impact / Test plan / Discovery contract status.
- **Whether the work is egel-gated.** If yes, fold the plan's sections into the body skeleton. If no, derive the same content from the local diff and commits, and omit the Discovery contract status section (there is no contract to report against).

### 2. Draft

Produce a title and body following the conventions above and the skeleton below.

#### Body skeleton (egel-aligned)

```
## Summary

<one-paragraph problem statement and resolution, semantic line breaks>
<Closes #N> on its own line; <Depends on #M> if applicable.

## Changes

<compressed plan checklist: file path + one-line description per unit>
<for repos that prefer prose: a few sentences covering the same ground>

## Impact

<callers / public APIs affected; reference plan's Impact list compressed>
<omit when the change is genuinely local (single private function, etc.)>

## Test plan

<invariants verified, tests added/modified, cross-API coverage>
<contract tests added in review-pipeline Phase 3, if any>
<verification results: cargo test / pytest / etc. — pass/fail summary>

## Discovery contract status

<for each plan Inconclusive item: how it resolved during implementation>
<for each plan Deferred item: current state / follow-up issue link>
<all-clean → "All Inconclusive / Deferred items resolved per plan."
 (one line)>
<omit the section entirely if the work did not go through
 research-and-implement-egel>

## Notes  (optional)

<derivations pointer (link to plan comment), risks, follow-ups>
```

The Phase 4a `## Plan-vs-actual delta` section is appended later by `review-pipeline`; do not pre-create an empty delta section here.

Section headings are optional for trivial PRs — a 5-line body covering Summary + Test plan often needs no headings.

### 3. Laundering pass

Before showing the draft, run the cold re-read across the five axes (References / Tone / Language / Structure / Trigger-flag — see CLAUDE.md "Two-surface boundary and laundering before publishing"). This is mandatory before every `gh pr create` / `gh pr edit`. The mechanical exclusions in `gh-body-conventions` cover known leak shapes; the cold re-read catches novel ones.

Trigger flag: if the chat just used private framing (internal phase numbers, project nicknames, JP clauses, private path references, "as we discussed"), assume priming and re-read more carefully.

### 4. Show for approval

Present the laundered draft to the user verbatim before filing. Do not file without confirmation.

If the user requests changes, revise and re-show. Do not file partially — the next step runs only after explicit approval.

### 5. File

Two modes, distinguished by the caller.

#### 5a. Standalone mode (default)

Used when invoked directly by the user, outside `review-pipeline`.

```bash
gh pr create \
  --repo <owner>/<repo> \
  --base <base-branch> \
  --title "<title>" \
  --body "$(cat <<'EOF'
<body>
EOF
)"
```

Always use HEREDOC for the body to preserve formatting and avoid shell escaping issues. Add `--draft` if the user wants a draft PR.

If the user mentioned a reviewer, add `--reviewer <login>`. Do not auto-add `@copilot` here — Copilot review is `copilot-review`'s responsibility.

#### 5b. Gate mode (review-pipeline Phase 2)

Used when invoked as a gate before `copilot-review` creates the PR. Stop after approval; do NOT run `gh pr create`. Output the approved title and body for the caller to pass into the `pr-with-copilot-review.sh` invocation.

Output format:

```
APPROVED TITLE:
<title>

APPROVED BODY (HEREDOC-ready):
<body>
```

The pipeline's Phase 2 step then runs:

```bash
${CLAUDE_SKILL_DIR}/../copilot-review/scripts/pr-with-copilot-review.sh \
  --base <base-branch> \
  --title "<approved title>" \
  --body "$(cat <<'EOF'
<approved body>
EOF
)"
```

### 6. Report

After filing in standalone mode, show the user:

- The PR number and URL.
- Any follow-up actions (linking from a parent umbrella issue, triggering Copilot review separately via `copilot-review`, etc.).

In gate mode, just confirm the approval and hand off to the pipeline.
