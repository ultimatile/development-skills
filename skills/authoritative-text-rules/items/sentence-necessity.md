# Sentence necessity

**Trigger.** `single-reading`'s trigger.

**Sweep.**

1. Take sentences `single-reading`'s Sweep takes.
2. Test each against the text with only that sentence deleted: what remains of its file together with every file joined to what remains by a rule-content reference, as `clause-composition`'s step 1 finds them. Where the sentence sits in a prompt the executor sends to another agent, the executor here is that prompt's receiver, and the text is that prompt together with the files the prompt tells its receiver to read. A deletion carries only the punctuation and agreement it forces.
3. A sentence or span is kept when a tie-break below keeps it or when deleting it loses one of these:
   - an action the executor takes, skips, or takes differently;
   - a use, excluded by the deleted text, of an input the remaining text names;
   - the outcome of one case of a split the remaining text makes between cases, where no other branch among those the split lists gives that case the same outcome;
   - a judgment a step of the remaining text requires and does not settle, for which the deleted text states a criterion, an instance, or a non-instance that the remaining text does not;
   - the identification of one remaining statement of a condition as a copy of another remaining statement.
4. Repeat steps 2 and 3 on the spans of each kept sentence, a span being any part of it that punctuation sets off and whose deletion leaves the sentence grammatical, and quote each span step 3 does not keep, except one inside a larger span step 3 does not keep.
5. Where deleting together every sentence and span that step 3 does not keep loses one of step 3's list, tested against the text step 2 builds with all of them deleted, report them as one concern in place of the concern conditions.

**Concern conditions:**

- A sentence step 1 takes that step 3 does not keep
- A span step 4 quotes

**N/A:** the trigger does not fire.

**Tie-breaks.**

- Against `clause-composition`: a statement of a condition that another remaining statement also states is kept here. So is a caller's statement of its own response to a state of a unit it invokes, as that item's **Not duplication.** paragraph describes.
- Against `single-reading`: a sentence or span that loses something under one reading of itself or of the remaining text and nothing under another is kept here.
