# Sentence necessity

**Trigger.** `single-reading`'s trigger.

**Sweep.**

1. Take the sentences `single-reading`'s Sweep takes.
2. Test them in file order, each against the file with the tested text and everything this sweep has already reported removed, and read what remains as a whole, together with the files that file references directly as rule content. Where the tested text sits in a prompt the executor sends to another agent, the executor here is that prompt's receiver, and what remains is that prompt together with the files the prompt tells its receiver to read.
3. A sentence or span is kept when one of these can be named:
   - an action the executor takes, skips, or takes differently, including the use of an input named in the remaining text, where the tested text excludes that use;
   - the outcome of one case of a split the text makes between cases, where no other branch of that split gives that case an outcome;
   - a judgment a step of the remaining text requires and does not itself settle, whose outcome the tested text can change;
   - the identification of one remaining statement of a condition as a copy of another remaining statement.
4. Once every sentence has been tested, repeat steps 2 and 3 on the spans of each kept sentence, a span being a clause or phrase, and quote each span the second concern condition below reports. The deletion carries only the punctuation and agreement it forces.

**Concern conditions:**

- A sentence step 1 takes loses none of step 3's list on deletion
- A span of a kept sentence loses none of step 3's list on deletion

**N/A:** the trigger above does not fire.

**Tie-breaks.**

- Against `case-space-totality`: branches of one split that give a case conflicting outcomes with no stated precedence are that item's.
- Against `clause-composition`: a condition stated in two places is that item's wherever that item is not N/A.
- Against `single-reading`: a sentence that loses something under one reading and nothing under another is `single-reading`'s.
