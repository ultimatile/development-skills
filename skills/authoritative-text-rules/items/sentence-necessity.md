# Sentence necessity

**Trigger.** `single-reading`'s trigger.

**Sweep.**

1. Take sentences `single-reading`'s Sweep takes.
2. Test each against the text with only that sentence deleted: what remains of its file together with the files that remaining text references directly as rule content. Where the sentence sits in a prompt the executor sends to another agent, the executor in this step and in step 3 is that prompt's receiver, and the text is that prompt together with the files the prompt tells its receiver to read. A deletion carries only the punctuation and agreement it forces.
3. A sentence or span is kept when a tie-break below keeps it or when deleting it loses one of these, for the executor, with step 2's text as the remaining text, or for the executor of a file referencing the deleted text's file as rule content, found as `clause-composition`'s step 1 finds inbound references, with that file and step 2's text as the remaining text:
   - an action the executor takes, skips, or takes differently;
   - a use, excluded by the deleted text, of an input the remaining text names;
   - the outcome of one case of a split the remaining text makes between cases, where no other branch among those the split lists gives that case the same outcome;
   - a judgment a step of the remaining text requires and does not settle, for which the deleted text states a criterion, an instance, or a non-instance that the remaining text does not;
   - the identification of one remaining statement of a condition as a copy of another remaining statement;
   - the application, to the step holding the deleted text, of a remaining statement elsewhere that the deleted text names.
4. Repeat steps 2 and 3 on the spans of each kept sentence, a span being any part of it that punctuation sets off and whose deletion leaves the sentence grammatical, and quote each span step 3 does not keep, except one inside a larger span step 3 does not keep.
5. Apply steps 2 and 3 to each set of sentences and spans that step 3 does not keep, deleting the whole set at once from the files holding its members and building step 2's text around all of those files. Report each set step 3 keeps that has no proper subset step 3 keeps, in place of the other concern conditions for its members.

**Concern conditions:**

- A sentence step 1 takes that step 3 does not keep, quoted
- A span step 4 quotes
- A set step 5 reports

**N/A:** the trigger does not fire.

**Tie-breaks.**

- Against `clause-composition`: a statement that restates, in full or in part, a condition another remaining statement states is kept here. So is a caller's statement of its own response to a state of a unit it invokes, as that item's **Not duplication.** paragraph describes.
- Against `single-reading`: a sentence or span that loses something under one reading of itself or of the remaining text and nothing under another is kept here.
