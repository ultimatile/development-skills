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
Runs `research-and-implement` then `review-pipeline` back to back,
with one seam rule so the duplicate `done-check` is skipped automatically.

**Issue:** #$ARGUMENTS

## Flow

1. **Phase A** — invoke `research-and-implement $ARGUMENTS`.
   Branch baseline, research, and implementation are handled there.
   `/implement`'s terminal step runs `/done-check` on the final diff.
2. **Phase B** — invoke `review-pipeline`, applying the seam rule below.

Sub-skill internal phases are referenced by name only.
Do not inline their steps, diagrams, or rule lists — they drift when the sub-skill is updated.

## Seam rule (Phase A → Phase B)

`/implement` runs `/done-check` on the same diff that `review-pipeline` Phase 0 would re-audit.
Detect freshness automatically and skip Phase 0 when the diff is unchanged.
No user prompt.

Detection:

```bash
git status --porcelain
```

Capture the snapshot at the end of Phase A.
Re-capture at the start of Phase B.
If the two outputs are byte-identical, start `review-pipeline` at **Phase 1 (codex review loop)** and skip its Phase 0.
Any difference (staged, unstaged, or untracked) invalidates freshness — start `review-pipeline` from Phase 0.

The rule is an invariant on diff freshness, not a hardcoded step skip,
so it stays correct if either sub-skill renumbers its phases.

## Stop points

Inherits `review-pipeline`'s stop points unchanged — notably the user-controlled **merge gate** between Phase 4a and Phase 4b.
Do not auto-merge.
Plan approval inside `/research` is also unchanged.
