---
name: codex-plan-review
description: Review an implementation plan with OpenAI Codex before coding, getting a second opinion on assumptions and approach.
---

# Codex Plan Review

Ask Codex to review an implementation plan against the actual codebase before implementation begins.

## Procedure

### 1. Build the prompt

Use the XML-block template below. Each block is optional — drop any block that does not fit the task, but keep the order stable so Codex sees a predictable structure.

Gather first:

- The implementation plan (from the current conversation)
- The list of repository files Codex should read before evaluating
- When the plan carries `research`'s Failure scenarios section, `research`'s scenario definitions and scenario records, and the hypotheses `research`'s Step 2 confirmed for the plan
- 2–4 specific evaluation questions (not "what do you think?")

Template:

```xml
<task>
Review the following implementation plan against this repository.
Read the referenced source files before evaluating.
Assess whether the plan will correctly achieve its stated goal without breaking existing behavior.

Plan:
<PLAN_TEXT>

Files to inspect first:
<FILE_LIST>

Specific questions:
<EVALUATION_QUESTIONS>
</task>

<failure_scenarios>
The plan above carries a Failure scenarios section; the definitions it uses, its records, and the hypotheses the plan rests on follow. A scenario the table lists as Covered `no` is one the plan deliberately leaves unguarded: do not report a missing guard for it, whatever the dig_deeper_nudge block asks. Report any evidence you read that the section is not accurate for the change, as its definitions define accurate, quoting that evidence, grounded in code you read or in the records given here; the grounding_rules, verification_loop and missing_context_gating blocks do not filter these reports otherwise.
<FAILURE_SCENARIOS_DEFINITIONS_RECORDS_AND_HYPOTHESES>
</failure_scenarios>

<grounding_rules>
Ground every concern in code you have actually read from this repository.
Do not invent file names, function signatures, or behaviors.
If a point is an inference rather than a verified fact, label it as such.
</grounding_rules>

<structured_output_contract>
Return:
1. verdict — one of: approve / approve with conditions / reject
2. findings ordered by severity, each tagged [P1/P2/P3] with file:line where applicable
3. supporting evidence for each finding (quoted code or exact file reference)
4. open questions you could not resolve from the repository alone
Keep the output compact. Do not restate the plan.
</structured_output_contract>

<dig_deeper_nudge>
Beyond the first obvious concern, check for:
- format or type mismatch between producers and consumers the plan touches
- branching logic that conflates distinct inputs or failure modes
- missing validation at API or module boundaries
- inconsistency between the plan and existing patterns in this codebase
- **dead-on-arrival public surface**: for each new parameter / field / method the plan adds, identify whether any current code path BRANCHES on its value (matches / reorders / validates / dispatches). Tautological consumers — `Clone`, accessors that just expose the field, constructors that just store it — do not count. If no branching consumer exists, the symbol's contract depends on consumer code that is not yet aligned, and the plan should either bring that consumer into scope or defer the symbol. This is the "contract closure" axis: a plan can be locally closed (mechanism fits) yet contract-empty (semantic meaning depends on outside).
- **shared-scope config reach**: for any lint / setting / config the plan enables at a shared scope (Cargo `[workspace.lints]` / `[lints]`, a workspace / package / global config, a compiler-wide flag), enumerate every unit that scope binds (for Cargo: lib, bins, integration tests, benches, examples, and the build script — each a separate compilation unit inheriting the package lints) and flag when the intended target (e.g. the library) is narrower than the actual reach. A narrower per-unit attribute, or bringing every bound unit into scope and verifying it, is the resolution.
- **probe-configuration representativeness**: when the plan leans on a "it builds" / "the tests pass" / "the cycle compiles" probe and the same source compiles under non-interchangeable configurations (Rust `--cfg test` vs the non-test build, feature-gated vs ungated, C / C++ translation units whose macro differences change a type's layout / ODR identity, distinct `target` / `arch`), a pass under one configuration does not certify a sibling that produces distinct type instances / ABI. Identify the configuration where the new obligation binds and flag when the probe runs only a sibling — an integration target linking the non-test build, or "does it build" — while the obligation binds in the crate's own `--cfg test` unit tests or the gated build. Requiring the binding-configuration probe, or restructuring so the obligation stays inside one configuration, is the resolution.
</dig_deeper_nudge>

<missing_context_gating>
Do not guess project constraints, YAGNI scope, or stakeholder intent.
If a finding depends on such context, list it under open questions instead of findings.
</missing_context_gating>

<verification_loop>
Before finalizing, verify that each finding is material (would cause incorrect behavior or a real regression) and anchored in code you actually read.
Drop speculative or stylistic nits.
</verification_loop>
```

Block selection rationale:

- `failure_scenarios`: keeps Codex from asking for guards against scenarios the table lists as Covered `no`, and surfaces evidence that the Failure scenarios section is not accurate for the change
- `grounding_rules`: plan review drifts into invented code otherwise
- `structured_output_contract`: forces a shape that maps directly to the triage step in §3
- `dig_deeper_nudge`: without it Codex tends to stop at the first plausible concern
- `missing_context_gating`: redirects scope/YAGNI speculation into open questions instead of findings
- `verification_loop`: trims speculative nits before they reach the user

### 2. Run Codex

```bash
codex exec "<prompt>" < /dev/null -o /tmp/codex-plan-review.md
```

**Important:**

- Always use `< /dev/null`
- Set timeout to 600000ms (10 minutes)
- Use `-o` to capture output to a file

### 3. Triage the feedback

Codex evaluates the plan against the code it reads, but lacks project context (design decisions, scope constraints, YAGNI boundaries). Classify each finding under the `finding-triage` SSOT dispositions. The cases that recur in plan review:

- **`actionable`**: a real design flaw that would cause bugs or incorrect behavior
- **`false-positive`**: a concern that doesn't apply given project constraints (e.g., suggesting generalization when only one case exists)

A finding whose resolution opens a design question the plan did not settle is `opens-a-question` → fold it back into the research that produced the plan rather than spot-patching the plan text.

Whatever the `<failure_scenarios>` block asks Codex to report is triaged as a finding under `finding-triage`, wherever in the output it appears.

Present the triage to the user, not the raw output.

### 4. Update the plan

Take each finding that is not closed, as `finding-triage` defines closed, as its disposition directs; for an `actionable` finding, that is revising the plan in the conversation. If the plan was revised, re-present it to the user for approval. Re-run Codex on the revised plan only when the revision meaningfully invalidates the prior verdict — e.g., switching to an alternative approach, invariant promotion (a symptom-level finding turned out to require an invariant-level rewrite), or scope shift. This is the triage author's call: Codex returns incremental judgments on the plan as presented, not fundamental-vs-incremental classifications of subsequent revisions, so its verdict label is not a proxy for this decision. Pure in-scope condition incorporation or a single P2 / P3 patch does not warrant re-running. See `research`'s Plan review gate for a caller-imposed loop using this trigger.

## What Codex is bad at in plan review

- Scope judgment (will suggest over-engineering)
- Project-specific constraints (doesn't know what's YAGNI)
- Trade-off decisions (will flag every simplification as a risk)
- Whether a "documented limitation" or "deferred mitigation" in the plan is acceptable or is a self-admission that the plan is mis-scoped — Codex grounds in code, not in scope-vs-contract distinctions

The user makes these calls, not Codex.
