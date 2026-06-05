---
name: finding-triage
description: Single source of truth for per-finding review-triage dispositions — actionable / false-positive / uncertain-validity / opens-a-question → research / invariant-premise-check / defer. Definition file, not a procedure.
---

# Finding Triage (SSOT)

This skill is **a definition file, not a runnable procedure**. Skills that triage review findings — `codex-review`, `copilot-review`, `codex-plan-review`, `codex-contract-test-review`, `review-pipeline`, and the audit-concern triage in `done-check` / `gh-body-check` — apply these dispositions by reference. Do not copy the class definitions into them; point at them by name.

A reviewer (Codex, Copilot, a fresh-context auditor) produces findings without the project context you hold — test results, design intent, scope constraints, conversation history. Triage is the step that converts a raw finding into a disposition. This file is the catalogue of dispositions; the catalogue does not vary by reviewer, so it lives in one place.

## Scope: stateless, per-finding

Every disposition here is judged on **one finding in isolation** — no dependence on what other findings said or on prior iterations. Loop-level criteria that depend on history across review iterations (oscillation detection, re-triage carryover policy) are **out of scope for this SSOT** and live in `review-pipeline`. A standalone review run (e.g. `codex-review` invoked on its own, outside the pipeline) applies these per-finding classes without the loop machinery — which is exactly why the classes cannot live in `review-pipeline` alone.

## The dispositions

Each finding receives exactly one disposition. A finding may be *re-triaged* to a different disposition after investigation (e.g. `uncertain-validity` → `actionable`), but at any moment it holds one.

- **actionable** — a real issue the reviewer correctly identified, whose resolution is a **local edit**. Fix in place.

- **false-positive** — plausible but wrong given context the reviewer lacked (test results, deliberate design choice, a system constraint that rules out the hypothesized input). Dismiss **with explicit reasoning** stated to the user. Never silently override a finding: false-positive classification is itself a triage step the user can challenge. This should be rare enough to be worth paper-trailing.

- **uncertain-validity** — you cannot yet tell whether the finding is real. The open question is **validity**. Investigate — read code, run a targeted probe — until it resolves to `actionable` or `false-positive`. Do not carry an unresolved `uncertain-validity` past the point where a fix would be committed.

- **opens-a-question → research** — the finding **is real**, but its resolution is **non-local**: it needs investigation, a design choice, or a scope judgment beyond a local edit. Both default responses are wrong here:

  - "fix in place" is wrong — the fix is not local.
  - "escalate to the user" is wrong — the resolution is probe-able.

  The correct disposition is to **re-enter `research`** with the finding as the task, then escalate only the genuinely user-owned residue (scope authority, taste, an external constraint).

- **invariant-premise-check** — the finding's *conclusion* may be correct, but its *premise* may be wrong. Applies to claims about mathematical properties, semantic validity, or precondition necessity. Before committing a fix, **verify the premise** — check whether the invariant the finding assumes actually holds, by reading code and tests and running targeted experiments. Resolves to `actionable` (premise holds → fix it) or `false-positive` (premise fails → the finding's conclusion does not follow). The mechanism for verifying the premise is the caller's (e.g. `review-pipeline` asks Codex a single targeted question); this SSOT owns only the class.

- **defer** — the finding is valid and its fix is understood, but it is **out of scope** for the current task. Record it (follow-up issue, note) and do not fix now. Distinct from `opens-a-question`: here the resolution is known and local, only the *timing* is deferred; in `opens-a-question` the resolution itself is unknown.

## opens-a-question vs uncertain-validity

The two name **different unknowns**:

- `uncertain-validity` — "**is the finding real?**" Validity unknown; resolution (if real) presumed local.
- `opens-a-question` — "the finding **is** real, but its **resolution is non-local**." Validity known; resolution unknown.

A finding can pass through both in sequence: resolve validity first (`uncertain-validity` → real), then, if the fix turns out non-local, re-triage to `opens-a-question`.

## The tell for opens-a-question

An `opens-a-question` finding often first reads as a **user gate** — "ask the user to decide X." The diagnostic: a *genuine* user gate stays a gate after investigation, whereas an `opens-a-question` **dissolves the moment someone investigates** — it was never user-owned. If the escalation would evaporate once a probe runs, route it through `research`, not straight to the user. Escalate only the residue that survives investigation: scope authority, taste, external constraint.
