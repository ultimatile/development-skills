---
name: file-pullreq
description: Draft and file a GitHub PR using gh-body-conventions and the PR body skeleton, via the gh-post wrapper. Supports a gate mode that stops at user approval.
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
- **Linked issue.** Read the issue body and comments — especially the `research` plan (in the sub-issue body for umbrella-spawned leaves, or in a comment for single-scope issues), if the work passed through `/research-and-implement`. The plan is the source of truth for Changes / Impact / Test plan / Discovery contract status.
- **Whether the work went through `research`.** If yes, fold the plan's sections into the body skeleton. If no, derive the same content from the local diff and commits, and omit the Discovery contract status section (there is no contract to report against).

### 2. Draft

Produce a title and body following the conventions above and the skeleton below.

#### Body skeleton

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
 research-and-implement>

## Notes  (optional)

<derivations pointer (link to plan comment), risks, follow-ups>
```

The Phase 4a `## Plan-vs-actual delta` section is appended later by `review-pipeline`; do not pre-create an empty delta section here.

Section headings are optional for trivial PRs — a 5-line body covering Summary + Test plan often needs no headings.

### 3. Laundering pass — run `gh-body-check`

Run `gh-body-check` against the drafted body. The check runs a Unicode-math regex scan and a cold-reader subagent that judges whether every referent in the body resolves from the target repo's public state alone — the author has just drafted the text and is primed to read what they meant rather than what they wrote, which has repeatedly let private-context tokens slip past a self-administered cold re-read.

Pass artifact kind `pr`, the target repo, and the target language. The check returns a ✅ / ⚠ status. Mandatory before every `gh-post pr create` / `gh-post pr edit`. Any ⚠ blocks step 4; revise the draft and re-run until no unresolved ⚠ remains, or explicitly waive a finding with a one-line justification.

See `gh-body-check/SKILL.md` for the procedure.

### 4. Show for approval

Present the laundered draft to the user verbatim before filing. Do not file without confirmation.

If the user requests changes, revise and re-show. Do not file partially — the next step runs only after explicit approval.

### 5. File

Two modes, distinguished by the caller.

#### 5a. Standalone mode (default)

Used when invoked directly by the user, outside `review-pipeline`. Write the laundered body to a temp file, then invoke the wrapper:

```bash
gh-post pr create \
  --repo <owner>/<repo> \
  --base <base-branch> \
  --title "<title>" \
  --body-file /tmp/<descriptive-name>.md
```

`gh-post` funnels every body through stream input and re-runs the hardwrap validator before forwarding to `gh`, so always create the PR through `gh-post` rather than `gh pr create --body ...` directly. Add `--draft` if the user wants a draft PR; extra flags (`--label`, `--reviewer <login>`, etc.) are forwarded to `gh` verbatim.

Do not auto-add `@copilot` here — Copilot review is `copilot-review`'s responsibility (gate mode below).

#### 5b. Gate mode (review-pipeline Phase 2)

Used when invoked as a gate before `copilot-review` creates the PR. Stop after approval; do NOT run `gh pr create`. Output the approved title and body for the caller to pass into the `pr-with-copilot-review.sh` invocation.

Output format:

```
APPROVED TITLE:
<title>

APPROVED BODY (HEREDOC-ready):
<body>
```

The pipeline's Phase 2 step then writes the approved body to a temp file and runs:

```bash
cat > /tmp/<descriptive-name>.md <<'EOF'
<approved body>
EOF

${CLAUDE_SKILL_DIR}/../copilot-review/scripts/pr-with-copilot-review.sh \
  --base <base-branch> \
  --title "<approved title>" \
  --body-file /tmp/<descriptive-name>.md
```

The script routes PR creation through `gh-post pr create`, which rejects inline `--body <string>` / `-b` to keep every body through the wrapper's validator stack — `--body-file` (preferred) or `--body-stdin` are the only accepted body inputs.

### 6. Report

After filing in standalone mode, show the user:

- The PR number and URL.
- Any follow-up actions (linking from a parent umbrella issue, triggering Copilot review separately via `copilot-review`, etc.).

In gate mode, just confirm the approval and hand off to the pipeline.
