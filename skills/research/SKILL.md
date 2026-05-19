---
name: research
description: >
  Research a GitHub issue (or free-text task) by classifying hypotheses as
  empirical (resolved by code / runtime probes via subagents) or
  derivational (resolved by deductive reasoning from defining equations
  in the main context), and producing an implementation plan with
  explicit Inconclusive / Deferred items plus reproducible derivations
  for any specific-example claims. Use when the user wants to investigate
  an issue before coding under the four-state decision discipline
  (confirmed / rejected / inconclusive / deferred) with mandatory
  disconfirming probes. Accepts an issue number or free-text description
  (e.g., /research 42 or /research add retry logic).
---

# research

GitHub-integrated wrapper around `evidence-gated-review`. Drives the Finding → Hypothesis → Defense → Probe → Decision workflow with parallel subagents and posts the resulting plan to GitHub. Do NOT write any production code in this skill.

**Issue / task:** $ARGUMENTS

## Step 0 — Determine issue context

Check whether `$ARGUMENTS` is a number (existing issue) or free text (new task).

- **Number** → `gh issue view $ARGUMENTS` and proceed with that issue.
- **Free text** → use the text as the task description; an issue will be created in Step 5.

## Step 1 — Read issue/task and form hypotheses

1. If existing issue, read it with `gh issue view`. Otherwise use the free text.
2. Skim the project layout (directory tree, CLAUDE.md, key entry points). Do NOT deep-read files yet; that is the subagent's job.
3. **Establish baselines.**
   - **Test baseline**: build and run existing tests. Record pre-existing failures so later regressions can be distinguished.
   - **Memory recall baseline**: read `MEMORY.md` (the index only), and for each feedback / convention entry whose one-line description plausibly intersects the work being scoped, open the full entry and read it. Memory is passively loaded into context but agents do not reliably recall passive context when forming hypotheses, so this step makes the recall deliberate. Representative triggers: adding new `pub` symbols (visibility entries), adding or modifying tests (test convention entries), pre-release work touching deprecation / aliases / shims (backwards-compat policy), naming new helpers (naming-as-claim entries), referencing prior issues / phases (issue-number-in-code bans), touching repo / dev-docs boundaries (documentation channel entries). Scope filter: if a memory entry does not plausibly intersect the work, it is not active for this research pass. The active list shapes hypothesis formation in Step 1.4 and onward — a hypothesis that contradicts an active memory rule is rejected at formation rather than carried into probing.
4. Form hypotheses across three aspects:
   - **What needs to change**: required code modifications
   - **What invariants must hold**: contracts / preconditions / correctness properties
   - **What could break**: existing code paths affected by the change, especially where new inputs flow through existing APIs
5. Each hypothesis is phrased as a **falsifiable Review Claim or Hypothesis** in the evidence-gated-review sense — concrete enough that a subagent can attempt to disprove it.
6. **Tag each hypothesis with a `kind`:**
   - `empirical` — resolved by reading code, running tests, observing runtime, inspecting git history, querying spec / external API / caller behavior. Subagent probes in Step 2 handle these.
   - `derivational` — resolved by deductive reasoning from defining equations / type laws / protocol axioms / mathematical or physical first principles. The truth value of a derivational hypothesis does not depend on the state of the codebase; reading more code will not resolve it. Step 2 handles these in the main context, not via subagents.

   Mis-classification fails open: a derivational claim treated as empirical sends a subagent on a probe that cannot resolve it (the code never had the answer in the first place); an empirical claim treated as derivational tries to deduce facts the codebase actually controls. When in doubt, ask: "if the codebase did not exist, would the claim still have a definite truth value?" Yes → derivational. No → empirical.

   **Numerical verification stays derivational.** A hypothesis whose resolution path is "construct a candidate (formula, fixture, matrix) → check it numerically against an existing oracle (a spec, a reference value, a closed-form ground truth)" is **derivational**, not empirical. The candidate construction is deterministic from public sources, and the verification touches no runtime state of the codebase under research. Such a hypothesis is resolved in Step 2.B by running a scratch script (numpy / sympy / out-of-tree program) against the oracle, not by writing production code in the project tree.

   The signal that a probe has been misclassified: its action is "write code in the project, then check whether it works." That action is neither empirical (it does not observe runtime) nor a proper derivational step (it produces production-code drift instead of a derivation artifact). It is a derivational gap dressed as an empirical probe — re-classify and resolve in Step 2.B before the plan exits research.

