---
name: land-via-integration-branch
description: >-
  Land a large change too big for one PR as a sequence of PRs merging into a
  long-lived integration branch, then a final PR into main. Use when one PR
  would exceed a reviewer's diff-size limit, or when multiple components' APIs
  must migrate together (cross-component migration, large refactor, multi-PR
  feature).
---

# Land via Integration Branch

A five-gate review cadence for landing a large change that does not fit a single PR, through a long-lived integration branch.

| Gate | Trigger | Action | Baseline |
| -- | -- | -- | -- |
| per-commit | each `git commit` | `/done-check` (preflight `/todo-check`) | the PR's base |
| per-unit | unit / design-boundary completion | `codex exec review --base <last-approved-SHA>` | last unit-approved SHA |
| pre-open code-review | per PR, before the per-PR-open gate | `/code-review-gate`, via `/review-pipeline` Phase 0.5 | integration branch |
| per-PR-open | PR creation | `/codex-review` against PR diff | PR base (integration branch) |
| per-PR-review | PR open on GitHub | `/copilot-review` + reply / fix loop | PR head |

The Baseline column is the authority on what each gate measures from, and the workflow steps below are what pass each cell to its gate. The cells split by `diff-root`'s two kinds of gate:

- **PR-scope** — per-commit, pre-open code-review, per-PR-open, per-PR-review. Their baseline is the branch the PR merges into, which is also the PR's own base: `integration/<issue#>-<slug>` for every per-PR PR, the default branch for the final one. One value per PR, fixed for its whole life, so each of these gates re-covers everything the PR will merge. Coverage is theirs.
- **Incremental** — the per-unit review. Its baseline advances to the last approved SHA after each unit, so it reviews less on purpose: it exists for early feedback on the design surface of one unit and establishes no coverage. The final integration → main section runs its per-commit audit incrementally too, for the reason stated there.

Do not make the per-commit audit advance with the work. Re-covering the accumulated PR diff at every commit is what makes it a coverage gate; an advancing baseline would leave each earlier commit covered only by the per-PR-open gate, and a PR that never reaches that gate uncovered entirely.

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

2. **Implement units inside the branch.** Run `/implement` with `integration/<issue#>-<slug>` as the root, once for the whole PR: its `/todo-check` preflight and per-commit `/done-check` are coverage gates, so that root stays fixed and each audit re-covers the PR's accumulated diff. Each commit goes through per-commit `/done-check`. At each unit boundary, run per-unit codex review against the last approved SHA:

   ```bash
   codex exec review --base <last-unit-approve-SHA> -o /tmp/codex-unit-<k>.<u>.md
   ```

   The baseline starts as the integration branch tip when PR `k` begins; advance it to the last approved SHA after each unit. Triage P1 / P2 findings at this gate before continuing to the next unit.

   **Committing past a workspace-wide pre-commit hook.** A hook that lints the whole workspace (e.g. a project-wide type/lint check) will fail by design on a `pr<k>/...` branch — downstream components scheduled for a later PR are still on the old API. Skip only that one workspace-coherence hook (e.g. `SKIP=<workspace-lint-hook> git commit ...`) after confirming the per-component test and lint gates both pass, and note the skip rationale in the commit body. Do NOT use `--no-verify`; it also drops formatting and line-count hooks, which remain binding.

3. **Open the PR against the integration branch.** Run `/review-pipeline` from Phase 0.5 forward (code-review gate, then codex-review, then copilot-review), supplying `integration/<issue#>-<slug>` as its root — the pipeline opens the PR against that same branch. Do not open the PR here: the pipeline's Phase 2 owns PR creation, and `/copilot-review` rejects a PR created separately.

4. **Merge into the integration branch when reviews are clean.** Workspace builds may be temporarily broken on it between PRs — the per-component gate is what binds intermediate.

## Final integration → main PR

After all per-PR PRs are merged into the integration branch:

1. **Workspace must build clean on the integration branch.** Run the full project CI / test gate on its tip. Fix workspace-level integration issues before opening the final PR. Those fixes are committed on the integration branch itself. Capture its tip SHA before the first fix commit — the branch ref advances with that commit, so the name stops naming this point — and use that SHA as the root for their per-commit `/done-check`, which is the commit-root case `diff-root` defines for an incremental gate that audits the fixes and not the per-PR work already merged and reviewed below them. Step 2's pipeline is the PR-scope gate that covers the whole merge-bound diff.

2. **Open the integration → main PR.** Standard `/review-pipeline` applies end to end, with the repository default branch as its root: Phase 0 done-check, Phase 0.5 code-review gate, Phase 1 codex-review, Phase 2 copilot-review, Phase 3 postmortem elevation, Phase 4a description delta. This is the second of the two points at which this skill enters the pipeline, and the two are separate runs, so each declares its own root.

3. **Final merge after the user-controlled gate.** The user merges; Phase 4b runs post-merge for umbrella drift join if the work referenced a tracking issue.

## Rules

- **Review per-unit, not per-commit.** Many commits are mechanical intermediate steps (file moves, signature substitution, test updates) that draw local nits. A per-unit cumulative review sees the full design surface of the unit and catches findings that span multiple commits (API shape leaking an internal type, a trait with a bypass path).

- **Advance and persist the per-unit baseline.** After each approved unit, the next per-unit review bases on that unit's SHA. Record the last-approved SHA in the tracking memory.

- **CI-green + done-check-green ≠ design accepted (phantom acceptance).** Those mean commit-local quality is OK, not that the design is reviewed. A design defect introduced in unit N stays invisible until unit M (M > N) is reviewed, at which point all of N through M must be reconsidered. Per-unit codex review at every unit boundary is the structural fix.

- **The per-PR-open codex review still matters.** It sees the final merge-bound state and catches commit-local issues the per-unit (cumulative-diff) pass missed.

## Skills invoked

- `/implement` — per-commit done-check; per-unit codex review when invoked at a unit boundary (the caller decides the boundary from commit messages or the tracking memory).
- `/review-pipeline` — per-PR from Phase 0.5 forward, and the final integration → main PR end to end.
- `/codex-plan-review` — plan-time review before any code, distinct from the per-unit codex review during implementation.

## Memory artifacts

Record at minimum, and include the per-unit codex review step explicitly in the session protocol:

- Working branches (integration branch + current PR branch).
- Latest unit-approved SHA (baseline for the next per-unit review).
- Integration branch tip SHA captured on entering the final integration → main section (root for that section's per-commit audits).
- PR sequence with per-PR status (planned / in-progress / merged-to-integration / pending-final).
- Open codex findings carried over (per-unit P1 / P2 deferred with rationale).
