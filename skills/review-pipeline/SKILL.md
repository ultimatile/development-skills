---
name: review-pipeline
description: Full automated review pipeline — done-check, codex review, fix loop, then PR with Copilot review, postmortem elevation, and umbrella drift join. Use this skill when the user says things like "review pipeline", "commit and review", "PR pipeline", "submit for review", or wants to go from local changes all the way through to a reviewed and merged PR. Also trigger when the user has finished implementation and wants to run the full review-and-submit flow.
---

# Review Pipeline

Orchestrate the full flow from local changes through PR review, user
merge, postmortem elevation, and umbrella drift join. This skill ties
together several sub-skills — invoke each by name.

The pipeline crosses a **user-controlled merge gate**: the user (not
Claude) merges the PR. Phases before the gate run on the PR branch;
phases after the gate run on `main` and on tracking issues. The
`← user merges PR ←` line in the diagram marks the boundary
explicitly so Claude pauses there.

## Pipeline

```
  ┌─────────────────────────────────────────────────┐
  │  Phase 0: Done-check loop (local, pre-commit)   │
  │                                                 │
  │  /done-check                                    │
  │       ↓                                         │
  │  any ⚠ concerns? ──yes──→ fix → loop back       │
  │       ↓ no                                      │
  └───────┼─────────────────────────────────────────┘
          ↓
  ┌─────────────────────────────────────────────┐
  │  Phase 1: Codex review loop (local)         │
  │                                             │
  │  /stage-commit-push                         │
  │       ↓                                     │
  │  /codex-review                              │
  │       ↓                                     │
  │  actionable? ──yes──→ fix                   │
  │       ↓               ↓                     │
  │       │         /done-check (delta)         │
  │       │               ↓                     │
  │       │         /stage-commit-push          │
  │       │               ↓                     │
  │       │         /codex-review → loop back   │
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
  │       │         /done-check (delta)         │
  │       │               ↓                     │
  │       │         /stage-commit-push          │
  │       │               ↓                     │
  │       │         --re-review → loop back     │
  │       ↓ no                                  │
  └───────┼─────────────────────────────────────┘
          ↓
  ┌─────────────────────────────────────────────────┐
  │  Phase 3: Postmortem elevation (pre-merge)      │
  │                                                 │
  │  3a. /bug-to-contract → test additions          │
  │       ↓                                         │
  │  3b. /codex-contract-test-review (narrow pass)  │
  │       ↓                                         │
  │  actionable? ──yes──→ revise test → 3b once     │
  │       ↓ no                                      │
  │  3c. /finding-to-audit (development-skills)     │
  │       ↓ (separate repo, no project merge gate)  │
  │  3d. /stage-commit-push (project test commits)  │
  └───────┼─────────────────────────────────────────┘
          ↓
  ┌─────────────────────────────────────────────────┐
  │  Phase 4a: PR description delta (pre-merge)     │
  │                                                 │
  │  derive plan-vs-actual delta                    │
  │       ↓                                         │
  │  edit PR description = full delta + evidence    │
  └───────┼─────────────────────────────────────────┘
          ↓
  ━━━━━━━━━ ← user merges PR ← ━━━━━━━━━━━━━━━━━━━━━━
          ↓
  ┌─────────────────────────────────────────────────┐
  │  Phase 4b: Umbrella drift join (post-merge)     │
  │                                                 │
  │  closed sub-issue references `Parent: #N`?     │
  │       ↓ yes                                     │
  │  sub-issue closing comment = compressed delta   │
  │  parent body = update only on design drift      │
  │       ↓ no parent ref                           │
  │  skip Phase 4b                                  │
  └───────┼─────────────────────────────────────────┘
          ↓
        Done