7. **Specific-example claim sweep (REQUIRED when applicable).** If the plan proposes a specific concrete example (a particular Hamiltonian, a particular input fixture, a particular protocol message, a named algorithm, a worked numerical case) AND attaches deductive properties to it ("this example is symmetric", "this example is non-degenerate", "this example exercises the multi-X path"), each such property MUST be enumerated as a separate `derivational` hypothesis. **"Obvious" is not an exemption.** Properties that feel obvious to the plan author are exactly the ones that bypass probing and surface as bugs at fixture construction time.

   For each property P attached to example E, write the hypothesis as: "Example E has property P, derivable from E's defining equations / specification." This forces Step 2 to actually perform the derivation.

8. **Present hypotheses to the user for approval before spawning subagents.** Show the `kind` tag for each. The user can narrow scope, split into sub-issues, or correct mis-classifications.

## Step 2 — Verify hypotheses

Hypotheses split by `kind`. Empirical hypotheses go through subagent probes (Step 2.A). Derivational hypotheses are resolved in the main context (Step 2.B). Both must complete before Step 3 consolidates.

### Step 2.A — Empirical hypotheses (subagents under evidence-gated-review)

Spawn one subagent per `empirical` hypothesis (or per small related group). Each subagent operates under the `evidence-gated-review` skill and follows its workflow exactly. The wrapper's job is to pre-fill the contract; the subagent's job is to honor it.

Subagent contract:

1. **Run `evidence-gated-review`** with the assigned hypothesis as the initial Review Claim or Hypothesis.
2. **Probes are mandatory three-way**:
   - Supporting probe — what evidence would confirm the claim
   - **Disconfirming probe** — what evidence would refute it; **must be actually executed**, not just listed
   - Scope probe — local vs systemic
3. **Reading depth matches semantic-review when the hypothesis touches non-trivial existing code.** For each meaningful unit read in the course of probing, the subagent considers `What / Why / Invariants / Failure modes / Connections`. If `Why` is unclear, mark `UNKNOWN — probe: <git blame / callers / tests / ADR>` rather than inventing a reason. Shallow grep-only verification is permitted only for trivially mechanical hypotheses (existence checks, file locations).
4. **Runtime probe (preferred for behavioral claims).** When the hypothesis is about observable behavior — output ordering, return shape, panic / error-path return, side-effect timing, ABI / FFI layout, signal handling, performance characteristic, anything the runtime decides rather than the source — construct a minimal reproducer and execute it. Reading API docs / source comments is corroboration, not verification. The reproducer should be small (a short scratch program, an out-of-tree project, an ad-hoc invocation of an existing example) — if a small reproducer is not enough, the hypothesis probably needs to be split. Ensure the probe does not harm the workspace: scratch files belong outside the project tree (e.g. under `/tmp/`), and the probe must not modify project sources, dependencies, configuration, persistent stores, or external services. The probe should leave the workspace state unchanged regardless of outcome.
5. **Boundary cases**: trace minimal/maximal input sizes, type variations, single-element containers. These are common plan-vs-actual divergence sources.
6. **For "what could break" hypotheses**: classify the change as compile-breaking (new required trait method, type change) or silently semantic (same signature, different behavior). Semantic changes need caller-by-caller contract verification — the compiler will not catch them.
7. **For safety-critical paths**: if any public API has unchecked internal assumptions (pointer arithmetic trusting an offset, a serializer trusting field order, an index trusting contiguity), flag it. A boundary contract violation propagates silently into these internals.
8. Return a **Decision** in one of four states:
   - `confirmed` — supporting probe succeeded AND disconfirming probe was attempted and failed to refute
   - `rejected` — disconfirming probe yielded counter-evidence
   - `inconclusive` — current evidence is insufficient; attach the remaining `probe:` needed to resolve
   - `deferred` — real concern but outside current scope; attach reason and resolution-point
