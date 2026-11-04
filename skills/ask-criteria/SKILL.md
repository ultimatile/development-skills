---
name: ask-criteria
description: Single source of truth for when an executing agent asks the user instead of deciding. Skills that cite it apply these criteria by reference.
---

# Ask Criteria (SSOT)

Skills that cite these criteria apply them by reference. Do not copy them into those skills — point at them by name.

## Scope

These criteria govern a decision a run faces at a step that cites them: which route to take, including how far back a return to research goes and what it re-runs; which option to apply; whether to continue.

## Criteria

An approval a skill step requires before an action — **A**, such as filing an issue or making an edit outside the task's scope — is not a decision these criteria govern, and stands as that step states it.

Ask the user when B, C or D holds. Otherwise take the decision, and state it and its basis in the next message to the user.

- **B — the user's intent decides it.** At least one of:

  1. The option the run would take changes what the issue the run holds asks for (with none, the task it was given), brings in something the plan the user approved excludes or defers, or drops something that plan includes; the last two apply when the run holds such a plan.
  2. Nothing the run can read, or find out by a probe it can run, settles the answer, and no option dominates. An option dominates when, in every state the outcome can reach, it is at least as good as every other option on each of truth, usefulness and harm, cost counting as harm.

- **C — what the run decided alone has failed.** At least one of:

  1. `review-pipeline`'s Oscillation detection reaches a topic that an earlier pass of that rule settled without asking.
  2. A review loop a skill step bounds ends because the revisions or iterations it allows have run out, or because it stops at a rejection with no further re-run warranted.

  Stop the procedure that reached C, and present what the run decided and what failed it.

- **D — the run cannot continue.** A step's precondition fails, and no step available to the run restores it.
