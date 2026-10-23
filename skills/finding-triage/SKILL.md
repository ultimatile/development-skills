---
name: finding-triage
description: Single source of truth for per-finding review-triage dispositions and response selection for actionable findings, which the review and audit skills apply by reference.
---

# Finding Triage (SSOT)

Skills that triage review findings apply these dispositions by reference; do not copy the class definitions into them, point at them by name.

A reviewer (Codex, Copilot, a fresh-context auditor) produces findings without the project context you hold — test results, design intent, scope constraints, conversation history. Triage is the step that converts a raw finding into a disposition. This file is the catalogue of dispositions and the response-selection rules for actionable findings; neither varies by reviewer.

## Scope: stateless, per-finding

Every disposition here is judged on **one finding in isolation** — no dependence on what other findings said or on prior iterations. Loop-level criteria that depend on history across review iterations (oscillation detection, re-triage carryover policy) are **out of scope for this SSOT** — they belong to whatever orchestrates the review loop. A standalone review run applies these per-finding classes without the loop machinery — which is exactly why the classes cannot live in the loop orchestrator alone.

## The dispositions

Each finding receives exactly one disposition. A finding may be *re-triaged* to a different disposition after investigation (e.g. `uncertain-validity` → `actionable`), but at any moment it holds one. What an entry tells the run to do with a finding binds only while the finding holds that entry.

- **actionable** — a real issue the reviewer correctly identified, whose resolution is a **local edit**: one the run makes directly, needing none of the non-local work that defines `opens-a-question` below, however many sites it touches — `generalize`, `delete`, and `deduplicate` below are local in this sense. Which edit is selected per **Response selection (actionable findings)** below. A run that judges the edit out of scope for the current task asks the user whether to make it in this run, and makes it only if the user says to.

- **false-positive** — plausible but wrong given context the reviewer lacked (test results, deliberate design choice, a system constraint that rules out the hypothesized input), or a finding that **Findings that ask for a guard** below dismisses. Dismiss **with explicit reasoning** stated to the user. Never silently override a finding: false-positive classification is itself a triage step the user can challenge. Outside **Findings that ask for a guard** below, this should be rare enough to be worth paper-trailing. When the dismissal rests on the behavior of an external system (a markdown renderer, parser, compiler, ABI, API), verify it before dismissing per **Verifying external-system claims** below.

- **uncertain-validity** — you cannot yet tell whether the finding is real. The open question is **validity**. Investigate — read code, run a targeted probe — until it resolves to `actionable` or `false-positive`, except where **Findings that ask for a guard** below names a different exit. When the targeted probe judges an external-system-behavior claim, verify it per **Verifying external-system claims** below. Do not carry an unresolved `uncertain-validity` past the point where a fix would be committed.

- **opens-a-question** — the finding **is real**, but its resolution is **non-local**: it needs investigation or a design choice beyond a local edit. Both default responses are wrong here:

  - "fix in place" is wrong — the fix is not local.
  - "escalate to the user" is wrong — the resolution is probe-able.

  The correct handling is to **re-enter `research`** with the finding as the task, then escalate only the genuinely user-owned residue (scope authority, taste, an external constraint).

- **invariant-premise-check** — the finding's *conclusion* may be correct, but its *premise* may be wrong. Applies to claims about mathematical properties, semantic validity, or precondition necessity. Before committing a fix, **verify the premise** — check whether the invariant the finding assumes actually holds, by reading code and tests and running targeted experiments. When the premise is an external-system-behavior claim, verify it per **Verifying external-system claims** below. Once the premise is verified, the finding resolves to `actionable` (premise holds → fix it) or `false-positive` (premise fails → the finding's conclusion does not follow). The mechanism for verifying the premise is the caller's; this SSOT owns only the class.

