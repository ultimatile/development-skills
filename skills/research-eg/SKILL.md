---
name: research-eg
description: >
  Research a GitHub issue (or free-text task) by delegating hypothesis verification
  to the evidence-gated-review skill, parallelizing per-hypothesis probes via subagents,
  and producing an implementation plan with explicit Inconclusive / Deferred items.
  Use when the user wants to investigate an issue before coding and prefers the
  four-state decision discipline (confirmed / rejected / inconclusive / deferred)
  with mandatory disconfirming probes. Accepts an issue number or free-text
  description (e.g., /research-eg 42 or /research-eg add retry logic).
---

# research-eg

GitHub-integrated wrapper around `evidence-gated-review`. Drives the
Finding → Hypothesis → Defense → Probe → Decision workflow with parallel
subagents and posts the resulting plan to GitHub. Do NOT write any
production code in this skill.

**Issue / task:** $ARGUMENTS

## Step 0 — Determine issue context

Check whether `$ARGUMENTS` is a number (existing issue) or free text (new
task).

- **Number** → `gh issue view $ARGUMENTS` and proceed with that issue.
- **Free text** → use the text as the task description; an issue will be
  created in Step 5.

## Step 1 — Read issue/task and form hypotheses

1. If existing issue, read it with `gh issue view`. Otherwise use the
   free text.
2. Skim the project layout (directory tree, CLAUDE.md, key entry
   points). Do NOT deep-read files yet; that is the subagent's job.
3. **Establish a baseline**: build and run existing tests. Record
   pre-existing failures so later regressions can be distinguished.
4. Form hypotheses across three aspects:
   - **What needs to change**: required code modifications
   - **What invariants must hold**: contracts / preconditions /
     correctness properties
   - **What could break**: existing code paths affected by the change,
     especially where new inputs flow through existing APIs
5. Each hypothesis is phrased as a **falsifiable Review Claim or
   Hypothesis** in the evidence-gated-review sense — concrete enough
   that a subagent can attempt to disprove it.
6. **Present hypotheses to the user for approval before spawning
   subagents.** The user can narrow scope or split into sub-issues.

## Step 2 — Verify hypotheses in parallel (subagents under evidence-gated-review)

Spawn one subagent per hypothesis (or per small related group). Each
subagent operates under the `evidence-gated-review` skill and follows
its workflow exactly. The wrapper's job is to pre-fill the contract; the
subagent's job is to honor it.

Subagent contract:

1. **Run `evidence-gated-review`** with the assigned hypothesis as the
   initial Review Claim or Hypothesis.
2. **Probes are mandatory three-way**:
   - Supporting probe — what evidence would confirm the claim
   - **Disconfirming probe** — what evidence would refute it; **must be
     actually executed**, not just listed
   - Scope probe — local vs systemic
3. **Reading depth matches semantic-review when the hypothesis touches
   non-trivial existing code.** For each meaningful unit read in the
   course of probing, the subagent considers `What / Why / Invariants /
   Failure modes / Connections`. If `Why` is unclear, mark
   `UNKNOWN — probe: <git blame / callers / tests / ADR>` rather than
   inventing a reason. Shallow grep-only verification is permitted only
   for trivially mechanical hypotheses (existence checks, file
   locations).
4. **Boundary cases**: trace minimal/maximal input sizes, type
   variations, single-element containers. These are common
   plan-vs-actual divergence sources.
5. **For "what could break" hypotheses**: classify the change as
   compile-breaking (new required trait method, type change) or
   silently semantic (same signature, different behavior). Semantic
   changes need caller-by-caller contract verification — the compiler
   will not catch them.
6. **For safety-critical paths**: if any public API has unchecked
   internal assumptions (pointer arithmetic trusting an offset, a
   serializer trusting field order, an index trusting contiguity), flag
   it. A boundary contract violation propagates silently into these
   internals.
7. Return a **Decision** in one of four states:
   - `confirmed` — supporting probe succeeded AND disconfirming probe
     was attempted and failed to refute
   - `rejected` — disconfirming probe yielded counter-evidence
   - `inconclusive` — current evidence is insufficient; attach the
     remaining `probe:` needed to resolve
   - `deferred` — real concern but outside current scope; attach reason
     and resolution-point
8. Report back with concise file paths, line numbers, function
   signatures, and probe results.

**Subagent granularity**: hypotheses requiring only existence checks or
single-file grep can be resolved directly from the main context. Reserve
subagents for hypotheses that touch multiple files or need deep reading.

Subagents run in parallel. Each subagent owns its own
evidence-gated-review ledger; the main context will merge them.

## Step 3 — Consolidate into implementation plan

Merge subagent reports into a single plan with the following sections.

### Plan body

- **Checklist of changes** with exact file paths, function signatures,
  type definitions
- **Impact list**: every caller affected and its implicit contract (for
  use in implementation verification)
- **Test plan**:
  - Invariants the new/changed code must satisfy
  - Tests to add/modify with expected behavior
  - For new constructors / input paths: tests passing those inputs
    through every existing public API that could receive them. A new
    input path without cross-API tests is incomplete.
- **Implementation guards** (from confirmed hypotheses):
  - New invariants enforced with assertions, not comments
  - Paired APIs that must stay consistent (sibling methods)
  - Constructor validations required
  - State that needs an explicit field rather than heuristic inference
- **Conflicts or dependencies between hypotheses** (if any)

### Inconclusive / Deferred items (REQUIRED section)

This section is **mandatory**. It explicitly carries forward UNKNOWNs
into the implementation phase so that mid-implementation discoveries are
either listed (handled per plan) or surface as research gaps (halt and
escalate).

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

If there are no inconclusive or deferred items, write
`Inconclusive / Deferred items: none identified` explicitly. Silent
omission is **forbidden** — it conflates "no UNKNOWNs" with "did not
look".

### Filter unresolved questions before listing them

Before escalating a sub-decision to the user as "unresolved":

1. **Workspace patterns** — search the workspace (`rg`, `fd`) for
   analogous constructs. If the workspace consistently does X, that is
   the answer.
2. **Memory and prior conversation** — check available memory entries
   and recent turns for decisions on the same axis.
3. **Subagent reports** — re-read Step 2 output. A subagent's confirmed
   recommendation is resolved unless contradicted elsewhere.

A sub-decision is genuinely unresolved only when the above are silent or
contradictory. "More than one technically-viable option exists" is not
unresolved — it is analysis you owe the user. When you do escalate,
state what you checked.

Report the plan back to the main context.

## Step 4 — User approval

Present the plan and ask for approval before posting to GitHub.

## Step 5 — Post plan to GitHub

After user approval:

- **Existing issue** → `gh issue comment $ARGUMENTS` with the plan as
  body
- **New task** → `gh issue create` with the plan in the body; report the
  new issue number

**Issue creation rules:**

1. **English only.** Conversation language and issue language are
   independent.
2. **Split issues by commit unit.** Each issue corresponds to one
   atomic, independently committable change. Multi-commit plans become
   multiple issues with `Depends on #N` links.
3. **No HPC paths, no cluster context, no local environment details.**
4. **No line numbers** in issue body (they rot).
5. **No "rejected alternatives" sections** unless explicitly requested.
