---
name: ask-criteria
description: Single source of truth for when an executing agent asks the user instead of deciding. Skills that reach a decision mid-procedure apply these criteria by reference.
---

# Ask Criteria (SSOT)

Skills that reach a decision mid-procedure apply the criteria below by reference. Do not copy them into those skills — point at them by name.

## Scope

These criteria govern a decision a run faces: which route to take, including how far back a return to research goes and what it re-runs; which option to apply; whether to continue. An approval a skill step requires before an action is not such a decision, and stands as that step states it.

## Criteria

Ask the user when B, C or F holds. Otherwise take the decision, and state it and its basis in the next message to the user.

- **B — the user's intent decides it.** At least one of:

  1. Proceeding changes what the issue asks for, or brings in something the last plan the user approved excludes or defers.
  2. Nothing the run can read settles the answer, and no option dominates. An option dominates when, in every state the outcome can reach, it is at least as good as every other option for truth, usefulness and harm.

- **C — what the run decided alone has failed.** At least one of:

  1. A plan revision would follow one the user did not approve.
  2. `review-pipeline`'s Oscillation detection reaches a topic the run has already settled there.
  3. The revisions or iterations a skill step allows have run out, and that step escalates.

  Stop, and present what the run decided and what failed it.

- **F — the run cannot continue.** A step's precondition fails, and no step available to the run restores it.
