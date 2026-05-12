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

   - If the current branch is the default branch (`main` / `master`), pick a conventional `<type>/<issue#>-<slug>` name based on the issue (e.g., `feat/195-dmrg-envs`, `fix/187-arpack-info`, `chore/<short-slug>`), create it, and proceed. Do not poll the user for the name — branch names are throwaway closed-PR metadata. Announce the chosen name in one line so the user can intervene if they object, then continue without waiting.
   - If the current branch is already a non-default branch, treat it as the intended branch and proceed. Only stop if the branch name plainly contradicts the issue (e.g., on `feat/100-foo` while working #200) — in that case announce the mismatch and ask.

4. Once the branch is settled, record it (and any switch / creation action you took) in the Phase 1 research notes so the implement phase can pick it up unambiguously.

This phase exists to keep direct pushes off the default branch by making the question deterministic at the start of the work. Default → branch automatically; do not block on the user for naming.

## PHASE 1 — RESEARCH

Execute `/research $ARGUMENTS` to investigate the issue and produce an implementation plan.

## PHASE 2 — IMPLEMENT

After Phase 1 completes, execute `/implement $ARGUMENTS` to carry out the plan.
