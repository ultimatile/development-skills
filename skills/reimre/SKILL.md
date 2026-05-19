---
name: reimre
description: >
  End-to-end wrapper that runs research-and-implement then review-pipeline
  back to back, closing the manual gap between the two skills so a single
  invocation carries a GitHub issue from initial investigation through PR
  review and the user-controlled merge gate. Use when the user wants the
  full flow on a GitHub issue end to end (e.g., /reimre 42).
---

# reimre

End-to-end wrapper.
Runs `research-and-implement` then `review-pipeline` back to back.
The duplicate `done-check` between the two sub-skills is resolved by suppressing the Phase A side,
leaving `review-pipeline`'s Phase 0 as the single audit gate.

**Issue:** #$ARGUMENTS

## Flow

1. **Phase A** — invoke `research-and-implement $ARGUMENTS`.
   Branch baseline, research, and implementation are handled there.
   **Skip `/implement`'s terminal `/done-check`** — Phase B owns the audit.
2. **Phase B** — invoke `review-pipeline`.
   Its Phase 0 `/done-check` is the first and only audit of the final diff.

Sub-skill internal phases are referenced by name only.
Do not inline their steps, diagrams, or rule lists — they drift when the sub-skill is updated.

## Stop points

Inherits `review-pipeline`'s stop points unchanged — notably the user-controlled **merge gate** between Phase 4a and Phase 4b.
Do not auto-merge.
Plan approval inside `/research` is also unchanged.
