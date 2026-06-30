---
name: codex-contract-test-review
description: Narrow Codex pass on a newly added contract test, verifying it is not tautological and would fail on the original buggy implementation. Lightweight alternative to the full codex-review / copilot-review loop.
---

# Codex Contract-Test Review

A focused Codex pass that asks one question: **does this test express the contract its name/comment claims?** Secondary: any critical bug in the test code itself.

This is *not* a full review — alternative test designs, additional test suggestions, and stylistic nits are explicitly out of scope.

## Procedure

### 1. Gather inputs

| Input | What to collect |
| -- | -- |
| Original finding | The review comment / bug report that triggered the contract elevation. 1–2 sentences or quoted text. |
| Claimed contract | One sentence — the implicit specification the test is asserting (the output of `bug-to-contract` Step 2). |
| New test location | `file:line` range of the added test. |
| Implementation under test | `file:line` of the code the contract applies to. |
| Specific questions (optional) | 0–3 narrow questions if there is genuine uncertainty. |

### 2. Build the prompt

Use the XML-block template below. Drop blocks that do not fit; keep order stable.

```xml
<task>
Review the newly added contract test against the claimed contract and
the implementation it covers.

Primary check: does the test actually express the claimed contract —
i.e., would it fail on the buggy implementation that motivated the
contract, and does it visit a representative input space rather than
only degenerate / identity / size-1 cases?

Secondary check: any critical bug in the test code itself (P1 only —
ignore stylistic concerns).

Original finding:
<FINDING_TEXT>

Claimed contract (one sentence):
<CONTRACT_STATEMENT>

New test:
<TEST_FILE_LINES>

Implementation under test:
<IMPL_FILE_LINES>

Specific questions (optional):
<EVALUATION_QUESTIONS>
</task>

<grounding_rules>
Read the cited file:line ranges before evaluating.
Do not invent file names, function signatures, or behaviors.
Do not conflate the test's name or comment with the contract — verify
that the assertions actually check the contract, not just that the
docstring claims to.
If a point is an inference rather than a verified fact, label it as
such.
</grounding_rules>

<structured_output_contract>
Return:
1. verdict — one of: approve / approve with conditions / reject
2. primary findings (max 3) — contract-expression problems. Tag each
   [P1/P2] with file:line, and state explicitly: "would this test
   fail on the original buggy implementation? yes / no / unclear"
3. secondary findings (max 2) — P1 critical bugs in the test code
   only. Drop P2/P3 / stylistic.
4. open questions you could not resolve from the repository alone
Total: at most 5 findings across primary + secondary.
Keep the output compact. Do not restate the test or the contract.
</structured_output_contract>

<dig_deeper_nudge>
Beyond a surface read, check for:
- tautology: the assertion is trivially true regardless of the bug
  (e.g., comparing a value to itself, asserting a property the type
  system already enforces)
- degenerate-input-only coverage: identity matrix, size-1 / 1×1,
  all-zero, all-equal, diagonal-only, when the implementation
  handles general inputs
- wrong invariant: the test asserts a property different from the
  one the contract claims (e.g., contract is "layout-invariance" but
  the test only checks one layout)
- error / cleanup paths uncovered: the implementation has fallible
  or cleanup paths but the test only exercises the happy path
- contract narrower than the bug: the test covers one instance of
  the bug class but not the class itself
</dig_deeper_nudge>

<missing_context_gating>
Do not guess project constraints, YAGNI scope, or design intent.
If a finding depends on such context, list it under open questions
instead of findings.
Do not propose alternative test designs.
Do not suggest additional tests beyond what is needed to express
the stated contract.
</missing_context_gating>

<verification_loop>
Before finalizing, verify that each finding is material (would let
the original bug class slip through, or would cause incorrect test
behavior) and anchored in code you actually read.
Drop speculative or stylistic nits.
If the test correctly expresses the contract and no critical bug is
found, return verdict = approve and stop — do not synthesize
findings to fill the slots.
</verification_loop>
```

Block selection rationale:

- `grounding_rules`: prevents the reviewer from trusting the test name / docstring instead of reading the assertions
- `structured_output_contract`: hard caps (max 3 primary, max 2 secondary, max 5 total) keep the output narrow and triageable
- `dig_deeper_nudge`: enumerates the failure modes that contract tests typically fall into — without this list the reviewer tends to stop at the first plausible concern
- `missing_context_gating`: forbids "you should also test X" creep — depth control's main lever
- `verification_loop`: explicit early-exit clause — without it the reviewer will manufacture findings to fill the structured slots
- No `action_safety`: read-only review
- No `completeness_contract`: scope is one test addition; one pass is sufficient

### 3. Run Codex

```bash
codex exec "<prompt>" < /dev/null -o /tmp/codex-contract-test-review.md
```

- Always use `< /dev/null` to prevent stdin hanging in background / automated contexts
- Set timeout to 600000ms (10 minutes); typical run is 30s–2min
- Use `-o` to capture output for reliable retrieval

### 4. Triage the feedback

Classify each finding under the `finding-triage` SSOT dispositions, same as `codex-review` and `codex-plan-review`. The cases that recur here:

- **`actionable`**: a real contract-expression flaw or critical bug that would let the original bug class through
- **`false-positive`**: a concern that doesn't apply given project context the reviewer can't see
- **`defer`**: out of scope for the current contract test (e.g., expanding to a different contract)

Present the triage to the user, not the raw output.

### 5. Apply or push

- If actionable findings exist: revise the test, then re-run this skill once. One re-review iteration is the cap — repeated iteration on a single contract test signals the contract itself is unclear; escalate to the user instead of looping.
- If clean: proceed to `/stage-commit-push` (or whatever the caller's commit step is).

## What this skill is bad at

- Project-specific scope decisions (will defer to open questions)
- Trade-off judgments about test coverage breadth (the user makes these calls)
- Anything outside the test-vs-contract relationship — for full diff review, use `codex-review` instead
