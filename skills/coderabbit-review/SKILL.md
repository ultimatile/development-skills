---
name: coderabbit-review
description: Create a GitHub PR and poll until the auto-triggered CodeRabbit review arrives.
allowed-tools: Bash(*/coderabbit-review/scripts/pr-with-coderabbit-review.sh:*), Bash(*/coderabbit-review/scripts/list-pr-threads.sh:*)
---

# CodeRabbit Review

Create a GitHub PR, wait for CodeRabbit's automatic review, and triage the results.

## How it works

CodeRabbit is app-driven: once the GitHub app is installed on the repository, it reviews every PR on open and re-reviews incrementally on every push. There is no reviewer-request step.

**The completion signal is the `CodeRabbit` commit status, not the review object.** CodeRabbit reports the review lifecycle as a commit status on the PR's head SHA (`Review queued` → `Review in progress` → `Review completed`), and **a clean review posts no review object at all** — a zero-finding run leaves only the walkthrough comment plus the `Review completed` success status. Read the outcomes as:

- Status `Review completed` + review object for the head commit → findings exist; triage them.
- Status `Review completed` + no review object → genuine zero findings; the gate passes.
- No `CodeRabbit` status at all (poll timeout) → the review never started; halt and surface to the user — check the app installation, plan, and automatic-review settings in the CodeRabbit dashboard, or post `@coderabbitai full review` and read the response.

The walkthrough / summary issue comment (collapsed `📝 Walkthrough`, pre-merge checks, poem) proves nothing either way — it is posted before the review completes. A repo `.coderabbit.yaml` setting `reviews.commit_status: false` hides the status signal; keep it enabled. When a review object does exist, it is attributed to the head commit by `commit_id`, so stale reviews of earlier commits are never reported.

**Use `pr-with-coderabbit-review.sh` for the entire flow.** Do NOT create the PR separately with `gh pr create` and then try to poll — the script handles PR creation and status-based polling in one shot.

### Normal mode: create PR + poll

```bash
${CLAUDE_SKILL_DIR}/scripts/pr-with-coderabbit-review.sh --title "fix: foo" --body-file /tmp/body.md --base main
```

All arguments are forwarded to `gh-post pr create`. The script then polls the `CodeRabbit` commit status until it reaches a terminal state, outputting either the review body plus that review's inline comments, or an explicit zero-finding result, to stdout.

Inline `--body <string>` and `-b <string>` are rejected by `gh-post` — the wrapper exists to keep every body through its hardwrap validator. Use `--body-file <path>` (preferred) or `--body-stdin`.

### Re-review mode: after pushing fixes

After pushing fix commits to an existing PR, wait for the incremental review the push already triggered:

```bash
${CLAUDE_SKILL_DIR}/scripts/pr-with-coderabbit-review.sh --re-review https://github.com/owner/repo/pull/123
```

No trigger step is needed — CodeRabbit starts the incremental review on the push itself. The status lives on the new head SHA, so the wait is race-free even when the review finishes before the script starts.

### Poll-only mode: recovery for existing PRs

```bash
${CLAUDE_SKILL_DIR}/scripts/pr-with-coderabbit-review.sh --poll https://github.com/owner/repo/pull/123
```

Same wait as `--re-review`; use it after triggering a review manually. On timeout the script prints the manual trigger command (`gh pr comment <N> --body "@coderabbitai full review"`) for the case where automatic reviews are disabled or the app missed the event.

### Environment variables

- `CODERABBIT_POLL_INITIAL` — initial poll interval in seconds (default: 60)
- `CODERABBIT_POLL_MAX` — max poll interval (default: 300)
- `CODERABBIT_POLL_ATTEMPTS` — max attempts (default: 10)

## Triage the review

CodeRabbit reviews see the diff and file contents and run linters / AST checks, but lack project-specific knowledge about design decisions, test coverage, or runtime verification. The output is chattier than most reviewers: the summary body carries collapsed sections (walkthrough, nitpicks, additional comments) and actionable items arrive as inline comments.

For each finding:

1. **Cross-check** against what you already know from the current conversation — code you've read, tests you've run, decisions made with the user
2. **Classify** under the `finding-triage` SSOT dispositions — typically `actionable`, `false-positive` (with reasoning), or `uncertain-validity`; a real finding whose fix is non-local is `opens-a-question` → re-enter `research`
3. **Present the triage** to the user — don't dump raw review output

Items inside the collapsed nitpick sections of the review body are findings too — expand and triage them under the same dispositions rather than skipping the collapsed blocks.

## Respond to review

Each CodeRabbit finding lives on an inline thread; that thread is the unit of response. After triaging, reply within each thread via `gh-post reply-inline` — every reply body is validated (hardwrap detector + halt-before-send) and a single batch covers the full review:

```bash
# 1. Collect target threads — by default this filters to CodeRabbit-authored heads
#    and reports per-thread state (resolved? has reply? outdated?).
#    Use --unresolved --unreplied to narrow to threads that actually need a reply.
${CLAUDE_SKILL_DIR}/scripts/list-pr-threads.sh {owner}/{repo} {number} --unresolved --unreplied

# 2. Build a JSONL file: one {"id": <head-comment-id>, "body": "<reply text>"} per line.
#    Each reply should be concise — state the classification (fixed, false positive,
#    acknowledged) and the reasoning in 1-2 sentences.

# 3. Send the batch. The wrapper validates every body BEFORE any send; on a body
#    failure no replies post. On a mid-batch API failure it prints un-sent indices
#    and exits non-zero.
gh-post reply-inline {owner}/{repo} {number} < /tmp/replies.jsonl
```

If `list-pr-threads.sh --unresolved --unreplied` returns zero lines: every CodeRabbit thread is already resolved or already has a reply — do NOT post additional replies. Surface this to the user and ask before doing anything else. Stacking a duplicate "addressed in …" reply on a closed thread is the failure mode this wrapper exists to prevent.

CodeRabbit converses on its own threads: it may reply to your reply, and its incremental reviews may resolve threads it judges addressed by a fix commit. Both states are already excluded by `--unresolved --unreplied`, so re-run `list-pr-threads.sh` after each incremental review instead of caching an earlier thread list.

Direct `gh api .../comments/{id}/replies -F body=...` is still possible but defeats both the body-validation guarantee and the thread-state filter — use it only for one-off cases where the JSONL ceremony is overhead, and verify thread state via `list-pr-threads.sh` first.

## Prerequisites

- CodeRabbit GitHub app installed on the repository — PR reviews on private repositories require a Pro plan or active trial; public repositories get them free
- `gh` CLI
- `gh-post` on `PATH` — the script routes PR creation through `gh-post pr create` so the body passes the wrapper's validator stack
- Optional: `.coderabbit.yaml` in the repo root to tune noise (`profile: chill`), path filters, and auto-review behavior

## Combined pipeline with codex-review

```
codex review loop (pre-PR, local)
    ↓ clean
${CLAUDE_SKILL_DIR}/scripts/pr-with-coderabbit-review.sh (creates PR + polls for auto review)
    ↓ review received
Triage + respond to each inline comment via gh-post reply-inline (JSONL batch)
    ↓ if fixes needed
Push fixes (triggers the incremental review)
    ↓
${CLAUDE_SKILL_DIR}/scripts/pr-with-coderabbit-review.sh --re-review <PR_URL>
    ↓ new review received
Triage + respond again
```