```

## Phase 0: Done-check loop

0a. Run `/done-check` against the current diff (committed + staged + unstaged + untracked)
0b. Triage the audit table — every `⚠` concern is actionable
0c. If concerns exist:
   - Fix the code
   - Run `/done-check` again (fresh, full audit — same rule as the codex review loop: do not bias the next pass with the previous concerns list)
   - Re-triage
0d. Repeat until all rows are `✅` or `⊘ N/A`

Done-check runs **before** any commit. Resolving its concerns post-commit produces noisy fix-up commits in the codex review history; resolving them pre-commit keeps each commit a meaningful unit.

## Phase 1: Codex review loop

1. Run `/stage-commit-push` to stage, commit, and push local changes
2. Run `/codex-review` to review the branch diff against main
3. Triage the output — classify each finding as actionable, false positive, or uncertain
4. If actionable findings exist:
   - Fix the code
   - Run `/done-check` in **delta mode** (see Rules below)
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
   - Run `/done-check` in **delta mode** (see Rules below)
   - Run `/stage-commit-push`
   - Run `${CLAUDE_SKILL_DIR}/../copilot-review/scripts/pr-with-copilot-review.sh --re-review <PR_URL>` to trigger and wait for a new review
   - Triage the new review (only new comments)
10. Repeat until no actionable findings remain

## Phase 3: Postmortem elevation (pre-merge)

After Phase 1 + 2 are clean, before the user merges, fold review
findings into durable artifacts:

11. **`/bug-to-contract`** — for each actionable finding from Phase 1
    and 2 (not just fix commits), ask whether an implicit contract
    was violated and whether it is now tested. Any finding that
    required a code change is evidence of a missing contract,
    regardless of whether the fix was a one-line doc tweak or a
    multi-file refactor.

12. **`/codex-contract-test-review`** — for each contract test added
    in Step 11, run a narrow Codex pass that asks: does the test
    actually express the claimed contract, and would it fail on the
    original buggy implementation? This is a lighter substitute for
    a full re-run of Phase 1 + 2 on the contract-test commits, which
    would otherwise be excessive.

    - If actionable findings: revise the test and re-run this step
      **once**. Repeated iteration signals the contract itself is
      unclear — escalate to the user.
    - If clean: continue.

13. **`/finding-to-audit`** — for findings whose detection would have
    been **diff-inspectable** (import direction, `pub` widening,
    missing standard trait impl, debug artifacts, hardcoded values,
    FFI output dropped, etc.), elevate to a pre-commit audit rule in
    the `done-check` skill (or the relevant host skill). This edits
    the `development-skills` repo, which is independent of the
    project's merge gate — commits land without waiting on Phase 4.

14. **`/stage-commit-push`** — push the contract-test commits in the
    project repo.

A finding can map to either `bug-to-contract`, `finding-to-audit`,
both, or neither. Use both when both apply.

## Phase 4a: PR description delta (pre-merge)

Skip when the work is not tied to an umbrella tracking issue.
Trigger only when the merged-bound PR or its `Closes #N` references
a sub-issue with a `Parent: #<umbrella>` line.

15. **Find the parent reference.** Read the sub-issue body:

    ```bash
    gh issue view <leaf#> --json body -q .body | rg '^Parent:' | head -1
    ```

    No match → skip Phase 4a and 4b entirely.

16. **Derive the plan-vs-actual delta.** Compare the sub-issue's
    Scope / Out of scope / Acceptance against the merged-bound PR's
    actual diff and behavior. Cover:
    - Scope additions (work that landed but was not in the
      original Scope) — was it justified, or scope creep?
    - Scope subtractions (Scope items that were deferred or
      dropped) — were they punted to a follow-up issue?
    - Out-of-scope churn (deferrals that became in-scope, or new
      deferrals discovered during implementation)
    - Acceptance criteria that were tightened, loosened, or
      reworded during review

    A "no delta" outcome (everything matched) is a valid answer —
    record it explicitly so the join step is auditable.

17. **Edit the PR description.** Full delta with file/line evidence
    and links to the relevant review iterations. This is the most
    detailed surface; it stays attached to the merged PR for future
    bisect readers. Done pre-merge so the merge commit's link to
    the PR has the complete context.

## ← user merges PR ←

Stop here. The user merges the PR via the GitHub UI or
`gh pr merge`. Do not attempt the merge from Claude unless the user
explicitly asks.

After the user confirms the merge has landed, continue to Phase 4b.

## Phase 4b: Umbrella drift join (post-merge)

Runs only after the user has merged.

