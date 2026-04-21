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

## PHASE 1 — RESEARCH

Execute `/research $ARGUMENTS` to investigate the issue and produce an implementation plan.

## PHASE 2 — IMPLEMENT

After Phase 1 completes, execute `/implement $ARGUMENTS` to carry out the plan.