- **defer** — the finding is valid and its fix is understood, and the user directs that it not be fixed in this run, by any direction other than one that meets `wontfix` below. A fix is understood, here and in `wontfix`, exactly when it is the local edit `actionable` names. Keep a follow-up for it and do not fix now; a follow-up is an issue or a note that carries the finding to a later fix. Entering this entry or `wontfix` takes the finding out of `actionable`.

- **wontfix** — the finding is valid and its fix is understood, and the user directs both that it not be fixed in this run and that no follow-up be kept. The decision is the user's alone; the run records the disposition and the user's reasoning, which states what the fix would have cost. Both a reason to postpone and a reason to drop the fix can hold of one finding; where they do, the user's direction, not the reason, selects.

- **abandoned** — the user directs that no further work be done on the finding in this run, and either whether it is valid is not known, or it is valid and its fix is not the local edit `actionable` names. The decision is the user's alone; the run records the disposition and the user's reasoning, and keeps a follow-up where the user directs that one be kept. Meeting this condition takes a finding out of `uncertain-validity`, `invariant-premise-check` or `opens-a-question`, whichever it held.

## Closed findings

A finding is **closed** when it holds `false-positive`, `defer`, `wontfix` or `abandoned` and the run has done what that entry directs.

## Taking a finding as its disposition directs

Taking a finding as its disposition directs follows it through every re-triage that work produces, and ends when the finding is closed or the edit that resolves it has been made.

## Response selection (actionable findings)

An `actionable` disposition settles validity; it does not settle the edit. Select the edit with the rules below — per-finding and stateless, like every disposition above.

**Inputs**: the finding; the target text; the evidence the run has already produced (test results, executed probes); and the predicate below.

**Predicate**:

- **load-bearing** — does the target text, taken as a whole across every copy the finding concerns, genuinely require the disputed content (e.g. the coverage an enumeration claims, the statement divergent copies make, the behavior a description asserts)? Judge the need for the content itself, not whether deleting one copy happens to leave it stated elsewhere.

**Axes**:

- **severity** — exclusive tiers; take the first that applies. `critical`: the specified behavior is wrong on the happy path. `may-fail`: a failure mode exists. `consistency-only`: behavior is identical under every admissible reading; only descriptions can drift. Severity does not choose the edit — the selection below is severity-independent. Severity bears instead on declining the fix: a finding at `critical` does not ordinarily warrant `wontfix`.
- **case-space** — `bounded` / `unbounded`; defined whenever the finding is a coverage-gap claim — the rule's domain may be stated as an enumeration, stated as a prose predicate, or left implicit (`n-a` for findings that claim no coverage gap). A domain not shown bounded (finite, closed membership) is classified `unbounded`; an implicit domain is never shown bounded.

**Response kinds**:

- **fix-in-place** — the local edit the finding asks for.
- **generalize** — restate the coverage intensionally: replace an enumeration with its defining predicate, or correct a stated predicate so it covers the domain.
- **delete** — remove the claim that generates the disputed surface, together with the references to it.
- **deduplicate** — collapse divergent copies into one statement plus references.

**Selection — which edit.** Dispatch on the finding's class; take the first branch that fits:

- **Coverage-gap claim** (case-space is defined), `bounded` → add the missing case (`fix-in-place`) when load-bearing is true; `delete` the claim that declares the domain when it is false.
- **Coverage-gap claim**, `unbounded` → never add the case, at any severity. `generalize` when load-bearing is true; `delete` when it is false. When `generalize` is selected but the defining predicate is not derivable from the finding and the target text, re-triage to `opens-a-question` instead.
- **Drift between copies of one rule** — the same rule stated in more than one place, whether or not the drift affects behavior → `deduplicate` when load-bearing is true (the collapsed statement carries the corrected content); `delete` when it is false. Rewriting the divergent copies in place is not an outcome.
- **Otherwise** (a statement misdescribes the behavior it annotates, a wrong action, a typo) → `fix-in-place`: correct it, when load-bearing is true; `delete` when it is false.

