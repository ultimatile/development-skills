---
name: research-and-implement-egel
description: >
  Implement a GitHub issue in two structured phases — research-eg first, then
  implement-el. Wraps the evidence-gated-review and execution-loop skills end
  to end with branch baseline, GitHub integration, and four-state hypothesis
  decisions. Use when the user wants to work on a GitHub issue end to end
  (e.g., /research-and-implement-egel 42) and prefers the disconfirming-probe
  discipline over the legacy /research-and-implement skill.
---

# research-and-implement-egel

End-to-end wrapper. Runs `research-eg` (Phase 1) and `implement-el`
(Phase 2) in sequence, with a branch baseline gate up front.

**Issue:** #$ARGUMENTS

## PHASE 0 — BRANCH BASELINE

Before research begins, settle the working branch.

1. Check current branch: `git branch --show-current`
2. Determine default branch: `git symbolic-ref --short
   refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@'`
3. **Decision gate**:
   - On default branch → pick a conventional `<type>/<issue#>-<slug>`
     (`feat/195-dmrg-envs`, `fix/187-arpack-info`, `chore/<slug>`),
     create it, and proceed. Do not poll the user for the name —
     branch names are throwaway closed-PR metadata. Announce the
     chosen name in one line so the user can intervene if they
     object, then continue without waiting.
   - On a non-default branch → treat it as the intended branch and
     proceed. Only stop if the branch name plainly contradicts the
     issue (e.g., on `feat/100-foo` while working #200) — in that
     case announce the mismatch and ask.
4. Once the branch is settled, record it (and any switch / creation
   action) so Phase 2 can pick it up unambiguously.

This phase exists to keep direct pushes off the default branch by
making the question deterministic at the start. Default → branch
automatically; do not block on the user for naming.

## PHASE 1 — RESEARCH

Execute `/research-eg $ARGUMENTS`.

The plan posted to the issue MUST include the `Inconclusive / Deferred
items` section (or `Inconclusive / Deferred items: none identified`).
This section is the discovery contract Phase 2 will enforce.

`/research-eg` runs the mandatory `codex-plan-review` gate at its
Step 3.5 — before user approval and before the plan is posted to
GitHub. No separate review phase is needed here; revisions resulting
from review land in the plan that Step 5 posts, so the issue trail
shows a single reviewed plan rather than a post-then-revise sequence.

## PHASE 2 — IMPLEMENT

After Phase 1 settles and the user approves the (possibly review-
revised) plan, execute `/implement-el $ARGUMENTS`.

Phase 2 will halt rather than ad-hoc-patch any mid-implementation
discovery that is not listed in the plan's discovery contract. If that
happens, return to Phase 1 (or update the plan explicitly) before
resuming.
