---
name: implement
description: Execute a prior research plan with GitHub issue integration, plan-vs-actual drift, done-check, and conventional commits. Optional issue number argument.
---

# implement

GitHub-integrated executor for a research plan: surfaces plan-vs-actual drift and runs a `done-check` audit before its final output.

**Issue / task:** $ARGUMENTS

## Step 1 — Retrieve the plan

1. Read the GitHub issue and comments using `gh issue view $ARGUMENTS --comments`.
2. Locate the implementation plan. It can live in two places depending on how the issue was created:
   - **Issue body** (D1 default for umbrella-spawned sub-issues): the body begins with `Parent: #<umbrella>` and contains the plan directly. When this line is present, treat the body itself as the plan and ignore comments for plan discovery.
   - **Issue comments** (single-scope issues): scan comments for the `research` output shape (`Hypotheses`, `Inconclusive / Deferred items` sections).
3. The retrieved plan is expected to follow the `research` output shape, including the `Inconclusive / Deferred items` section, regardless of which surface it lived on.
4. If no plan is found in either location, check the current conversation context. If neither is available, suggest running `/research $ARGUMENTS` first and stop.

## Step 2 — Extract the discovery contract

From the plan, extract:

- **Plan checklist** (units of work)
- **Impact list** (callers expected to be touched)
- **Implementation guards** (assertions, paired APIs, constructor validations)
- **Derivations** (specific examples and their deductive properties, already verified in `research`'s Derivational hypotheses step). The list of examples whose properties have been derived defines the **derivationally cleared example set** — examples not on this list are unverified by the plan, regardless of how obvious their properties may seem.
- **Inconclusive items** with their `probe` and `expected branches`
- **Deferred items** with their `reason` and `resolution-point`

These together form the **discovery contract**: the plan-side definition of what counts as "expected during implementation" vs "research gap".

If the plan has no `Inconclusive / Deferred items` section at all, treat that as a research gap and stop. Do not synthesize the section yourself. Re-run `/research` or ask the user to update the plan.

If the plan has no `Derivations` section but the work involves specific-example fixtures (concrete Hamiltonians, concrete protocol messages, named worked cases, etc.), treat that as a research gap on the derivational axis and stop the same way. The absence of a `Derivations` section means no specific example has been derivationally cleared.

## Step 3 — Execute the plan

Work through the Step 2 plan checklist with the plan as the source of truth.

The **root** — the ref this change is measured from — is an input, supplied by the caller on `diff-root`'s terms. This skill resolves none: with none supplied, ask. State it, and pass it to Step 3.0's `todo-check` and Step 4's `done-check`.

### 3.0 Preflight via todo-check

Before any implementation change, invoke `todo-check` against the plan, passing the root stated above, to extract the active preflight items and their setup actions for this work. Carry out each △ row's setup action: run a command it names before any change, with the 3.1 baseline, and make any other setup action with the changes it concerns. A preflight that halts emits no table at all, so there are no △ rows to carry out; it has surfaced something to the user, and implementation does not start. A file the diff will carry but the plan does not name has no preflight setup row here; the Step 4 `done-check` catches it against the diff.

### 3.0.1 Pre-commit hook recall

Once per session (cache for the duration of the conversation), read the project's pre-commit configuration to identify the constraints each hook will enforce. Typical config locations: `.pre-commit-config.yaml`, `lefthook.yml`, `.husky/`, the `[hooks]` section of a project task runner (e.g. `Makefile.toml` / `Justfile`).

For each hook, summarize what it enforces. Do not memorize hook internals. Pay particular attention to:

- **Line-count / file-size limits.** Correct response is file-split first, trim only genuinely redundant text (see `quality-list` `completion-hygiene`).
- **Linter constraints** that gate commits (e.g., warnings-as-errors flags). They feed into Step 3.1 Baseline.
- **Custom checks** specific to the project (banned imports, header enforcement, schema validation). Note their existence.

Formatter hooks (rustfmt, prettier, black, clang-format) do not need anticipation — they reformat in place at commit time.

Output: a short summary of the binding constraints. Do not paste the configuration into context.

### 3.0.2 Memory recall

Make recall deliberate once per session.

1. Read `MEMORY.md` (index only).
2. For each entry whose one-line description plausibly intersects a unit in the Step 2 checklist, open and read it.
3. Scope filter: entries the unit's description does not plausibly invoke are not active.

Output: a short list of active memory rules, followed in the changes they bear on, alongside `todo-check`'s active items. Before Step 4, fix a change that violates one of these memory rules.

### 3.0.3 Project documentation recall

Once per session, read any contributor / agent guidance docs present at the repo root or in `docs/` (top-level only): `CLAUDE.md`, `AGENTS.md`, `CONTRIBUTING.md`, `STYLE.md` / `STYLEGUIDE.md`, `HACKING.md`, `docs/CODING_GUIDELINES.md`, `docs/conventions/`. `README.md` only if it carries contribution guidance. Treat clearly-labeled non-standard names as in-scope. Follow the constraints the same way as 3.0.2.

### 3.1 Baseline

Before any code change, build and run existing tests to record pre-existing failures, and run the project's linter (e.g., `cargo clippy`, `clang-tidy`, `ruff check`, `eslint`) to record pre-existing warnings. Compare against both baselines whenever the tests or the linter run. Pre-commit-gated linters (Step 3.0.1) are especially important — the gate rejects on any new violation. Formatters are excluded.

### 3.2 Discovery handling during a unit

If, while executing a unit, an unexpected fact is observed (a behavior, type, caller, or invariant the plan did not anticipate):

1. **Check the plan's `Inconclusive` items.** Is this discovery an expected branch?
   - **Yes** → follow the listed branch. If the branch says "re-plan trigger", **stop implementation** and return to research for this hypothesis.
   - **No** → continue to step 2.
2. **Check the `Deferred` items.** Is this discovery the resolution-point of a deferred concern?
   - **Yes** → surface to user, decide whether to expand scope or keep it deferred.
   - **No** → continue to step 3.
3. **Unlisted discovery = research gap.** **Stop.** Do not patch the surprise ad-hoc. Surface to the user with: what was observed, why it contradicts the plan, what hypothesis class it falls under. Ask whether to re-research or to expand the discovery contract explicitly.

The plan's Inconclusive section is the only sanctioned channel for mid-implementation surprises.

### 3.2.1 Specific-example derivation gate

The Step 3.2 rule above covers behavioral / structural surprises. A parallel gate covers **the introduction of a new specific example** during implementation, review, or test addition — even when no "unexpected fact" has surfaced. This includes:

- A concrete Hamiltonian, fixture, or input case being added to satisfy a test plan that named only the abstract spec.
- A worked numerical case being chosen to instantiate a property the plan stated abstractly ("multi-sector W bond" → a particular choice of operators that supposedly realizes it).
- A protocol message, schema, or replay sequence being filled in for a placeholder.
- A test fixture acquiring concrete parameter values where the plan only constrained their qualitative properties.

For every such example, before adding the implementation:

1. **Check the derivationally cleared example set** (extracted in Step 2 from the plan's `Derivations` section). If the example is on the list, it has already been derivationally verified during research; proceed.
2. **If the example is not on the list, halt.** Do not add it on the strength of its properties feeling obvious.
3. **Required action when halted:** Surface to the user with: the proposed example, the deductive properties it is being relied on to satisfy (e.g., "this Hamiltonian must be U(1)-symmetric, must be Hermitian, must be non-diagonal in the chosen basis, must exercise the multi-sector path"), and the request to extend the plan's `Derivations` section before proceeding. The derivation itself is performed in `research`'s Derivational hypotheses step, not in implementation.

A `rejected` derivational outcome is a plan bug — return to research and choose a different example.

### 3.2.2 Mechanism-substitution discipline

When the plan sketches a specific strategy (algorithm, data structure, unsafe pattern) and the implementer chooses a different one at execution time, the substitution must preserve **every** property of the original, not just the explicit motivation named in the sketch.

Procedure when substituting:

1. **Enumerate the original strategy's properties explicitly.** Not just the named motivation — every property the original mechanism happens to achieve. E.g. `MaybeUninit` + transmute provides {no zero-init, no per-element heap alloc, caller-controlled placement, deterministic layout}; `Vec::with_capacity` + push provides {no zero-init} only.
2. **Verify the substitute preserves each property.** Any dropped property must be named in the plan-vs-actual diff and surfaced to the user — "substituting M with M' to avoid unsafe; M' loses Q. OK to ship?" — not silently discarded.

### 3.3 Quality items

Substantive rules for guards, fixtures, docstring consistency, textual drift, naming-as-claim, and plan-vs-actual reconciliation live in the rule sets `todo-check` applies. Honor whichever items Step 3.0's `todo-check` marked active. The gates in 3.2, 3.2.1, and 3.2.2 above layer on top.

### 3.4 Rejected commits

A commit a pre-commit hook rejects was not created. Skip a hook — by `--no-verify` or any other means — only where the user or the skill that invoked this one directs it, and only that hook. Otherwise fix what the hook reports, unless the fix would depart from the plan: then stop and surface the rejection to the user. After a skip or a fix, stage what the commit carries, including the hook's rewrites of those files, and create a new commit, never `git commit --amend`.

## Step 4 — Run done-check

Invoke the `done-check` skill against the diff, passing the root stated at Step 3. Do not proceed until `done-check`'s step 5 gate is satisfied over both domains — the audit table's `⚠` rows and the cross-cutting concerns reported under it. An audit that halts emits no table at all. It has surfaced something to the user, and this step does not complete.

## Step 5 — Final output

1. **Plan-vs-actual diff** — enumerate every divergence between the plan and the implementation diff together with what each divergence traces to, state whether every artifact the plan enumerated is present, and state the outcome of comparing the plan's impact list against the callers the implementation diff modified. `quality-list` `discovery-surfacing` governs the trace vocabulary and that enumeration check; `impact-verification` governs the comparison.
2. **Conventional commit message(s)**, generated under the rules of `generate-conventional-commit-messages` if the skill is available. No HPC paths, no cluster context, no local environment details, no line numbers in body.
3. Hand off — do **not** commit unless the user explicitly authorized commits.
