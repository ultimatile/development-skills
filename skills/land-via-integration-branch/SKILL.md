---
name: land-via-integration-branch
description: >
  Workflow for landing a single large change that does not fit one PR and whose
  intermediate states intentionally break the build. Decomposes the change into
  a sequence of PRs that merge into a long-lived integration branch instead of
  main, with per-unit codex review against a moving last-approved baseline; a
  final PR merges the integration branch into main under the full review
  pipeline. Use when a single PR would exceed a reviewer's diff-size limit, OR
  when the change spans multiple components whose APIs must change together and
  cannot all migrate in one PR. Instances: cross-component API migration, large
  refactor, multi-PR feature.
---
# Land via Integration Branch

A four-gate review cadence for landing a large change that does not fit a single PR, through a long-lived integration branch.

| Gate | Trigger | Action | Baseline |
| -- | -- | -- | -- |
| per-commit | each `git commit` | `/done-check` (preflight `/todo-check`) | working tree |
| per-unit | unit / design-boundary completion | `codex exec review --base <last-approved-SHA>` | last unit-approved SHA |
| per-PR-open | PR creation | `/codex-review` against PR diff | PR base (integration branch) |
| per-PR-review | PR open on GitHub | `/copilot-review` + reply / fix loop | PR head |

Trigger the cadence off commits, units, and PRs only. Do NOT add a per-session gate — session boundaries are human time, not design boundaries.

## When to invoke

- A change that does not fit one PR (diff exceeds a reviewer's size limit, or multiple component APIs must change together).
- The intermediate PRs intentionally break the project-wide build: the per-component test gate is binding intermediate, the full project CI gate runs at the final PR only.

Do NOT use for:

- Single-PR work — `/review-pipeline` covers that directly.
- Changes that compile in every intermediate state — one PR, no integration branch needed.

## Setup procedure

1. **Close or draft the superseded PR (if any).** Post a closing comment that links to the new tracker.

   ```bash
   gh pr close <old-PR> --comment "Superseded by #<new-issue>; new plan in that issue, integration-branch flow below."
   ```

2. **Create the integration branch off main.**

   ```bash
   git checkout main && git pull
   git checkout -b integration/<issue#>-<slug>
   git push -u origin integration/<issue#>-<slug>
   ```

3. **Plan the PR sequence.** Each PR targets one per-component or per-concern scope. Record the sequence in the tracking memory or issue body for cross-session continuity.

## Per-PR workflow

For PR `k` in the sequence (each PR is one or more units):

1. **Branch off the integration branch.**

   ```bash
   git checkout integration/<issue#>-<slug>
   git pull
   git checkout -b pr<k>/<scope>
   ```

2. **Implement units inside the branch.** Each commit goes through per-commit `/done-check`. At each unit boundary, run per-unit codex review against the last approved SHA:

   ```bash
   codex exec review --base <last-unit-approve-SHA> -o /tmp/codex-unit-<k>.<u>.md
   ```

   The baseline starts as the integration branch tip when PR `k` begins; advance it to the last approved SHA after each unit. Triage P1 / P2 findings at this gate before continuing to the next unit.

   **Committing past a workspace-wide pre-commit hook.** A hook that lints the whole workspace (e.g. a project-wide type/lint check) will fail by design on a `pr<k>/...` branch — downstream components scheduled for a later PR are still on the old API. Skip only that one workspace-coherence hook (e.g. `SKIP=<workspace-lint-hook> git commit ...`) after confirming the per-component test and lint gates both pass, and note the skip rationale in the commit body. Do NOT use `--no-verify`; it also drops formatting and line-count hooks, which remain binding.

3. **Open the PR against the integration branch.** Run `/review-pipeline` from the per-PR-open gate forward (codex-review then copilot-review). Merge target is `integration/<issue#>-<slug>`, not `main`.

   ```bash
   gh-post pr create --base integration/<issue#>-<slug> --title "..." --body-file ...
   ```

4. **Merge into the integration branch when reviews are clean.** It accumulates the PR sequence. Workspace builds may be temporarily broken on it between PRs — the per-component gate is what binds intermediate.

## Final integration → main PR

After all per-PR PRs are merged into the integration branch:

1. **Workspace must build clean on the integration branch.** Run the full project CI / test gate on its tip. Fix workspace-level integration issues before opening the final PR.

2. **Open the integration → main PR.** Standard `/review-pipeline` applies end to end: Phase 0 done-check, Phase 1 codex-review, Phase 2 copilot-review, Phase 3 postmortem elevation, Phase 4a description delta.

3. **Final merge after the user-controlled gate.** The user merges; Phase 4b runs post-merge for umbrella drift join if the work referenced a tracking issue.

## Rules

- **Review per-unit, not per-commit.** Many commits are mechanical intermediate steps (file moves, signature substitution, test updates) that draw local nits. A per-unit cumulative review sees the full design surface of the unit and catches findings that span multiple commits (API shape leaking an internal type, a trait with a bypass path).

- **Advance and persist the per-unit baseline.** After each approved unit, the next per-unit review bases on that unit's SHA. Record the last-approved SHA in the tracking memory so the baseline is recoverable across sessions.

- **CI-green + done-check-green ≠ design accepted (phantom acceptance).** Those mean commit-local quality is OK, not that the design is reviewed. A design defect introduced in unit N stays invisible until unit M (M > N) is reviewed, at which point all of N through M must be reconsidered. Per-unit codex review at every unit boundary is the structural fix.

- **The per-PR-open codex review still matters.** It sees the final merge-bound state and catches commit-local issues the per-unit (cumulative-diff) pass missed.

## Skills invoked

- `/implement` — per-commit done-check; per-unit codex review when invoked at a unit boundary (the caller decides the boundary from commit messages or the tracking memory).
- `/review-pipeline` — per-PR-open codex-review onward; the merge target is configured per-PR, so the pipeline needs no integration-branch awareness.
- `/codex-plan-review` — plan-time review before any code, distinct from the per-unit codex review during implementation.

## Memory artifacts

Record at minimum, and include the per-unit codex review step explicitly in the session protocol:

- Working branches (integration branch + current PR branch).
- Latest unit-approved SHA (baseline for the next per-unit review).
- PR sequence with per-PR status (planned / in-progress / merged-to-integration / pending-final).
- Open codex findings carried over (per-unit P1 / P2 deferred with rationale).