The selected edit is applied in the current run, subject to the question `actionable` puts to the user for an out-of-scope edit; a re-triage out of `actionable` exits instead. Declining the fix is such an exit; this section does not settle which disposition a declined finding takes, and the entry conditions in **The dispositions** above govern that question.

The regeneration signal — whether the target sentence was written to answer a prior finding — is iteration history, out of scope here per **Scope: stateless, per-finding**.

## Findings that ask for a guard

When the work under review follows a plan that carries a failure-scenario table (`research`'s Failure scenarios section), a finding that asks the change to add a guard, a validation, or other defensive handling for an input or an operation is judged by that table before the dispositions above are applied. The work follows the plan itself in a review of that plan, and the plan it implements in a review of a change.

A finding about several scenarios is split into one finding per scenario, each triaged on its own. Take the scenario's row, or, for a scenario the table does not list, its Covered value worked out by the Failure scenarios section's rules. While the finding and the evidence the run holds do not settle a fact the next step needs, whether one the Covered value taken above rests on or one the finding states against a cell of the row, the finding is `uncertain-validity`, and once investigation settles it the finding returns here rather than taking that entry's exits. Then take the first that fits:

- The finding states a fact, settled as holding, that makes a cell of the scenario's row false → the row does not decide; the dispositions above apply.
- The scenario is not covered → `false-positive`, stating the axis values as the reasoning.
- Otherwise → the dispositions above, as for any finding. Neither a gate's own list of typical false positives nor the `false-positive` entry's system-constraint ground dismisses such a finding on the ground that its input cannot occur, since Covered has settled that.

## Pre-existing instances do not license dismissal

A finding is not downgraded to `false-positive`, `defer`, `wontfix` or `abandoned` merely because the surrounding code already exhibits the same flaw. Pre-existing instances of a problem are unextracted debt, not a convention that licenses adding another — "matches the surrounding code" describes the debt, it does not dismiss the finding. Dismissal still requires the disposition's own bar: for `false-positive`, context that makes *this* finding wrong, or the dismissal **Findings that ask for a guard** makes; for `defer`, `wontfix` and `abandoned`, the user's direction the entry names.

## opens-a-question vs uncertain-validity

The two differ in **what is known**:

- `uncertain-validity` — "**is the finding real?**" Validity unknown.
- `opens-a-question` — "the finding **is** real, but its **resolution is non-local**." Validity known.

A finding can pass through both in sequence: resolve validity first (`uncertain-validity` → real), then, if the fix turns out non-local, re-triage to `opens-a-question`.

## The tell for opens-a-question

An `opens-a-question` finding often first reads as a **user gate** — "ask the user to decide X." The diagnostic: a *genuine* user gate stays a gate after investigation, whereas an `opens-a-question` **dissolves the moment someone investigates** — it was never user-owned. If the escalation would evaporate once a probe runs, route it through `research`, not straight to the user.

## Verifying external-system claims

What follows binds a verdict that rests on a claim about an **external system's behavior** (a markdown renderer, parser, compiler, ABI, API, runtime), whichever disposition that verdict carries.

**Requirement.** Before committing a verdict that rests on such a claim, run the finding's input through that system's **authoritative implementation** (`gh api /markdown` for GitHub rendering; the actual compiler / parser / runtime otherwise). A local proxy (a regex standing in for a renderer, a reimplemented parser) or a hand-derivation is built from your own mental model of how the system behaves — the same model that produced your reading — so it can only confirm that reading; only the authoritative implementation can test whether the reading holds.

**Scope.** This fires only for claims about an external system's *behavior*, and only at the point a verdict is committed (a fix shipped, a finding dismissed) — not for intermediate reasoning.

**When the authoritative implementation is unavailable or too costly to run.** Cost decides whether you can pay to confirm; it never makes a proxy into sufficient evidence. If you cannot run the authoritative implementation, the claim does not resolve via a proxy: the finding stays unresolved rather than advancing to a committed verdict, and whether the verification is worth its cost — or whether an alternative authoritative source exists — escalates to the user.
