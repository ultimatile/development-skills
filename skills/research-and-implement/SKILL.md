---
name: research-and-implement
description: Work a GitHub issue end to end in two phases — research, then implement — under quaere-evidence and quaere-execution discipline.
---

# research-and-implement

End-to-end wrapper. Runs `research` (Phase 1) and `implement` (Phase 2) in sequence, with a branch and root baseline gate up front.

**Issue:** #$ARGUMENTS

## PHASE 0 — BRANCH AND ROOT BASELINE

Before research begins, settle the working branch and the root the change will be measured from.

1. Check current branch: `git branch --show-current`
2. Determine the default branch as `diff-root` directs; step 3 compares the current branch against it.
3. **Decision gate**:
   - On default branch → pick a conventional `<type>/<issue#>-<slug>` (`feat/195-dmrg-envs`, `fix/187-arpack-info`, `chore/<slug>`), create it, and proceed. Do not poll the user for the name — branch names are throwaway closed-PR metadata. Announce the chosen name in one line so the user can intervene if they object, then continue without waiting.
   - On a non-default branch → treat it as the intended branch and proceed. Only stop if the branch name plainly contradicts the issue (e.g., on `feat/100-foo` while working #200) — in that case announce the mismatch and ask.
4. Once the branch is settled, record it (and any switch / creation action) so Phase 2 can pick it up unambiguously.
5. **Settle the root**, on `diff-root`'s terms: the branch this work merges into, as a bare branch name. The ref step 3 cut the branch from is not it — a local branch is routinely ahead of or behind what the work will merge into, and commits inherited that way must stay in every gate's scope because they land through the same PR. Take a root the caller supplied; with none, ask. Record it beside the branch, and state it: Phase 2 passes it on, and a caller continuing past this skill needs it for its own gates.

This phase exists to keep direct pushes off the default branch, and to keep every later gate measuring from the ref the work is actually against, by making both questions deterministic at the start. Default → branch automatically; do not block on the user for naming.

## PHASE 1 — RESEARCH

Execute `/research $ARGUMENTS`.

The plan posted to the issue MUST include the `Inconclusive / Deferred items` section (or `Inconclusive / Deferred items: none identified`). This section is the discovery contract Phase 2 will enforce.

## PHASE 2 — IMPLEMENT

After Phase 1 settles and the user approves the (possibly review-revised) plan, execute `/implement $ARGUMENTS`, supplying the root Phase 0 settled.

Phase 2 will halt rather than ad-hoc-patch any mid-implementation discovery that is not listed in the plan's discovery contract. If that happens, return to Phase 1 (or update the plan explicitly) before resuming.
