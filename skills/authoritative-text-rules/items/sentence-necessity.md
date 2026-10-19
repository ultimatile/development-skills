# Sentence necessity

**Trigger.** `single-reading`'s trigger.

**Sweep.**

1. Take sentences `single-reading`'s Sweep takes.
2. Test each against the text with only that sentence deleted: what remains of its file together with every file joined to what remains by a rule-content reference, as `clause-composition`'s step 1 finds them. Where the sentence sits in a prompt the executor sends to another agent, the executor here is that prompt's receiver, and the text is that prompt together with the files the prompt tells its receiver to read. A deletion carries only the punctuation and agreement it forces.
3. A sentence or span is kept when a tie-break below keeps it or when deleting it loses one of these:
   - an action the executor takes, skips, or takes differently, including the use of an input named in the remaining text, where the deleted text excludes that use;
   - the outcome of one case of a split the remaining text makes between cases, where no other branch among those the split lists gives that case the same outcome;
   - a judgment a step of the remaining text requires and does not settle, for which the deleted text states a criterion, an instance, or a non-instance that the remaining text does not;
   - the identification of one remaining statement of a condition as a copy of another remaining statement.
4. Repeat steps 2 and 3 on the spans of each kept sentence, a span being any part of it that punctuation sets off and whose deletion leaves the sentence grammatical, and quote each span the second concern condition reports that no larger reported span contains.
5. Where deleting together every sentence and span that step 3 does not keep and no tie-break assigns to another item loses one of step 3's list, tested against the texts step 2 names for them, report them as one concern in place of the concern conditions. Its response is deleting them one at a time in text order, testing each against the text as it then stands, and keeping any that step 3 then keeps.

**Concern conditions:**

- A sentence step 1 takes that step 3 does not keep
- A span step 4 tests that step 3 does not keep

**N/A:** the trigger does not fire.

**Tie-breaks.**

- Against `clause-composition`: a pair of statements that item reports as drift-prone duplication is that item's, and a caller's statement of its own response to a state of a unit it invokes, as that item's Not-duplication paragraph describes, is kept.
- Against `single-reading`: a sentence or span that loses something under one reading of itself or of the remaining text and nothing under another is `single-reading`'s where that item reports it, and is kept otherwise.