9. Report back with concise file paths, line numbers, function signatures, and probe results.

**Subagent granularity**: hypotheses requiring only existence checks or single-file grep can be resolved directly from the main context. Reserve subagents for hypotheses that touch multiple files or need deep reading.

Subagents run in parallel. Each subagent owns its own evidence-gated-review ledger; the main context will merge them.

### Step 2.B — Derivational hypotheses (deductive verification in main context)

Each `derivational` hypothesis is resolved by working out the deduction explicitly, not by reading code. The deduction may take either form:

- **Symbolic** — pen-and-paper algebra, formal manipulation of defining equations, type-law rewriting, protocol-axiom application.
- **Numerical** — when the closed form is too messy for pen-and-paper but reduces to a numerical identity verifiable against an existing oracle (a published reference matrix, a closed-form spec, a ground-truth value), run a scratch script (numpy / sympy / out-of-tree program) and compare to the oracle. The numerical run **is part of the derivation**, performed in research, and is not a deferred implementation probe. Production code in the project tree is not written for this lane — only out-of-tree scratch artifacts.

Both stay in research. Subagents are not appropriate here — the derivation lives in the plan, not in the codebase, and a subagent dispatched to "check" it will either (a) re-grep the code (irrelevant) or (b) attempt the same derivation the main context owes the user (no advantage over doing it directly).

For each derivational hypothesis:

1. **State the defining equations / axioms / specification clauses** the example or claim rests on. Quote the source if it is an external spec (RFC, protocol doc, mathematical definition); reproduce it if it is a project-internal definition.
2. **Derive forward from the defining equations to the claimed property.** Show the deductive steps. A derivation that ends in "therefore P holds" without reproducible steps is unacceptable — it is the same as not deriving at all.
3. **Attempt a counterexample (the disconfirming step).** Try to construct an instance of the example where the claimed property fails, working from the defining equations. A property that resists counterexample construction is corroborated; one that admits a counterexample falsifies the hypothesis.
4. **Report a Decision** in the same four-state shape as Step 2.A:
   - `confirmed` — derivation completed AND counterexample construction failed
   - `rejected` — counterexample constructed (the claim is false; plan needs revision before continuing)
   - `inconclusive` — derivation incomplete due to missing axiom / ambiguous spec / unresolved sign or convention conflict between sources; attach the missing piece as a `probe:` (this probe is now empirical — locate the missing axiom or canonical reference — and routes back through Step 2.A). **"The algebra is too messy / I will code it up in the project and check at implementation time" is not a valid `inconclusive` state.** That is a derivational gap and must be resolved by the numerical-derivation lane above (scratch script, out of tree, against an oracle) before the plan exits research.
   - `deferred` — outside current scope; attach reason and resolution-point

A `rejected` derivational hypothesis is a **plan bug**. Do not proceed to Step 3 until the plan is corrected and the affected hypotheses are re-derived. Patching the example mid-implementation is the failure mode this step exists to prevent.

**No derivation, no plan.** A plan that attaches deductive properties to specific examples without reproducing the derivation fails this step. The derivation does not need to be long, but it must be present and reproducible.

## Step 3 — Consolidate into implementation plan

Merge subagent reports into a single plan with the following sections.

### Plan body

