---
name: reimrecr
description: End-to-end wrapper running research-and-implement then review-pipeline-coderabbit on a GitHub issue, carrying it from investigation through the user-controlled merge gate.
---

# reimrecr

End-to-end wrapper.
Runs `research-and-implement` then `review-pipeline-coderabbit` back to back.

**Issue:** #$ARGUMENTS

## Flow

1. **Phase A** — invoke `research-and-implement $ARGUMENTS`.
   Branch baseline, research, and implementation are handled there.
   **Skip `/implement`'s terminal `/done-check`** — Phase B owns the audit.
2. **Phase B** — invoke `review-pipeline-coderabbit`.

Sub-skill internal phases are referenced by name only.
Do not inline their steps, diagrams, or rule lists — they drift when the sub-skill is updated.

## Stop points

Inherits `review-pipeline-coderabbit`'s stop points unchanged — notably the user-controlled **merge gate** between Phase 4a and Phase 4b.
Do not auto-merge.
Plan approval inside `/research` is also unchanged.
