---
name: research-and-implement
description: >
  Implement a GitHub issue in two structured phases — Research first, then Implement.
  Use this skill whenever the user wants to work on a GitHub issue, implement a feature from an issue,
  fix a bug described in an issue, or says things like "implement issue #N", "work on #N",
  "let's tackle issue N", or references a GitHub issue number for implementation.
  Accepts an issue number as an argument (e.g., /research-and-implement 42).
---

# research-and-implement

Implement a GitHub issue in two phases: Research, then Implement.

**Issue:** #$ARGUMENTS

## PHASE 0 — BRANCH BASELINE

Before research begins, establish the working branch.

1. Check the current branch:

   ```bash
   git branch --show-current
   ```

2. Determine the repo's default branch (usually `main` or `master`):

   ```bash
   git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null \
     | sed 's@^origin/@@'
   ```

3. **Decision gate:**

   - If the current branch is the default branch (`main` / `master`),
     **stop and propose a feature branch** to the user. Do not start
     research on the default branch. Suggest a name based on the
     issue (e.g., `feat/195-dmrg-envs`, `fix/187-arpack-info`,
     `chore/<short-slug>`). Wait for explicit user approval before
     creating the branch.
   - If the current branch is already a non-default branch, confirm
     with the user that this is the intended branch for the issue
     (it may be a leftover from prior work). Proceed only after
     confirmation.

4. Once the branch is settled, record it (and any switch / creation
   action you took) in the Phase 1 research notes so the implement
   phase can pick it up unambiguously.

This phase exists to keep direct pushes off the default branch by
making the question deterministic at the start of the work, not a
remembered behavioral rule. Default → branch unless the user
explicitly waives.

## PHASE 1 — RESEARCH

Execute `/research $ARGUMENTS` to investigate the issue and produce an implementation plan.

## PHASE 2 — IMPLEMENT

After Phase 1 completes, execute `/implement $ARGUMENTS` to carry out the plan.