- **Checklist of changes** with exact file paths, function signatures, type definitions
- **Impact list**: every caller affected and its implicit contract (for use in implementation verification)
- **Test plan**:
  - Invariants the new/changed code must satisfy
  - Tests to add/modify with expected behavior
  - For new constructors / input paths: tests passing those inputs through every existing public API that could receive them. A new input path without cross-API tests is incomplete.
- **Implementation guards** (from confirmed hypotheses):
  - New invariants enforced with assertions, not comments
  - Paired APIs that must stay consistent (sibling methods)
  - Constructor validations required
  - State that needs an explicit field rather than heuristic inference
- **Derivations** (from confirmed derivational hypotheses): for each specific example whose properties were claimed in the plan, reproduce the derivation in compressed form (defining equations → steps → conclusion). The plan reader should be able to retrace the deduction without re-running Step 2.B. This section also serves as the audit surface if a subsequent phase challenges the example choice.
- **Conflicts or dependencies between hypotheses** (if any)

### Inconclusive / Deferred items (REQUIRED section)

This section is **mandatory**. It explicitly carries forward UNKNOWNs into the implementation phase so that mid-implementation discoveries are either listed (handled per plan) or surface as research gaps (halt and escalate).

```markdown
## Inconclusive / Deferred items

- inconclusive — <hypothesis>
  probe: <next investigation: git blame, runtime observation, etc.>
  expected branches:
    - if probe yields X → continue per plan
    - if probe yields Y → re-plan trigger (return to research)

- deferred — <hypothesis>
  reason: <why postponed>
  resolution-point: <when this becomes actionable>
```

If there are no inconclusive or deferred items, write `Inconclusive / Deferred items: none identified` explicitly. Silent omission is **forbidden** — it conflates "no UNKNOWNs" with "did not look".

### Filter unresolved questions before listing them

Before escalating a sub-decision to the user as "unresolved":

1. **Workspace patterns** — search the workspace (`rg`, `fd`) for analogous constructs. If the workspace consistently does X, that is the answer.
2. **Memory and prior conversation** — check available memory entries and recent turns for decisions on the same axis.
3. **Subagent reports** — re-read Step 2 output. A subagent's confirmed recommendation is resolved unless contradicted elsewhere.

A sub-decision is genuinely unresolved only when the above are silent or contradictory. "More than one technically-viable option exists" is not unresolved — it is analysis you owe the user. When you do escalate, state what you checked.

Report the plan back to the main context.

## Step 3.4 — Contract reachability check (mandatory)

A plan can be **locally closed** (mechanism fits in scope, tests are writable, the docstring is composable) yet **contract-empty** (the semantic contract of any new public surface depends on consumer code that is not yet aligned). Local closure is what `codex-plan-review` and the author's confidence both assess well; contract closure is what they both miss, because it requires looking outward (at downstream consumers) rather than inward (at the plan).

When contract closure fails silently and the plan ships, the symptom shows up later as repeated reviewer friction over the same API contract — "should this parameter accept both values?", "should this panic?", "should this convert?" — i.e., oscillation in the review pipeline that the oscillation-detection rule then has to catch downstream. This step exists to catch it upstream, via mechanical signals that don't require insight.

Run all three checks against the plan body and the proposed public surface. Any one of them firing means the plan's contract is not closed; the response is to escalate scope or defer, not to ship.

### Check 1 — Dead-on-arrival state

For each new public symbol introduced by the plan (function parameter with non-trivial value range, struct field, accessor, method, type variant), answer:

> Does any current or in-plan code path **branch on** (act on) this symbol's value?

Branching means: reading the value and choosing a code path based on it (`match`, `if`, conditional dispatch, layout reorder, validation, etc.). Pure references that do not branch — `Clone` copying the field, an accessor `pub fn x(&self) -> X { self.x }` exposing it, a constructor storing it — are **not** branches. They are tautological consumers that exist solely to expose the symbol and do not justify the symbol's existence.

