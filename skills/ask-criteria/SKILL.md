---
name: ask-criteria
description: Single source of truth for when an executing agent asks the user instead of deciding. Skills that reach a decision mid-procedure apply these criteria by reference.
---

# Ask Criteria (SSOT)

Skills that reach a decision mid-procedure apply the criteria below by reference. Do not copy them into those skills — point at them by name.

## Scope

These criteria govern a decision a run faces: which route to take, including how far back a return to research goes and what it re-runs; which option to apply; whether to continue. An approval a skill step requires before an action — **A**, such as filing an issue or making an edit outside the task's scope — is not such a decision, and stands as that step states it.

## Criteria

Ask the user when B, C or D holds. Otherwise take the decision, and state it and its basis in the next message to the user.

- **B — the user's intent decides it.** At least one of:

  1. The option the run would take changes what the issue asks for (with no issue, the task), brings in something the last plan the user approved excludes or defers, or drops something it includes.
  2. Nothing the run can read settles the answer, and no option dominates. An option dominates when, in every state the outcome can reach, it is at least as good as every other option for truth, usefulness and harm.

- **C — what the run decided alone has failed.** At least one of:

  1. A plan revision, as `research` defines it, would replace one the user did not approve.
  2. `review-pipeline`'s Oscillation detection reaches a topic to which an earlier pass of that rule applied a fix option.
  3. A review loop a skill step bounds ends without the reviewer's approval: the revisions or iterations it allows have run out, or it stops at a rejection with no further re-run warranted.

  Stop, and present what the run decided and what failed it.

- **D — the run cannot continue.** A step's precondition fails, and no step available to the run restores it.
