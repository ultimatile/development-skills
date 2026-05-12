---
name: research
description: >
  Research a GitHub issue using hypothesis-driven divide-and-conquer — form hypotheses,
  verify them in parallel with subagents, and produce a concrete implementation plan.
  Use this skill when the user wants to investigate an issue before coding, says things like
  "research issue #N", "investigate #N", "analyze issue N", or wants a plan without implementation.
  Accepts an issue number or a free-text description as an argument
  (e.g., /research 42 or /research add retry logic to the API client).
---

# research

Research using hypothesis-driven divide-and-conquer. Do NOT write any production code.

## Step 0 — Determine issue context

Check whether `$ARGUMENTS` is a number (existing issue) or free text (new task).

- **Number** → Read the existing issue using `gh issue view $ARGUMENTS`. Proceed with that issue.
- **Free text** → This is a new task without an existing issue. Use the text as the task description and proceed. An issue will be created in Step 4.

## Step 1 — Read issue/task and form hypotheses

1. If an existing issue, read it with `gh issue view`. If free text, use `$ARGUMENTS` as the task description.
2. Skim the project structure (directory tree, CLAUDE.md, key entry points) — do NOT deep-read files yet
3. **Establish a baseline**: build and run existing tests to record any pre-existing failures. This is essential for distinguishing regressions introduced by your changes from issues that already existed.
4. Form a set of **hypotheses** covering three aspects:
   - **What needs to change**: code modifications required to implement the task
   - **What invariants must hold**: contracts, preconditions, and correctness properties that the change must preserve or establish
   - **What could break**: existing code paths that may be affected, especially where new inputs flow through existing APIs

   Each hypothesis should be a focused, verifiable question, e.g.:
   - "Function `foo()` in `src/bar.rs` needs a new parameter for X"
   - "`bar()` callers assume the return value is sorted — this invariant must be preserved"
   - "The new constructor allows input Y, which flows into `baz()` — need to verify `baz()` handles Y correctly"
   - "The existing `qux()` can be reused for Z with minor modification"
5. **Present hypotheses to the user for approval before proceeding.** The user can judge whether the scope is appropriate, suggest narrowing focus, or split into sub-issues. Do not spawn subagents until the user confirms.

## Step 2 — Verify hypotheses in parallel (subagents)

Spawn a **separate subagent per hypothesis** (or per small group of related hypotheses). Each subagent:

1. Reads only the files relevant to its hypothesis — use targeted Grep/Glob, not exhaustive exploration
2. Confirms or refutes the hypothesis with evidence (exact file paths, line numbers, function signatures)
3. **Trace boundary cases**: check code paths for edge cases such as minimal/maximal input sizes, type variations, and single-element containers. These are common sources of plan-vs-actual divergence.
4. **For "what could break" hypotheses**: identify whether the change is compile-breaking (new required trait method, type change) or silently semantic (same signature, different behavior). Semantic changes require caller-by-caller contract verification — the compiler will not catch them.
5. **For safety-critical paths**: check if any public API has unchecked internal assumptions — e.g., pointer arithmetic trusting an offset, a serializer trusting that field order is stable, or an index computation trusting that data is contiguous. A contract violation at the public boundary silently propagates into these internals and causes damage disproportionate to the apparent change. These paths need the strictest validation.
6. Reports back a concise summary: what was found, what needs to change, and any surprises

**Subagent granularity**: not every hypothesis warrants a subagent. Simple checks (e.g., confirming a file or function exists) can be done directly with Grep/Glob from the main context. Reserve subagents for hypotheses that require reading multiple files or deep analysis.

Subagents run in parallel to maximize efficiency and isolate context consumption.

## Step 3 — Consolidate into implementation plan

After all subagents complete, synthesize their findings into a single implementation plan:

- Checklist of changes with exact file paths, function signatures, and type definitions
- Impact list: every caller affected by the change and its implicit contract (for use in implementation verification)
- Test plan:
  - What invariants the new/changed code must satisfy
  - What tests to add/modify, with expected behavior
  - If the change introduces a new constructor or input path, include tests that pass those inputs through every existing public API that could receive them. A new input path without cross-API tests is incomplete.
- Implementation guards (from verified hypotheses):
  - New invariants that must be enforced with assertions, not comments
  - Paired APIs that must be kept consistent (if one sibling method gets a guard, all siblings need review)
  - Constructor validations required (all accepted parameters must be validated at construction time)
  - State that cannot be reliably inferred from existing fields and needs an explicit disambiguating field
- Conflicts or dependencies between hypotheses (if any)
- Any unresolved questions for the user

### Filter unresolved questions before listing them

Before listing a sub-decision as "unresolved for the user", first try to resolve it from available evidence:

1. **Workspace patterns**. Search the workspace (`rg`, `fd`) for analogous constructs already in use — error types, API shapes, naming conventions, dependency choices. If the workspace consistently does X, that is the answer; do not ask which of {X, Y, Z} the user prefers.
2. **Memory and prior conversation**. Check available memory entries and recent turns for decisions on the same axis (e.g., "the user already ruled out backwards-compat shims while pre-release", "we already established the FFI-completeness rule one commit ago"). Apply those.
3. **Subagent reports**. Re-read the subagent outputs from Step 2. If a subagent has decisively recommended one option with reasoning, treat it as resolved unless the reasoning conflicts with another source.

A sub-decision is genuinely unresolved only when the above sources are **silent or contradictory**. "More than one technically-viable option exists" is not, by itself, an unresolved question — it is an analysis task you owe the user. Listing options with pros/cons in the plan when the evidence already points to one of them wastes the user's bandwidth and signals that you skipped the analysis.

When you do escalate a question, state explicitly what you checked and what was contradictory or silent — this makes the user's decision informed rather than a tiebreaker on data you didn't gather.

Report the plan back to the main context.

## Step 4 — Post plan to GitHub

After the user approves the final plan:

- **Existing issue** (number was given) → Post the plan as a comment using `gh issue comment $ARGUMENTS`
- **New task** (free text was given) → Create a new issue with the plan in the body using `gh issue create`, and report the new issue number to the user

**Important rules for issue creation:**

1. **Write issues in English.** Even if the conversation with the user is in another language, GitHub issue titles and bodies must be in English. The conversation language and the issue language are independent.
2. **Split issues by commit unit.** Each issue should correspond to one atomic, independently committable change. If the plan spans multiple commits (e.g., a prerequisite trait change, then a feature built on it), create separate issues for each commit rather than one monolithic issue. Link dependencies between issues (e.g., "Depends on #N").