- If at least one real branch exists → contract has a consumer that acts on the value; proceed.
- If no real branch exists → the symbol is dead-on-arrival. Either:
  - **Expand scope** — add the consumer-side branching to the plan checklist, with its own implementation guards, tests, and impact list.
  - **Defer the symbol** — drop it from this plan; refile when the consumer materializes.

A `source_order: MemoryOrder` parameter where no current code reads `tensor.order()` to branch on it is dead-on-arrival in the strict sense — every consumer treats the layout authority as something else (e.g., `backend.preferred_order()`). The plan must either resolve the consumer side first or not introduce the parameter.

### Check 2 — Docstring-vocabulary scan

Grep the plan body and any proposed docstrings for the following phrases (case-insensitive):

```
not yet honored | currently restricted | social contract | deferred (mitigation|consumer-side|to a later)
documented limitation | for future use | in preparation for | analogous to ... cascade
in a future PR | follow-up issue tracks | when consumers ... | until consumers ...
```

Each hit is a self-admission that the plan's contract depends on something **outside the plan's scope**. Hits are not automatically fatal — sometimes the dependency is in-flight under another tracked issue. But every hit must resolve into either:

- A **`Depends on #N` link** to the issue that closes the gap (in which case the plan's `Inconclusive / Deferred items` carries the dependency explicitly).
- A **scope expansion** that pulls the gap into this plan.
- A **defer / close** decision: this issue is not single-actionable; re-frame upstream.

A plan with hits and no resolution route is contract-empty by self-declaration. Do not proceed to Step 3.5; return to Step 1 and rescope.

### Check 3 — Local-closure vs contract-closure distinction

Restate the plan's claim in one sentence and ask: would this claim still be true if every line of consumer code outside the plan's checklist were arbitrary?

- **Local closure**: "the new constructor stores the data correctly and propagates the order tag" — true regardless of consumer behavior; plan is locally closed.
- **Contract closure**: "the new constructor produces a tensor that downstream operations interpret correctly under the declared order" — only true if consumers honor the tag, which is a consumer-side property.

If the user-visible value of the plan rests on contract closure (not just local closure) and contract closure is not in scope, the plan is mis-scoped. The fix is to either bring contract closure into scope or step back to the upstream design decision.

The output of Step 3.4 is one of:

- **clean** — none of Check 1 / 2 / 3 fired; proceed to Step 3.5.
- **flagged** — list the firings, the proposed resolution route (scope expansion / `Depends on` / defer-and-close), and surface to the user before continuing.

## Step 3.5 — Plan review gate (mandatory offer)

Plan review is consistently mishandled when left to ad-hoc judgement — trivial changes skip it (fine), risky changes also skip it (not fine), and the decision is made on the basis of how confident the plan author feels rather than how exposed the plan is. The gate makes the decision deterministic. Running review before Step 5 (GitHub post) keeps the issue trail clean: only the reviewed plan is ever posted, so a premise problem caught here does not produce a noisy "first plan / revised plan" sequence on the issue.

After Step 3 produces a plan and before Step 4 collects user approval:

1. **Always offer `codex-plan-review`** — never silently skip. Phrase it as a recommendation, not a question:

   > "Plan ready. Recommend running `/codex-plan-review` before
   > approval; type `skip` to bypass, or anything else to run it."

   Bypassing is a deliberate user choice, not the default.

2. **If review runs**: triage the findings.
   - **Implementation concerns** (algorithm details, error handling, test coverage gaps, naming): patch the plan in place and proceed to the loop gate below.
   - **Premise concerns** (the assumed root cause may be wrong, the described mechanism doesn't match how the code actually fails, a fixture's claimed properties may not hold, an "obvious" derivation is unproven): **return to Step 1**. Do not patch the plan in place — the hypothesis set itself is suspect, and incremental edits perpetuate the bad premise across iterations.

   Distinguishing the two: an implementation concern asks "given the plan's assumptions, is the proposed approach sound?"; a premise concern asks "are the plan's assumptions actually true?". If the reviewer would have given a different answer with empirical evidence in hand, it's a premise concern.

3. **Loop gate**: after patching, re-run `codex-plan-review` per its Step 4 re-run rule (only when the revision meaningfully invalidates the prior verdict — triage author's call, not derived from Codex's verdict label). Exit the loop when the last valid verdict is `approve` or `approve with conditions`. Cap: 3 iterations within the same premise. If the cap is reached, or if the loop sits at `reject` with no further re-run warranted, surface the verdict and outstanding findings to the user and ask whether to proceed as-is, patch further manually, or escalate. Premise concerns return to Step 1 and reset the counter — iteration count is per-premise, not lifetime.

4. **The plan that exits this step is the contract.** Step 5 will post that plan once. Revisions happen here, before posting; there is no "post then revise" loop.

The cost of running `codex-plan-review` once per cycle is minutes; the cost of carrying a wrong-premise plan through implementation is hours-to-days of rework. Bias toward running it.

## Step 4 — User approval

Present the plan (after any Step 3.5 revisions) and ask for approval before posting to GitHub.

## Step 5 — Post plan to GitHub

### 5.0 Laundering pass — run `gh-body-check` (MANDATORY)

Before any `gh-post` invocation, run `gh-body-check` on the plan body, regardless of which routing branch below applies. The check delegates mechanical items (hard-wrap, over-fragmented sub-clause breaks, local-path patterns, private skill names, Phase / Step numbering, JP clauses in English bodies, chat-tone scaffolding, Unicode math in prose, unresolved placeholders, line numbers in issue bodies) to a fresh-context subagent — research plans are particularly prone to over-fragmented "clause-per-line" formatting (lines ending on prepositions, mid-noun-phrase, or after list commas) that the author's own re-read passes because they read intent rather than text.

Resolve any ⚠ before invoking `gh-post`. The "per `file-issue` step 5" pointers below refer to the `gh-post` invocation shape only; `file-issue`'s Step 3 laundering pass does NOT run automatically from those pointers, so this 5.0 step is its replacement on the research-post path.

### 5.1 Route to the correct surface

After 5.0 clears, route the plan based on what `$ARGUMENTS` resolves to:

- **Existing single-scope issue** → `gh-post issue comment $ARGUMENTS` (per `file-issue` step 5) with the plan as body.
- **Existing umbrella issue** (the body contains a Phases table or sub-tasks list) → spawn a new sub-issue whose body IS the plan, following `file-issue`'s `Variants > Umbrella sub-issue` shape: `Parent: #<umbrella>` on the first line, `Phase N: <topic>` title, Goal / Scope / Out of scope / Acceptance derived from the plan. After creation, append the new sub-issue's number to the umbrella's Phases table row. The sub-issue body is the canonical contract surface; do not also post the plan as an umbrella comment.
- **New task** → `gh-post issue create` (per `file-issue` step 5) with the plan in the body; report the new issue number.

When the umbrella vs single-scope classification is ambiguous, surface both options to the user and let them choose. The umbrella branch is the D1 default — the sub-issue body becomes the single referenceable artifact (`Closes #<sub-issue>` from the PR points directly to the plan), avoiding the body/comment two-layer redundancy of the legacy spawn-then-comment flow.

**Issue creation rules:**

1. **English only.** Conversation language and issue language are independent.
2. **Split issues by commit unit.** Each issue corresponds to one atomic, independently committable change. Multi-commit plans become multiple issues with `Depends on #N` links.
3. **No HPC paths, no cluster context, no local environment details.**
4. **No line numbers** in issue body (they rot).
5. **No "rejected alternatives" sections** unless explicitly requested.

The body / title formatting itself follows `file-issue`'s conventions and (for the umbrella branch) its `Umbrella sub-issue` variant — this skill is the orchestrator, `file-issue` is the SSOT for body shape.