18. **Sub-issue closing comment.** Post a compressed delta
    (≈ 5–10 lines) plus the merged PR link via
    `gh issue comment <leaf#>`, then close the sub-issue with
    `gh issue close <leaf#>`.

19. **Umbrella body update.** Edit only when the delta changes a
    **parent-level design assumption** — a new deferral that
    affects another phase, a scope shift that invalidates the
    Phases table, a decision that contradicts the umbrella's
    "Decisions captured" section. A clean implementation with no
    parent-level implications gets no umbrella edit.

20. **Do not edit the sub-issue body.** It was the frozen
    plan-confirmed contract; the closing comment is the journal
    entry. Editing the body rewrites history that other surfaces
    (PR title, commit messages) already point to.

## Rules

- **Never skip done-check, including in fix loops.** Phase 0 audits the initial implementation, but every fix commit is itself a diff that can introduce new drift — especially items 9 (completion hygiene) and 11 (textual-drift sweep). Skipping a fix-loop done-check is the most common cause of multi-iteration review oscillation on documentation, comments, and PR-body wording.
- **Fix-loop done-check runs in delta mode.** Report only rows whose status changes from the previous audit, plus any new ⚠ introduced by the fix. Items still passing from Phase 0 stay implicit — do not re-print the full table on every fix iteration. Resolve any new ⚠ before the subsequent `/stage-commit-push`. Pay special attention to:
  - Item 11 (textual-drift): every comment / docstring / PR-body sentence touched by or referring to the fixed code must still be accurate.
  - Item 9 (hygiene): pre-commit hooks catch lint / fmt / line count, but the fix may have added stray `dbg!` / `println!` / scratch test code.
  - The PR description: if a fix invalidates a claim in the description (e.g., "previously-missed mutant is now caught" became "now excluded"), update the description in the same iteration.
- **Never skip codex review.** Even for small fixes, run the full loop. Codex review catches things that are invisible in the diff alone.
- **Never inject previous review comments into the next review prompt.** Each review iteration must be fresh and unbiased, so it can catch both regressions from the fix and new problems.
- **Every commit goes through `/stage-commit-push`.** Do not manually run git add/commit/push during the pipeline. The skill ensures consistent commit message generation.
- **Pre-commit branch gate.** Before each `/stage-commit-push` invocation in this pipeline, verify the current branch is not the repo's default branch:

      test "$(git symbolic-ref --short HEAD)" != \
           "$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's@^origin/@@')"

  Halt and surface to user if equal. The session-start branch baseline (e.g. `research-and-implement-egel` Phase 0) is one-shot and does not catch silent mid-session branch switches.
- **Reply to Copilot comments individually**, not as a single PR comment. Use `gh api .../pulls/{number}/comments -X POST -F in_reply_to={comment_id}` for each.
- **Triage is mandatory.** Never present raw review output to the user. Classify findings and lead with actionable items.
- **Sub-classify actionable findings before fixing.** Not all actionable findings warrant the same response:
  - **Surface** (typo, stale comment, wrong API name): fix is self-evident. Commit immediately.
  - **Invariant** (claims about mathematical properties, semantic validity, precondition necessity): the finding's *conclusion* may be correct, but its *premise* may be wrong. Before committing a fix, verify the premise — check whether the invariant the finding assumes actually holds, by reading code, tests, and running targeted experiments. If unsure, ask codex a single targeted question via `codex exec "<fix proposal + one specific question about the premise>" -o /tmp/fix-check.md` before committing.
- **Oscillation detection.** If the same conceptual topic (not the same literal comment, but the same underlying question — e.g., "is this input valid?", "does this property hold?") appears across 2+ consecutive review iterations, stop fixing and escalate to the user. Repeated findings on one topic signal that the underlying invariant is not understood well enough for a confident fix. Present what is known, what is uncertain, and ask the user for direction.
- **Pause at the merge gate.** Phase 4b runs only after the user merges. Do not run `gh pr merge` from Claude unless explicitly asked.
- **Contract-test review is bounded.** `/codex-contract-test-review` allows at most one revise-and-re-review cycle. If it doesn't converge, the contract itself is unclear — escalate, don't loop.
