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
   - On default branch → **stop and propose a feature branch**
     (`feat/195-dmrg-envs`, `fix/187-arpack-info`, `chore/<slug>`).
     Wait for explicit approval before creating.
   - On a non-default branch → confirm with the user that this is the
     intended branch (it may be a leftover). Proceed only after
     confirmation.
4. Once the branch is settled, record it (and any switch / creation
   action) so Phase 2 can pick it up unambiguously.

This phase exists to keep direct pushes off the default branch by
making the question deterministic at the start, not a remembered
behavioral rule. Default → branch unless the user explicitly waives.

## PHASE 1 — RESEARCH

Execute `/research-eg $ARGUMENTS`.

The plan posted to the issue MUST include the `Inconclusive / Deferred
items` section (or `Inconclusive / Deferred items: none identified`).
This section is the discovery contract Phase 2 will enforce.

## PHASE 2 — IMPLEMENT

After Phase 1 completes and the user approves the plan, execute
`/implement-el $ARGUMENTS`.

Phase 2 will halt rather than ad-hoc-patch any mid-implementation
discovery that is not listed in the plan's discovery contract. If that
happens, return to Phase 1 (or update the plan explicitly) before
resuming.
