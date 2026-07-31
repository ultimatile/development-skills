---
name: review-pipeline
description: Full review pipeline from local changes through PR, Copilot review, postmortem elevation, and umbrella drift join. Pauses at the user-controlled merge gate between Phase 4a and 4b.
---

# Review Pipeline

Orchestrate the full flow from local changes through PR review, user merge, postmortem elevation, and umbrella drift join. This skill ties together several sub-skills — invoke each by name.

The pipeline crosses a **user-controlled merge gate** (Phase 4a → 4b): the user, not Claude, merges the PR. Phases before the gate run on the PR branch; phases after run on `main` and tracking issues. Claude pauses at the `## ← user merges PR ←` section.

## Pipeline entry

This pipeline takes two inputs, stated before the first phase the run executes. A run entering at Phase 4a or 4b takes neither: from Phase 4a on, no step commits, uses a root, or opens a PR — 4a reads the sub-issue and edits the PR body, and 4b runs on `main` after the merge.

- **Root** — the branch this change merges into, as a bare branch name, supplied by the caller on `diff-root`'s terms. Every gate here is a coverage invocation in that skill's sense, so all of them take this one value: every `/done-check` invocation (Phase 0, Phase 0.5's delta run, and the fix-loop substep), Phase 0.5's `/code-review-gate`, Phase 1's `/codex-review`, and — when the run reads fix commits rather than working from review findings alone — Phase 3's `/bug-to-contract` and `/finding-to-audit`. Phase 2 opens the PR against that same branch. This pipeline resolves no root: with none supplied, ask.

- **Branch guard** — run the default-branch check in Rules. This entry check is in addition to the per-`/stage-commit-push` checks, not a replacement for them.

## Phase 0: Done-check loop

1. Run `/done-check` against the current diff (committed + staged + unstaged + untracked), passing the root stated at pipeline entry.
2. Triage what it returned — both the `⚠` rows of the audit table and the cross-cutting concerns reported under it.
3. If done-check's step 5 gate is not yet satisfied over everything it returned:
   - Fix the code
   - Run `/done-check` again (fresh, full audit — do not bias the next pass with the previous concerns list)
   - Re-triage
4. Repeat until done-check's step 5 gate is satisfied over both domains — its rows and its cross-cutting concerns. That gate owns which dispositions close each; do not restate them here.

What binds this phase is that the audit closing it saw the diff that proceeds — step 3 secures that by re-running the audit after every fix.

## Phase 0.5: Claude code-review gate

Runs after the done-check loop.

1. Run `/code-review-gate` against the current diff, passing the root stated at pipeline entry and `high` for a large or risky diff, `medium` otherwise. The gate skill owns effort semantics, the lane chain, lane-failure handling, and exhaustion.
2. Triage the output — classify each finding under the `finding-triage` SSOT dispositions.
3. If actionable findings exist: fix, run `/done-check` in delta mode against the previous audit's rows and concerns with the same root, then re-run `/code-review-gate` at the same effort and root (fresh, full review — no bias from the previous iteration). If the same conceptual topic recurs across 2+ iterations, stop and follow the escalation order in Rules.
4. Repeat until no actionable findings remain.

Step 3 gives this gate the same property Phase 0 has: the review closing it saw the diff that proceeds.

When that diff received a valid gate review (i.e. the gate was not waived), attribute each **Phase 1 and Phase 2** reviewer finding to one of two provenances, and note it in the triage presentation. A finding already present in the diff this gate reviewed is by construction a penetration of it. A finding introduced by a Phase 1 or Phase 2 fix is not: those fix loops run the audit, commit, and re-run the current reviewer, never this gate, so the defect did not exist when this gate ran.

## Phase 1: Codex review loop

1. Ensure the diff Phase 0.5 reviewed is committed and pushed, which is the state `/codex-review`'s `--base` mode is defined over. Run `/stage-commit-push`, which routes on what is actually outstanding — commit and push, push only, or nothing — so an entry arriving already committed and pushed passes through it without action.
2. Run `/codex-review` to review the branch diff, passing the root stated at pipeline entry
3. Triage the output — classify each finding under the `finding-triage` SSOT dispositions
4. If actionable findings exist, apply the **fix-loop substeps** (see Rules) and repeat until no actionable findings remain.

## Phase 2: Copilot review

1. Run `/file-pullreq` in **gate mode** — drafts the PR title + body following `gh-body-conventions` and the standard body skeleton, discharges its evidence claims, runs the laundering pass, and gets the user's approval. The skill stops at approval and emits the approved title + body for the next step. It does NOT create the PR itself.
2. Run `/copilot-review` in its normal mode, passing the approved title + body and **the root as this pipeline's `--base`** — this creates the PR with `--reviewer @copilot` and polls until the review arrives. The root is a branch name, which is what that flag takes; `/codex-review`'s `--base` one phase earlier is a different value, a merge base derived from the same root. Omitting it opens the PR against the repository default branch, and every gate above measured from the branch this run was told it merges into, so the two would then disagree.
3. Triage the review — filter to the latest review's comments only (by `pull_request_review_id`)
4. Reply to each inline comment individually via `gh-post reply-inline <owner>/<repo> <PR> < /tmp/replies.jsonl`. Build the JSONL with one `{"id": <comment-id>, "body": "<reply>"}` per line; the wrapper validates every body through the hardwrap detector before any send (halt-before-send) and prints un-sent indices on a mid-batch API failure.
5. If actionable findings exist, apply the **fix-loop substeps** (see Rules), replacing the re-review step with `${CLAUDE_SKILL_DIR}/../copilot-review/scripts/pr-with-copilot-review.sh --re-review <PR_URL>`. Triage only new comments. Repeat until no actionable findings remain.

## Phase 3: Postmortem elevation (pre-merge)

After Phase 1 + 2 are clean, before the user merges, fold review findings into durable artifacts:

1. **`/bug-to-contract`** — for each actionable finding from Phase 1 and 2 (not just fix commits), ask whether an implicit contract was violated and whether it is now tested.

2. **`/codex-contract-test-review`** — for each contract test added in step 1, run a narrow Codex pass: does the test express the claimed contract, and would it fail on the original buggy implementation?

   - If actionable findings: revise the test and re-run this step **once**. Repeated iteration → escalate to the user.
   - If clean: continue.

3. **`/finding-to-audit`** — for findings whose detection would have been **diff-inspectable** (import direction, `pub` widening, missing standard trait impl, debug artifacts, hardcoded values, FFI output dropped, etc.), promote to a pre-commit audit rule in the host `finding-to-audit` selects — a rule-set SSOT such as `quality-list` or `authoritative-text-rules`, or a domain-specific audit skill. By default this files an issue against the host skill's repository proposing the rule, reviewed there on its own timeline — so the elevation neither blocks this project's merge gate nor lands as an unreviewed edit to a shared audit surface.

4. **`/stage-commit-push`** — push the contract-test commits in the project repo.

A finding can map to either `bug-to-contract`, `finding-to-audit`, both, or neither. Use both when both apply.

**`/gate-miss-to-issue`** (process-postmortem) — when a defect surfaced only at Phase 1/2 review or by user pushback that an earlier gate should have caught, file the gate gap against `development-skills` (independent of the project merge gate, like `/finding-to-audit`). Skip when every defect was caught at its earliest gate.

## Phase 4a: PR description delta (pre-merge)

Skip when the work is not tied to an umbrella tracking issue. Trigger only when the merged-bound PR or its `Closes #N` references a sub-issue with a `Parent: #<umbrella>` line.

1. **Find the parent reference.** Read the sub-issue body:

   ```bash
   gh issue view <leaf#> --json body -q .body | rg '^Parent:' | head -1
   ```

   No match → skip Phase 4a and 4b entirely.

2. **Derive the plan-vs-actual delta.** Compare the sub-issue's Scope / Out of scope / Acceptance against the merged-bound PR's actual diff and behavior. Cover:

   - Scope additions (work that landed but was not in the original Scope) — was it justified, or scope creep?
   - Scope subtractions (Scope items that were deferred or dropped) — were they punted to a follow-up issue?
   - Out-of-scope churn (deferrals that became in-scope, or new deferrals discovered during implementation)
   - Acceptance criteria that were tightened, loosened, or reworded during review

   A "no delta" outcome (everything matched) is a valid answer — record it explicitly.

3. **Edit the PR description.** Append a `## Plan-vs-actual delta` section to the existing body — full delta with file/line evidence and links to the relevant review iterations.

   Apply `gh-body-conventions` to the appended section (same semantic line breaks, same exclusions). Line refs into this PR's diff are permitted.

   Discharge the appended section's evidence claims per `gh-body-conventions` § Evidence claims before running the check below, and re-check any completeness claim already in the body — work done since the body was last discharged can have falsified one without its text changing.

   Before invoking `gh-post pr edit`, run `/gh-body-check` against the **final body** (existing PR body concatenated with the appended delta section). Paragraph boundaries and reference patterns can cross the section seam, so auditing only the appended section would miss them. Pass artifact kind `pr` and the target language. Any unresolved ⚠ blocks `gh-post pr edit` — revise the appended section, re-discharge its evidence claims, and re-run until clean.

   Write the final body to a temp file and invoke `gh-post pr edit <N> --repo <owner>/<repo> --body-file /tmp/<descriptive-name>.md`. Do not run `gh pr edit ... --body*` directly; route the body through `gh-post`.

## ← user merges PR ←

Stop here. The user merges the PR via the GitHub UI or `gh pr merge`. Do not attempt the merge from Claude unless the user explicitly asks.

After the user confirms the merge has landed, continue to Phase 4b.

## Phase 4b: Umbrella drift join (post-merge)

Runs only after the user has merged.

1. **Sub-issue closing comment.** Post a compressed delta (≈ 5–10 lines) plus the merged PR link via `gh-post issue comment <leaf#> --repo <owner>/<repo> --body-file /tmp/<descriptive-name>.md`, then close the sub-issue with `gh issue close <leaf#>`. (Route the comment body through `gh-post`, not `gh issue comment ... --body*` directly; `gh issue close` carries no body and stays a direct `gh` call.)

2. **Umbrella body update.** Two independent axes:

   - **Progress reflection (default action).** If the umbrella tracks sub-items by status annotation (`- [x] foo` checkbox, `_[Promoted to #N.]_` / `_[Done in #M.]_` inline tag, `Phases | Status` table column, etc.), update the item the leaf was promoted from. The skill that filed the leaf already wrote the "promoted" annotation; the merge step closes the loop by switching it to "done". Skip only if the umbrella truly has no per-item status convention.
   - **Design-assumption change.** Edit additionally when the delta changes a parent-level design assumption — a new deferral that affects another phase, a scope shift that invalidates the Phases table, a decision that contradicts the umbrella's "Decisions captured" section.

   A clean implementation with no parent-level implications still gets the progress-reflection edit; the design-assumption axis can be skipped.

3. **Do not edit the sub-issue body.**

## Rules

- **Fix-loop substeps** (Phase 1 step 4 and Phase 2 step 5):

  1. **Oscillation check (iteration N ≥ 2).** Compare current actionable topics against the previous iteration's preserved topics. If any conceptual topic recurs, halt and follow the escalation order below — do NOT fix or done-check.
  2. Fix the code.
  3. Run `/done-check` in delta mode, against the previous audit's rows and concerns, with the root stated at pipeline entry.
  4. Run `/stage-commit-push`.
  5. Re-run the review (fresh, full review — no bias from previous iteration). Phase 2 uses `--re-review` instead.
  6. Preserve actionable topic classifications for the next iteration's oscillation check.
  7. Re-triage (Phase 2: only new comments).

- **Never skip done-check, including in fix loops.** Every fix commit is itself a diff that can introduce new drift — especially `completion-hygiene` and `paired-artifact-drift`.

- **A halted done-check stops the pipeline.** This binds every `/done-check` invocation here — Phase 0, Phase 0.5, and the fix-loop substep alike. A halted run emits no table. The step that invoked it does not complete: do not fix, do not commit, do not re-review. It has surfaced something to the user; that is where the pipeline waits.

- **Done-check delta mode.** `done-check` defines the mode, what a delta report carries, and what its step 5 gate binds. Satisfy that gate before the subsequent `/stage-commit-push` rather than only the ⚠ the delta printed. Pay special attention to:

  - `paired-artifact-drift`: every comment / docstring / PR-body sentence touched by or referring to the fixed code must still be accurate. Accuracy is not the whole test: a fix that answers a reviewer by *qualifying* a documented behavior — admitting a case the doc did not — strands every unqualified statement of that behavior elsewhere, which an accuracy check over the fix's own text never looks at. Run the item's **Qualification completeness** sweep on those fixes. Fix loops generate this class, which the first-pass audit cannot pre-empt: the caveat does not exist yet for the earlier text to contradict.
  - `completion-hygiene`: pre-commit hooks catch lint / fmt / line count, but the fix may have added stray `dbg!` / `println!` / scratch test code.
  - `behavior-coverage`: a fix that edits a docstring / module doc stating a behavioral guarantee can silently widen it to sibling symbols, creating a per-symbol coverage obligation the previous audit never saw. Run the delta pass as a fresh `done-check` (subagent) invocation rather than informal doc-truth reasoning — confirming the broadened claim is *true* does not confirm each newly-covered symbol is *tested*.
  - The PR description: if a fix invalidates a claim in the description (e.g., "previously-missed mutant is now caught" became "now excluded"), update the description in the same iteration. That edit is text changed after its claims were discharged, so re-discharge the description in main context per `gh-body-conventions` § Evidence claims and re-run `/gh-body-check` against the result before posting it.

- **Never skip codex review.** Even for small fixes, run the full loop.

- **Never inject previous review comments into the next review prompt.**

- **Every commit goes through `/stage-commit-push`.** Do not manually run git add/commit/push during the pipeline.

- **Pre-commit branch gate.** Before each `/stage-commit-push`, and at pipeline entry on the terms Pipeline entry states, verify the current branch is not the repo's default branch:

  ```
  default=$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's@^origin/@@')
  test -n "$default" || { echo "remote HEAD unset — run: git remote set-head origin -a"; exit 1; }
  test "$(git symbolic-ref --short HEAD)" != "$default"
  ```

  The first two lines are `diff-root`'s default-branch read, spelled out because this check runs it; that skill states why each is load-bearing. Halt and surface to the user if the branches are equal, or if the default branch does not resolve.

- **Reply to Copilot comments individually**, not as a single PR comment. Use `gh-post reply-inline <owner>/<repo> <PR> < /tmp/replies.jsonl`. JSONL shape: one `{"id": <comment-id>, "body": "<reply>"}` per line.

- **Triage is mandatory.** Never present raw review output to the user. Classify every finding under the `finding-triage` SSOT dispositions and lead with actionable items.

- **Select the response before fixing.** Select the edit per `finding-triage`'s **Response selection (actionable findings)**; a finding fitting `invariant-premise-check` or `opens-a-question` re-triages per those dispositions. For a premise check, if unsure, ask codex a single targeted question via `codex exec "<fix proposal + one specific question about the premise>" -o /tmp/fix-check.md`. The commit is owned by whichever `/stage-commit-push` step the current phase runs.

- **Oscillation detection.** Run at the start of each fix-loop iteration (the first sub-bullet under "If actionable findings exist" in Phase 1 step 4 and Phase 2 step 5), BEFORE fix and done-check. If the same conceptual topic (not the same literal comment, but the same underlying question — e.g., "is this input valid?", "does this property hold?", "should this parameter accept both values?") appears across 2+ consecutive review iterations, stop fixing and escalate to the user. Repeated findings on one topic signal that the underlying invariant is not understood well enough for a confident fix.

  **Escalation order.** Before presenting the fix-direction question (panic vs allow vs convert vs ...), FIRST ask whether the original plan scope is correct. Oscillation in the fix-direction space is the symptom that the contract is empty or depends on something outside the plan's scope — refining the fix without rescoping just re-anchors the same empty contract from a different angle. Ask in this order:

  1. **Is this question even single-actionable inside the current plan?** Does the disagreement among reviewers concern an upstream undecided design question (consumer semantics, system invariant, layout authority, etc.) that the plan implicitly assumed?
  2. **If yes upstream**: rescope. Close the current PR, refile the upstream design question as a separate issue, and let the current API decision fall out of that resolution. This is the right move even when the current fix is technically correct in isolation.
  3. **If no upstream issue**: present what is known, what is uncertain, and ask the user to choose among the surviving fix options.

  The "no-clarifying-questions" mode does NOT override this rule. Convergence of three independent reviewers on the same API-contract concern is the signal regardless of mode.

- **Pause at the merge gate.** Phase 4b runs only after the user merges. Do not run `gh pr merge` from Claude unless explicitly asked.

- **Contract-test review is bounded.** `/codex-contract-test-review` allows at most one revise-and-re-review cycle. If it doesn't converge, the contract itself is unclear — escalate, don't loop.
