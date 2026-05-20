---
name: research
description: Investigate a GitHub issue or free-text task with empirical (subagent probes) and derivational (in-context deduction) hypotheses, producing a vetted implementation plan with Inconclusive / Deferred items. Accepts an issue number or task text.
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
   - **Memory recall baseline**: read `MEMORY.md` (index only); for each entry whose one-line description plausibly intersects the work, open and read it. Passive memory load is unreliable for hypothesis formation — make recall deliberate. A hypothesis that contradicts an active memory rule is rejected at formation.
4. Form hypotheses across three aspects:
   - **What needs to change**: required code modifications
   - **What invariants must hold**: contracts / preconditions / correctness properties
   - **What could break**: existing code paths affected by the change, especially where new inputs flow through existing APIs
5. Each hypothesis is phrased as a **falsifiable Review Claim or Hypothesis** in the evidence-gated-review sense — concrete enough that a subagent can attempt to disprove it.
6. **Tag each hypothesis with a `kind`:**
   - `empirical` — resolved by reading code, running tests, observing runtime, inspecting git history, querying spec / external API / caller behavior. Subagent probes in Step 2 handle these.
   - `derivational` — resolved by deductive reasoning from defining equations / type laws / protocol axioms / mathematical or physical first principles. The truth value of a derivational hypothesis does not depend on the state of the codebase; reading more code will not resolve it. Step 2 handles these in the main context, not via subagents.

   Mis-classification fails open in both directions. Disambiguation test: "if the codebase did not exist, would the claim still have a definite truth value?" Yes → derivational. No → empirical. Two follow-on rules:

   - **Numerical verification stays derivational.** "Construct a candidate → check against an oracle (spec, reference value, closed-form ground truth)" is derivational; resolve in Step 2.B with a scratch script outside the project tree.
   - **Misclassification signal.** If a probe's action is "write code in the project, then check whether it works", it is a derivational gap dressed as an empirical probe — re-classify before the plan exits research.

7. **Specific-example claim sweep (REQUIRED when applicable).** If the plan attaches deductive properties to a concrete example ("this example is symmetric / non-degenerate / exercises the multi-X path"), each property MUST be a separate `derivational` hypothesis — "obvious" is not an exemption. Form: "Example E has property P, derivable from E's defining equations / specification."

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
4. **Runtime probe (preferred for behavioral claims).** Behavioral claims (output ordering, return shape, error-path return, ABI / FFI layout, signal handling, performance) need a minimal reproducer — docs reading is corroboration, not verification. Scratch files belong outside the project tree (e.g. `/tmp/`); the probe must not modify project sources, dependencies, configuration, persistent stores, or external services.
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

- **Symbolic** — pen-and-paper algebra / type-law rewriting / protocol-axiom application.
- **Numerical** — when the closed form is too messy, reduce to a numerical identity against an oracle (published reference matrix, closed-form spec, ground-truth value); run a scratch script outside the project tree. This **is** the derivation, not a deferred implementation probe.

