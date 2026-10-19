# Sentence necessity

**Trigger.** `single-reading`'s trigger.

**Sweep.**

1. Take the sentences `single-reading`'s Sweep takes.
2. Test each against the file with only that sentence removed, and read what remains as a whole, together with the files that file references directly as rule content. Where the sentence sits in a prompt the executor sends to another agent, the executor here is the agent that receives it.
3. The sentence is kept when one of these can be named:
   - an action the executor takes, skips, or takes differently, including the use of an input named in the remaining text, where the sentence excludes that use;
   - the outcome of one case of a split the text makes between cases, where no other branch of that split gives that case an outcome;
   - a judgment a step of the remaining text requires and does not itself settle, whose outcome the sentence can change;
   - a reference in a remaining sentence that loses its antecedent, where that sentence is kept and its chain of such references ends at a sentence kept on a ground of this list other than this one;
   - the identification of one remaining statement of a condition as a copy of another remaining statement.
4. Repeat step 3 on the spans of a kept sentence, a span being a clause or phrase, and quote each span the second concern condition below reports. The deletion carries only the punctuation and agreement it forces.

**Concern conditions:**

- A sentence step 1 takes loses none of step 3's list on deletion
- A span of a kept sentence loses none of step 3's list on deletion

**N/A:** the trigger above does not fire.

**Tie-breaks.**

- Against `case-space-totality`: branches of one split that give a case conflicting outcomes with no stated precedence are that item's.
- Against `clause-composition`: a condition stated in two places is that item's wherever that item is not N/A.
- Against `consumer-closure`: a sentence telling the executor to emit a value is kept here; whether the value is received is `consumer-closure`'s.
- Against `single-reading`: a sentence that loses something under one reading and nothing under another is `single-reading`'s.
