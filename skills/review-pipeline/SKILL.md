---
name: review-pipeline
description: Full automated review pipeline — commit, codex review, fix loop, then PR with Copilot review. Use this skill when the user says things like "review pipeline", "commit and review", "PR pipeline", "submit for review", or wants to go from local changes all the way through to a reviewed PR. Also trigger when the user has finished implementation and wants to run the full review-and-submit flow.
---

# Review Pipeline

Orchestrate the full flow from local changes to a reviewed PR. This skill ties together three sub-skills — invoke each by name.

## Pipeline

```
  ┌─────────────────────────────────────────────┐
  │  Phase 1: Codex review loop (local)         │
  │                                             │
  │  /stage-commit-push                         │
  │       ↓                                     │
  │  /codex-review                              │
  │       ↓                                     │
  │  actionable? ──yes──→ fix → loop back       │
  │       ↓ no                                  │
  └───────┼─────────────────────────────────────┘
          ↓
  ┌─────────────────────────────────────────────┐
  │  Phase 2: Copilot review (remote)           │
  │                                             │
  │  /copilot-review (creates PR + polls)       │
  │       ↓                                     │
  │  actionable? ──yes──→ fix                   │
  │       ↓               ↓                     │
  │       │         /stage-commit-push           │
  │       │               ↓                     │
  │       │         --re-review → loop back     │
  │       ↓ no                                  │
  └───────┼─────────────────────────────────────┘
          ↓
  ┌─────────────────────────────────────────────┐
  │  Phase 3: Bug-to-contract                   │
  │                                             │
  │  /bug-to-contract (from review findings)    │
  │       ↓                                     │
  │  contract tests proposed? ──yes──→ add test │
  │       ↓ no                    + commit      │
  └───────┼─────────────────────────────────────┘
          ↓
        Done
```

## Phase 1: Codex review loop

1. Run `/stage-commit-push` to stage, commit, and push local changes
2. Run `/codex-review` to review the branch diff against main
3. Triage the output — classify each finding as actionable, false positive, or uncertain
4. If actionable findings exist:
   - Fix the code
   - Run `/stage-commit-push` again
   - Run `/codex-review` again (fresh, full review — no bias from previous iteration)
   - Re-triage
5. Repeat until no actionable findings remain

## Phase 2: Copilot review

6. Run `/copilot-review` — this creates the PR with `--reviewer @copilot` and polls until the review arrives
7. Triage the review — filter to the latest review's comments only (by `pull_request_review_id`)
8. Reply to each inline comment individually via `gh api .../pulls/{number}/comments -X POST -F in_reply_to={id}`
9. If actionable findings exist:
   - Fix the code
   - Run `/stage-commit-push`
   - Run `${CLAUDE_SKILL_DIR}/../copilot-review/scripts/pr-with-copilot-review.sh --re-review <PR_URL>` to trigger and wait for a new review
   - Triage the new review (only new comments)
10. Repeat until no actionable findings remain

## Phase 3: Bug-to-contract

After all reviews are clean and fixes are committed:

11. Run `/bug-to-contract` with all actionable findings from Phase 1 and 2 as input — not just fix commits. Any finding that required a code change is evidence of a missing contract, regardless of whether the fix was a one-line doc tweak or a multi-file refactor.
12. If contract tests are proposed, add them, run `/stage-commit-push`, and push

## Rules

- **Never skip codex review.** Even for small fixes, run the full loop. Codex review catches things that are invisible in the diff alone.
- **Never inject previous review comments into the next review prompt.** Each review iteration must be fresh and unbiased, so it can catch both regressions from the fix and new problems.
- **Every commit goes through `/stage-commit-push`.** Do not manually run git add/commit/push during the pipeline. The skill ensures consistent commit message generation.
- **Reply to Copilot comments individually**, not as a single PR comment. Use `gh api .../pulls/{number}/comments -X POST -F in_reply_to={comment_id}` for each.
- **Triage is mandatory.** Never present raw review output to the user. Classify findings and lead with actionable items.
- **Sub-classify actionable findings before fixing.** Not all actionable findings warrant the same response:
  - **Surface** (typo, stale comment, wrong API name): fix is self-evident. Commit immediately.
  - **Invariant** (claims about mathematical properties, semantic validity, precondition necessity): the finding's *conclusion* may be correct, but its *premise* may be wrong. Before committing a fix, verify the premise — check whether the invariant the finding assumes actually holds, by reading code, tests, and running targeted experiments. If unsure, ask codex a single targeted question via `codex exec "<fix proposal + one specific question about the premise>" -o /tmp/fix-check.md` before committing.
- **Oscillation detection.** If the same conceptual topic (not the same literal comment, but the same underlying question — e.g., "is this input valid?", "does this property hold?") appears across 2+ consecutive review iterations, stop fixing and escalate to the user. Repeated findings on one topic signal that the underlying invariant is not understood well enough for a confident fix. Present what is known, what is uncertain, and ask the user for direction.
