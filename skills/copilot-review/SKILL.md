---
name: copilot-review
description: Create a GitHub PR with Copilot as reviewer and poll until the review arrives.
allowed-tools: Bash(*/copilot-review/scripts/pr-with-copilot-review.sh:*), Bash(*/copilot-review/scripts/list-pr-threads.sh:*)
---

# Copilot Review

Create a GitHub PR, request Copilot review, poll until it arrives, and triage the results.

## How it works

**Use `pr-with-copilot-review.sh` for the entire flow.** Do NOT create the PR separately with `gh pr create` and then try to poll — the script handles PR creation, Copilot review request (`--reviewer @copilot`), and polling in one shot.

### Normal mode: create PR + review + poll

```bash
${CLAUDE_SKILL_DIR}/scripts/pr-with-copilot-review.sh --title "fix: foo" --body-file /tmp/body.md --base main
```

All arguments are forwarded to `gh-post pr create --reviewer @copilot`. The script then polls until Copilot's review arrives, outputting the review body and inline comments to stdout.

Inline `--body <string>` and `-b <string>` are rejected by `gh-post` — the wrapper exists to keep every body through its hardwrap validator. Use `--body-file <path>` (preferred) or `--body-stdin`.

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
2. **Classify** under the `finding-triage` SSOT dispositions — typically `actionable`, `false-positive` (with reasoning), or `uncertain-validity`; a real finding whose fix is non-local is `opens-a-question` → re-enter `research`
3. **Present the triage** to the user — don't dump raw review output

## Respond to review

Each Copilot finding lives on an inline thread; that thread is the unit of response. After triaging, reply within each thread via `gh-post reply-inline` — every reply body is validated (hardwrap detector + halt-before-send) and a single batch covers the full review:

```bash
# 1. Collect target threads — by default this filters to Copilot-authored heads
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

If `list-pr-threads.sh --unresolved --unreplied` returns zero lines: every Copilot thread is already resolved or already has a reply — do NOT post additional replies. Surface this to the user and ask before doing anything else. Stacking a duplicate "addressed in …" reply on a closed thread is the failure mode this wrapper exists to prevent.

Direct `gh api .../comments/{id}/replies -F body=...` is still possible but defeats both the body-validation guarantee and the thread-state filter — use it only for one-off cases where the JSONL ceremony is overhead, and verify thread state via `list-pr-threads.sh` first.

## Prerequisites

- `gh` CLI >= 2.88.0 (for `--reviewer @copilot` support)
- `gh-post` on `PATH` — the script routes PR creation through `gh-post pr create` so the body passes the wrapper's validator stack
- Copilot code review enabled for the repository (via GitHub plan + org/repo settings)
- Alternative: configure automatic Copilot review via Repository Rulesets (Settings > Rules)

## Combined pipeline with codex-review

```
codex review loop (pre-PR, local)
    ↓ clean
${CLAUDE_SKILL_DIR}/scripts/pr-with-copilot-review.sh (creates PR + polls for review)
    ↓ review received
Triage + respond to each inline comment via gh-post reply-inline (JSONL batch)
    ↓ if fixes needed
Push fixes
    ↓
${CLAUDE_SKILL_DIR}/scripts/pr-with-copilot-review.sh --re-review <PR_URL>
    ↓ new review received
Triage + respond again
```
