---
name: codex-plan-review
description: Review an implementation plan with OpenAI Codex before coding, getting a second opinion on assumptions and approach.
---

# Codex Plan Review

Ask Codex to review an implementation plan against the actual codebase before implementation begins.

## When to use

- When you want a second opinion on architectural decisions before writing code
- To catch design-level issues that are cheaper to fix before implementation

## Procedure

### 1. Build the prompt

Use the XML-block template below. Each block is optional — drop any block that does not fit the task, but keep the order stable so Codex sees a predictable structure.

Gather first:

- The implementation plan (from the current conversation)
- The list of repository files Codex should read before evaluating
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

- `grounding_rules`: plan review drifts into invented code otherwise
- `structured_output_contract`: forces a shape that maps directly to the triage step in §3
- `dig_deeper_nudge`: without it Codex tends to stop at the first plausible concern
- `missing_context_gating`: redirects scope/YAGNI speculation into open questions instead of findings
- `verification_loop`: trims speculative nits before they reach the user
- No `action_safety`: plan review is read-only
- No `completeness_contract`: one pass is sufficient; the plan is small

### 2. Run Codex

```bash
codex exec "<prompt>" < /dev/null -o /tmp/codex-plan-review.md
```

**Important:**

- Always use `< /dev/null` to prevent stdin hanging in background/automated contexts
- Set timeout to 600000ms (10 minutes)
- Use `-o` to capture output to a file for reliable retrieval

### 3. Triage the feedback

Codex evaluates the plan against the code it reads, but lacks project context (design decisions, scope constraints, YAGNI boundaries). Classify each finding under the `finding-triage` SSOT dispositions. The cases that recur in plan review:

- **`actionable`**: a real design flaw that would cause bugs or incorrect behavior
- **`false-positive`**: a concern that doesn't apply given project constraints (e.g., suggesting generalization when only one case exists)
- **`defer`**: valid but out of scope for the current task

A finding whose resolution opens a design question the plan did not settle is `opens-a-question` → fold it back into the research that produced the plan rather than spot-patching the plan text.

Present the triage to the user, not the raw output.

### 4. Update the plan

If actionable findings exist, revise the plan in the conversation and re-present to the user for approval. Re-run Codex on the revised plan only when the revision meaningfully invalidates the prior verdict — e.g., switching to an alternative approach, invariant promotion (a symptom-level finding turned out to require an invariant-level rewrite), or scope shift. This is the triage author's call: Codex returns incremental judgments on the plan as presented, not fundamental-vs-incremental classifications of subsequent revisions, so its verdict label is not a proxy for this decision. Pure in-scope condition incorporation or a single P2 / P3 patch does not warrant re-running. See `research` Step 3.5 for a caller-imposed loop using this trigger.

## What Codex is good at catching in plans

- Format mismatches between producer and consumer functions
- Filtering/branching logic that conflates distinct failure modes
- Missing validation at API boundaries
- Inconsistency between the plan and existing code patterns
- (with the `dig_deeper_nudge` extension above) dead-on-arrival public surface — symbols whose contracts have no current branching consumer
- (with the `dig_deeper_nudge` extension above) shared-scope config reach — a lint / config enabled at a workspace / package / global scope that binds more compilation units (tests, benches, examples, build scripts) than the intended one

## What Codex is bad at in plan review

- Scope judgment (will suggest over-engineering)
- Project-specific constraints (doesn't know what's YAGNI)
- Trade-off decisions (will flag every simplification as a risk)
- Whether a "documented limitation" or "deferred mitigation" in the plan is acceptable or is a self-admission that the plan is mis-scoped — Codex grounds in code, not in scope-vs-contract distinctions

The user makes these calls, not Codex. The `research` Step 3.4 (Reachability check) is the upstream gate for these outward-reach failures; `codex-plan-review`'s extensions above provide redundant code-side checks, but they are not a substitute for Step 3.4.
