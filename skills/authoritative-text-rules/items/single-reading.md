# Single reading

An executor acts on the reading it arrives at. Where a sentence admits two readings that lead to different actions, the rule has no determinate content, and the author — who holds the intended reading — is the reader least able to notice.

**Trigger.** The diff adds, modifies, or removes a sentence in authoritative text. Removal counts because deleting a sentence can strand an antecedent or a bound that a surviving sentence relied on.

**Defining predicate.** A sentence fails when a competent executor can extract from it two incompatible readings — readings under which the executor would do different things. Two readings that produce the same action are not a finding.

**Sweep.** Take each added or modified sentence, plus each surviving sentence in the same unit as a removal — the section or numbered step the removed text sat in, not the whole file — and work the search keys below. They are the positions where a second reading recurs, not a closed set; the predicate above decides, and a position not listed here still counts when it admits a divergent reading.

1. **Reference.** For every pronoun and every definite description — "the surface", "the set", "the selection", "its", "that step" — name the antecedent. Report one with no antecedent in the unit, and one with two candidates the syntax does not choose between.
2. **Definition versus example.** For every appositive, parenthetical gloss, or `e.g.`-less list following a term, mark it as fixing the term's meaning or as illustrating it. Report one readable as either, since one reading closes the term and the other leaves it open.
3. **Clause scope.** For every qualifying clause, mark whether it governs the branch it sits in or the whole unit. Report one whose scope is unmarked and where the two scopes differ in effect.
4. **Extent.** For every reference to an extent — "the caveat's own surface", "the touched files", "nearby" — name what bounds it. Report one with no stated bound.
5. **Coordination.** For every `and` or `or` joining more than two elements, or crossing a negation or a modifier, state the grouping. Report one the syntax leaves open.
6. **Attachment.** For every trailing modifier — a relative clause, a participial phrase, a prepositional phrase — name what it attaches to. Report one with more than one available host.
7. **Negation and quantifier scope.** For every `not`, `no`, `every`, `any`, or `only` whose scope over a coordination, a conditional, or another quantifier is not forced by the syntax, state the scope. Report one left open.
8. **Grammatical completeness.** Report a clause left dangling by an edit — a subject with no verb, a conditional with no consequent, a list item whose continuation was severed.

**Concern conditions:**

- An added or modified sentence admits two readings under which the executor would act differently
- A term is introduced by a gloss that is readable as either its definition or an example of it
- A reference has no resolvable antecedent, or an extent has no stated bound

**N/A:** the trigger above does not fire — the diff changes no sentence in authoritative text.

**Tie-breaks.**

- Against `case-space-totality`: this item owns how a sentence reads; totality owns which cases the rule covers once read. Fix the reading first; if a gap remains under every reading, it is totality's.
- Against `clause-composition`: a single sentence readable two ways is this item. Two sentences that are each unambiguous but disagree is `clause-composition`.
