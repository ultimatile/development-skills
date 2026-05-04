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

## PHASE 1.5 — PLAN REVIEW GATE (mandatory)

Plan review is consistently mishandled when left to ad-hoc judgement —
trivial changes skip it (fine), risky changes also skip it (not fine),
and the decision is made on the basis of how confident the plan author
feels rather than how exposed the plan is. The gate makes the decision
deterministic.

After the plan is posted in Phase 1 and before implementation begins:

1. **Always offer `codex-plan-review`** — never silently skip. Phrase it
   as a recommendation, not a question:

   > "Plan posted. Recommend running `/codex-plan-review` before
   > implementation; type `skip` to bypass, or anything else to run it."

   Bypassing is a deliberate user choice, not the default.

2. **If review runs**: triage the findings.
   - **Implementation concerns** (algorithm details, error handling,
     test coverage gaps, naming): patch the plan in place, post a
     short revision comment to the issue, and proceed to Phase 2.
   - **Premise concerns** (the assumed root cause may be wrong, the
     described mechanism doesn't match how the code actually fails,
     a fixture's claimed properties may not hold, an "obvious"
     derivation is unproven): **re-enter `/research-eg` from Step 1**.
     Do not patch the plan in place — the hypothesis set itself is
     suspect, and incremental edits perpetuate the bad premise across
     iterations.

   Distinguishing the two: an implementation concern asks "given the
   plan's assumptions, is the proposed approach sound?"; a premise
   concern asks "are the plan's assumptions actually true?". If the
   reviewer would have given a different answer with empirical
   evidence in hand, it's a premise concern.

3. **If a plan revision results from review** (either lane), the
   revised plan is the new contract. Re-post it as a fresh comment
   on the issue (not an edit) so the discovery contract trail is
   auditable. If `/research-eg` was re-entered, it overwrites the
   prior plan automatically per its own Step 5 rules.

The cost of running `codex-plan-review` once per cycle is minutes; the
cost of carrying a wrong-premise plan through implementation is
hours-to-days of rework. Bias toward running it.

## PHASE 2 — IMPLEMENT

After Phase 1.5 settles and the user approves the (possibly revised)
plan, execute `/implement-el $ARGUMENTS`.

Phase 2 will halt rather than ad-hoc-patch any mid-implementation
discovery that is not listed in the plan's discovery contract. If that
happens, return to Phase 1 (or update the plan explicitly) before
resuming.
