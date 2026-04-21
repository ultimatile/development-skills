---
name: copilot-review
description: Create a GitHub PR and get Copilot code review with automated polling. Use this skill whenever the user wants to create a PR with Copilot review, says things like "PRを作って", "create a PR", "Copilotにレビューしてもらって", "PR with review", or wants to submit changes for automated review. Also trigger when the user mentions "Copilot review" or wants to check PR review status.
---

# Copilot Review

Create a GitHub PR, request Copilot review, poll until it arrives, and triage the results.

## How it works

**Use `pr-with-copilot-review.sh` for the entire flow.** Do NOT create the PR separately with `gh pr create` and then try to poll — the script handles PR creation, Copilot review request (`--reviewer @copilot`), and polling in one shot.

### Normal mode: create PR + review + poll

```bash
${CLAUDE_SKILL_DIR}/scripts/pr-with-copilot-review.sh --title "fix: foo" --body "bar" --base main
```

All arguments are forwarded to `gh pr create --reviewer @copilot`. The script then polls until Copilot's review arrives, outputting the review body and inline comments to stdout.

### Re-review mode: after pushing fixes

After pushing fix commits to an existing PR, trigger a new Copilot review and wait:

```bash
${CLAUDE_SKILL_DIR}/scripts/pr-with-copilot-review.sh --re-review https://github.com/owner/repo/pull/123
```

This records the current review count, runs `gh pr edit --add-reviewer @copilot` to trigger a new review, then polls until a new review appears (ignoring previous ones).

### Poll-only mode: recovery for existing PRs

If the PR was already created and review already requested:

```bash
${CLAUDE_SKILL_DIR}/scripts/pr-with-copilot-review.sh --poll https://github.com/owner/repo/pull/123
```

This skips PR creation and review request, going straight to polling.

### Environment variables

- `COPILOT_POLL_INITIAL` — initial poll interval in seconds (default: 60)
- `COPILOT_POLL_MAX` — max poll interval (default: 300)
- `COPILOT_POLL_ATTEMPTS` — max attempts (default: 10)

## Triage the review

Copilot reviews see the diff and file contents but lack project-specific knowledge about design decisions, test coverage, or runtime verification.

For each finding:
1. **Cross-check** against what you already know from the current conversation — code you've read, tests you've run, decisions made with the user
2. **Classify** as actionable, false positive (with reasoning), or uncertain
3. **Present the triage** to the user — don't dump raw review output

## Respond to review

After triaging, reply to each inline comment individually using the review comment replies API:

```bash
# Get inline comment IDs
gh api repos/{owner}/{repo}/pulls/{number}/comments --jq '.[] | {id, path, line, body: (.body | .[0:80])}'

# Reply to each comment
gh api repos/{owner}/{repo}/pulls/{number}/comments/{comment_id}/replies -f body='...'
```

Each reply should be concise — state the classification (fixed, false positive, acknowledged) and the reasoning in 1-2 sentences.

## Prerequisites

- `gh` CLI >= 2.88.0 (for `--reviewer @copilot` support)
- Copilot code review enabled for the repository (via GitHub plan + org/repo settings)
- Alternative: configure automatic Copilot review via Repository Rulesets (Settings > Rules)

## Combined pipeline with codex-review

```
codex review loop (pre-PR, local)
    ↓ clean
${CLAUDE_SKILL_DIR}/scripts/pr-with-copilot-review.sh (creates PR + polls for review)
    ↓ review received
Triage + respond to each inline comment via gh api .../replies
    ↓ if fixes needed
Push fixes
    ↓
${CLAUDE_SKILL_DIR}/scripts/pr-with-copilot-review.sh --re-review <PR_URL>
    ↓ new review received
Triage + respond again
```
