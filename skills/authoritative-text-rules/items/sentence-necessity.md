# Sentence necessity

**Trigger.** The diff adds, modifies, or removes a sentence in authoritative text.

**Sweep.**

1. **Take the sentences.** Each added or modified sentence, plus each surviving sentence in the same unit as a removal. The unit is the innermost heading section or numbered step holding the sentence; where the removal took a whole section, the unit is its parent.
2. **Delete one sentence at a time.** Test each against the file with only that sentence removed, and read what remains as a whole, together with the files it references. Where the sentence sits in text the executor passes verbatim to another agent, the executor here is that agent.
3. **Name what the deletion loses.** The sentence is kept when one of these can be named:
   - an action the executor takes, skips, or takes differently, including a use of an input the remaining text names that the sentence excludes;
   - the only outcome its unit gives a case the unit distinguishes, no action included;
   - a judgment a step of the remaining text requires and does not itself settle, whose outcome the sentence can change;
   - a reference in a remaining sentence that loses its antecedent, where that sentence is kept and its chain of such references ends at a sentence kept on one of the three grounds above;
   - the naming of the statement that a remaining copy of a condition duplicates, where that statement remains too.
4. **Repeat step 3 on the spans of a kept sentence.** A clause or phrase whose deletion loses none of the above is reported for deletion by quoting it. The deletion carries only the punctuation and agreement it forces; a rewording beyond that is not a finding.

**Concern conditions:**

- A sentence step 1 takes loses none of step 3's list on deletion
- A span of a kept sentence loses none of step 3's list on deletion

**N/A:** the trigger above does not fire.

**Tie-breaks.**

- Against `clause-composition`: a condition, obligation, or prohibition stated in two places is that item's.
- Against `consumer-closure`: a sentence telling the executor to emit a value is kept here; whether the value is received is `consumer-closure`'s.
- Against `single-reading`: a sentence that loses something under one reading and nothing under another is `single-reading`'s.
