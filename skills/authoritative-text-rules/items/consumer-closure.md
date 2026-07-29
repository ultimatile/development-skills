# Consumer closure

A value the rule tells its executor to produce is only worth producing if some step accepts it, and an obligation the rule imposes is only dischargeable if something ends it and something receives its result. A verdict outside the consumer's vocabulary and a task with no receiver both fail silently: the executor does the work and nothing happens.

**Trigger.** The diff adds, modifies, or removes authoritative text that emits a value or imposes an obligation. Recurring instances: a verdict token, a status, a disposition, a row, a named field, a return shape, an instruction whose result another step is expected to use.

**Sweep.**

1. **Freeze the set before tracing anything.** Read the audited text through once and write down every emitted value and every obligation it holds. Extract by these categories:

   - an **emitted value** is any token the text tells its executor to produce or record — a verdict, a status, a disposition, a named field, a table cell, a row;
   - an **obligation** is any imperative addressed to the executor whose result another step is expected to consume. An imperative whose result nothing else consumes is an ordinary step, not an obligation, and stays out of this item.

   Both categories are frozen together at this step. Trace only the frozen list: text written to discharge any entry — a value or an obligation — does not join it, so the traversal ends.

2. **For each emitted value, find the consuming step** and confirm the value is in the vocabulary that step accepts. A step that branches on a fixed set of tokens accepts exactly those tokens; a value outside the set is unreceived even when its meaning is obvious.

3. **For each obligation, name two things** — its termination bound, the condition that makes it finish, and its receiver, the step that consumes its result. Report an obligation missing either.

**Concern conditions:**

- An emitted value is not in the vocabulary of the step that consumes it
- An emitted value has no consuming step at all
- An obligation has no stated termination bound, or no step that receives its result

**N/A:** the trigger above does not fire — no authoritative text in the diff emits a value or imposes an obligation.

**Self-application.** The sweep instructions in this item are addressed to the auditor running it and terminate at the row that auditor returns. They are not entries in the frozen set of step 1, and auditing them is out of scope.

**Tie-breaks.**

- Against `executor-fitness`: that item asks whether a step's inputs let it run; this one asks whether its outputs land.
- Against `case-space-totality`: a vocabulary whose members are each received, but which leaves some case unable to produce any member, is totality's.
- Against `single-reading`: if the consuming step is identified, or the value falls inside its vocabulary, under one admissible reading, the defect is the ambiguity — report it there. If no reading lands the value, it is unreceived and this item's.
- Against `clause-composition`: compose the clauses before deciding. A value still unreceived once they are composed — no consuming step, or one whose vocabulary excludes it — is this item's. A receiver one clause establishes and another suppresses or contradicts is `clause-composition`'s.
