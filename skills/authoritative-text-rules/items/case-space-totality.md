# Case-space totality

Rule text that maps conditions to outcomes is read as a function: an executor arrives with a case and must leave with exactly one outcome. A case that reaches no outcome stalls the executor; a case that reaches two leaves the choice to whoever runs it, which is the same as leaving it undefined.

**Trigger.** The diff adds, modifies, or removes authoritative text that maps a condition to an outcome. Recurring instances: a trigger, an N/A criterion, a concern condition, a branch table, a guarded step, a routing rule, a status vocabulary, a precedence statement. Removal counts because deleting a branch can leave the cases it covered with none.

**Sweep.**

1. **Name the declared domain.** Take it from the rule's own trigger or scope sentence — the set of inputs it says it ranges over. When that domain is intensional or unbounded, do not enumerate it: partition it by the axes the rule itself branches on, and take the cells of that partition as the case set. An axis the rule never branches on cannot produce an undefined cell, so adding one manufactures findings rather than exposing them.
2. **Map each case to the branch that fires on it.** Work from the literal branch conditions, not from what the branch was evidently meant to catch.
3. **Report each of the following that the mapping exposes:**
   - a case matching no branch, where the text states no default;
   - a case matching two or more branches that assign different outcomes, where the text states no precedence;
   - a mirrored case treated on one side only. Two cases are mirrors when one is obtained from the other by inverting a binary axis the rule itself names — the two directions of a change, the two halves of a declared split, the two members of a named pair. An asymmetry the text gives a reason for is not a finding;
   - a proposition about the domain that the enumeration relies on and that is untrue — which constructs of a language can raise, which paths a glob matches, what a named file or clause actually says. Check these against the domain itself, not against the rest of the rule. A proposition that can only be settled by running something is outside this sweep, which reads text.

**Concern conditions:**

- A case in the declared domain reaches no outcome, and no default covers it
- A case reaches two or more conflicting outcomes with no stated precedence
- One member of a mirrored pair is treated and the other is neither treated nor excluded with a reason
- The enumeration rests on a proposition about the domain that is false

**N/A:** the trigger above does not fire — no authoritative text in the diff maps a condition to an outcome.

**Tie-breaks.**

- Against `single-reading`: if the gap disappears under one admissible reading of the sentence, the defect is the ambiguity — report it there. If the gap survives every admissible reading, report it here.
- Against `clause-composition`: two branches of the *same* unit both firing with no stated precedence is this item, because that unit's map is not single-valued. Two clauses in *different* units disagreeing is `clause-composition`.