Subagents cannot resolve derivational hypotheses (they'd re-grep code or repeat the deduction).

For each derivational hypothesis:

1. **State the defining equations / axioms / specification clauses** the example or claim rests on. Quote the source if it is an external spec (RFC, protocol doc, mathematical definition); reproduce it if it is a project-internal definition.
2. **Derive forward from the defining equations to the claimed property.** Show the deductive steps. A derivation that ends in "therefore P holds" without reproducible steps is unacceptable — it is the same as not deriving at all.
3. **Attempt a counterexample (the disconfirming step).** Try to construct an instance of the example where the claimed property fails, working from the defining equations. A property that resists counterexample construction is corroborated; one that admits a counterexample falsifies the hypothesis.
4. **Report a Decision** in the same four-state shape as Step 2.A:
   - `confirmed` — derivation completed AND counterexample construction failed
   - `rejected` — counterexample constructed (the claim is false; plan needs revision before continuing)
   - `inconclusive` — derivation incomplete due to missing axiom / ambiguous spec / convention conflict; attach the missing piece as an empirical `probe:` routing back through Step 2.A. ("Code it up and check at implementation time" is not valid — use the numerical-derivation lane.)
   - `deferred` — outside current scope; attach reason and resolution-point

A `rejected` derivational hypothesis is a **plan bug**. Correct the plan and re-derive before Step 3. A plan that attaches deductive properties to examples without reproducing the derivation fails this step.

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

If none, write `Inconclusive / Deferred items: none identified` explicitly — silent omission conflates "no UNKNOWNs" with "did not look".

### Filter unresolved questions before listing them

Before escalating a sub-decision to the user as "unresolved":

1. **Workspace patterns** — search the workspace (`rg`, `fd`) for analogous constructs. If the workspace consistently does X, that is the answer.
2. **Memory and prior conversation** — check available memory entries and recent turns for decisions on the same axis.
3. **Subagent reports** — re-read Step 2 output. A subagent's confirmed recommendation is resolved unless contradicted elsewhere.

A sub-decision is genuinely unresolved only when the above are silent or contradictory. "More than one technically-viable option exists" is not unresolved — it is analysis you owe the user. When you do escalate, state what you checked.

Report the plan back to the main context.

## Step 3.4 — Contract reachability check (mandatory)

A plan can be locally closed yet **contract-empty** when a new public surface's semantics depend on consumer code outside scope. `codex-plan-review` and author confidence both miss this — it requires looking outward. Any check firing means the plan's contract is not closed; rescope or defer.

### Check 1 — Dead-on-arrival state

For each new public symbol (parameter with non-trivial value range, struct field, accessor, method, variant), ask: does any current or in-plan code path **branch on** this symbol's value (`match`, `if`, conditional dispatch, layout reorder, validation)? Pure references — `Clone` copying, accessor exposure, constructor storing — are not branches.

- Real branch exists → proceed.
- No real branch → dead-on-arrival. Either expand scope (add consumer-side branching to the checklist) or defer the symbol until the consumer materializes.

### Check 2 — Docstring-vocabulary scan

Grep the plan body and proposed docstrings (case-insensitive):

```
not yet honored | currently restricted | social contract | deferred (mitigation|consumer-side|to a later)
documented limitation | for future use | in preparation for | analogous to ... cascade
in a future PR | follow-up issue tracks | when consumers ... | until consumers ...
```

Each hit admits an out-of-scope dependency. Each must resolve into a `Depends on #N` link (carried in `Inconclusive / Deferred items`), a scope expansion, or a defer / close decision. Hits without a resolution route → return to Step 1 and rescope.

### Check 3 — Local-closure vs contract-closure distinction

Restate the plan's claim in one sentence. Would it still be true if every line of consumer code outside the plan were arbitrary?

- **Local closure**: "constructor stores the data correctly and propagates the order tag" — true regardless of consumers.
- **Contract closure**: "constructor produces a tensor that downstream operations interpret correctly under the declared order" — only true if consumers honor the tag.

If the user-visible value rests on contract closure and contract closure is out of scope, the plan is mis-scoped. Bring contract closure in or step back to the upstream design decision.

Output: **clean** (proceed to Step 3.5) or **flagged** (list firings + proposed resolution + surface to user).

## Step 3.5 — Plan review gate (mandatory offer)

Running plan review before Step 5 keeps the issue trail clean — only the reviewed plan is posted.

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

## Step 4 — User approval

Present the plan (after any Step 3.5 revisions) and ask for approval before posting to GitHub.

## Step 5 — Post plan to GitHub

### 5.0 Laundering pass — run `gh-body-check` (MANDATORY)

Run `gh-body-check` on the plan body before any `gh-post` invocation; resolve any ⚠ before posting. Note: `file-issue`'s Step 3 laundering pass does NOT auto-run from the pointers below, so this 5.0 step is its replacement on the research-post path.

### 5.1 Route to the correct surface

After 5.0 clears, route the plan based on what `$ARGUMENTS` resolves to:

- **Existing single-scope issue** → `gh-post issue comment $ARGUMENTS` (per `file-issue` step 5) with the plan as body.
- **Existing umbrella issue** (the body contains a Phases table or sub-tasks list) → spawn a new sub-issue whose body IS the plan, following `file-issue`'s `Variants > Umbrella sub-issue` shape: `Parent: #<umbrella>` on the first line, `Phase N: <topic>` title, Goal / Scope / Out of scope / Acceptance derived from the plan. After creation, append the new sub-issue's number to the umbrella's Phases table row. The sub-issue body is the canonical contract surface; do not also post the plan as an umbrella comment.
- **New task** → `gh-post issue create` (per `file-issue` step 5) with the plan in the body; report the new issue number.

When ambiguous, ask the user. Umbrella sub-issue is the D1 default — the sub-issue body becomes the single referenceable artifact (`Closes #<sub-issue>` points directly to the plan).

**Issue creation rules:**

1. **English only.** Conversation language and issue language are independent.
2. **Split issues by commit unit.** Each issue corresponds to one atomic, independently committable change. Multi-commit plans become multiple issues with `Depends on #N` links.
3. **No HPC paths, no cluster context, no local environment details.**
4. **No line numbers** in issue body (they rot).
5. **No "rejected alternatives" sections** unless explicitly requested.

The body / title formatting itself follows `file-issue`'s conventions and (for the umbrella branch) its `Umbrella sub-issue` variant — this skill is the orchestrator, `file-issue` is the SSOT for body shape.
