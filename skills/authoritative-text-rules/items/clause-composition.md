# Clause composition

A rule set is executed as a whole, so a clause is correct only in company. Two clauses can each be right and still leave the executor with conflicting instructions, or with one instruction suppressed by another, or with one condition maintained in two places that drift apart.

**Trigger.** The diff adds, modifies, or removes an authoritative-text clause stating a condition, an obligation, or a prohibition, in a rule set holding more than one unit.

**Sweep.**

1. **Fix the rule set.** It is the authoritative-text files the diff touches, plus every file joined to them by a rule-content reference in **either** direction: the ones they reference — an index they read, an item body they dispatch on, a definition file they point at by name — and the ones that reference them. Traverse inbound too, because references run runner-to-rule: an item body names no runner, so an outbound-only rule set makes every item-only diff a single unit and hides exactly the runner-versus-item conflict this item exists to catch. Find the inbound side by searching the tree for the changed file's path and slug. A file merely mentioned in passing is not rule content.
2. **Derive the search keys from the clause's own terms.** Take its subject, its governing verb, and every artifact, step, or status token it names. Search on the named artifacts rather than on the clause's phrasing: a condition restated in different words still has to mention the things it constrains, so the artifact names find it where the wording does not.
3. **Read every hit and classify it:**
   - **contradiction** — the two clauses assign incompatible outcomes to a case both cover;
   - **shadowing** — one clause sits at a scope that suppresses the other for cases the other was meant to cover, typically an item-level statement placed where it reads as branch-level or the reverse;
   - **drift-prone duplication** — the same condition stated in two places, either of which can be edited without the other.
4. **Resolve duplication by pointing, not by synchronizing.** Keep one statement and have the other refer to it. Two copies kept accurate today are the defect, not the difference between them.

**Concern conditions:**

- Two clauses of the rule set assign incompatible outcomes to a case both cover, with no stated precedence
- A clause is stated at a scope that suppresses another clause for cases that other clause was meant to cover
- One condition is stated in two places, either editable alone

**N/A:** the rule set holds a single unit, or the trigger above does not fire.

**Not duplication.** A unit that invokes another and states what it does when that other reaches some state — halts, errors, returns nothing — is branching, not copying, and this item does not report it. A caller has to be executable on its own. What does count is the caller **restating the callee's rule**: why that state arises, or under which condition it is reached. That restatement drifts when the callee's rule changes and the copy does not. The line: the caller names the state and its own response, and the callee owns everything else about it.

**Ownership.** The case this rule set cedes — see the Ownership boundary section of `authoritative-text-rules/SKILL.md` — is not this item's. This item owns contradiction, shadowing, and duplication that hold independently of any qualification the diff added.

**Tie-breaks.**

- Against `case-space-totality`: two branches of one unit both firing is that item. Two clauses in different units is this one.
- Against `single-reading`: if the clauses conflict only under one reading of one of them, the defect is that ambiguity.
