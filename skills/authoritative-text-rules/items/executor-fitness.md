# Executor fitness

A step that names its executor promises that executor can perform it. The promise fails when the step demands information the executor is never given, or a judgment nothing in its inputs can settle, or when the condition it turns on cannot be evaluated at all.

**Trigger.** The diff adds, modifies, or removes an authoritative-text step that names who or what executes it — a subagent dispatch, a main-context pass, a command invocation, a lane assignment, or an instruction addressed to a specific reader.

**Sweep.**

1. **List what the step demands** — every input it reads and every judgment it must reach.
2. **Quote what the executor is given.** Find the written definition of the executor's inputs: the prompt that dispatches it, the lane definition that routes to it, the step that resolves its arguments. Quote that text rather than summarizing it.
3. **Compare entry by entry.** Report a demanded input the written definition does not supply, and a demanded judgment that cannot be reached from what it does supply.
4. **Report a circular condition** — one whose evaluation presupposes the output it is being used to produce, so that no order of evaluation settles it.
5. **Hold the standard at the written definition.** Fitness is decided against the text describing the executor's inputs, never against an estimate of the executor's capability. A judgment those inputs support is fit even when it looks demanding; a judgment they do not support is unfit even when the executor could plausibly guess well. An unfitness claim that cannot be stated as "the written inputs do not include X" is not a finding.

**Concern conditions:**

- A step demands an input the written definition of its executor's inputs does not supply
- A step demands a judgment that cannot be reached from those inputs
- A condition's evaluation presupposes its own output

**N/A:** the trigger above does not fire — no authoritative text in the diff has a step that names its executor.

**Tie-breaks.**

- Against `consumer-closure`: this item asks whether the step can be performed; `consumer-closure` asks whether what it produces is received.
- Against `case-space-totality`: a branch the executor cannot evaluate is this item. A branch that is evaluable but covers no case is totality's.
