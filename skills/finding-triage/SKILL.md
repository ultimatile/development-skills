---
name: finding-triage
description: Single source of truth for per-finding review-triage dispositions — actionable / false-positive / uncertain-validity / opens-a-question / invariant-premise-check / defer / wontfix — and response selection for actionable findings. Definition file, not a procedure.
---

# Finding Triage (SSOT)

This skill is **a definition file, not a runnable procedure**. Skills that triage review findings apply these dispositions by reference. Do not copy the class definitions into them; point at them by name.

A reviewer (Codex, Copilot, a fresh-context auditor) produces findings without the project context you hold — test results, design intent, scope constraints, conversation history. Triage is the step that converts a raw finding into a disposition. This file is the catalogue of dispositions and the response-selection rules for actionable findings; neither varies by reviewer, so both live in one place.

## Scope: stateless, per-finding

Every disposition here is judged on **one finding in isolation** — no dependence on what other findings said or on prior iterations. Loop-level criteria that depend on history across review iterations (oscillation detection, re-triage carryover policy) are **out of scope for this SSOT** — they belong to whatever orchestrates the review loop. A standalone review run applies these per-finding classes without the loop machinery — which is exactly why the classes cannot live in the loop orchestrator alone.

## The dispositions

Each finding receives exactly one disposition. A finding may be *re-triaged* to a different disposition after investigation (e.g. `uncertain-validity` → `actionable`), but at any moment it holds one.

- **actionable** — a real issue the reviewer correctly identified, whose resolution is a **local edit**: one the run makes directly, needing none of the non-local work that defines `opens-a-question` below, however many sites it touches — `generalize`, `delete`, and `deduplicate` below are local in this sense. Which edit is selected per **Response selection (actionable findings)** below.

- **false-positive** — plausible but wrong given context the reviewer lacked (test results, deliberate design choice, a system constraint that rules out the hypothesized input). Dismiss **with explicit reasoning** stated to the user. Never silently override a finding: false-positive classification is itself a triage step the user can challenge. This should be rare enough to be worth paper-trailing. When the dismissal rests on the behavior of an external system (a markdown renderer, parser, compiler, ABI, API), verify it before dismissing per **Verifying external-system claims** below.

- **uncertain-validity** — you cannot yet tell whether the finding is real. The open question is **validity**. Investigate — read code, run a targeted probe — until it resolves to `actionable` or `false-positive`. When the targeted probe judges an external-system-behavior claim, verify it per **Verifying external-system claims** below. Do not carry an unresolved `uncertain-validity` past the point where a fix would be committed.

- **opens-a-question** — the finding **is real**, but its resolution is **non-local**: it needs investigation, a design choice, or a scope judgment beyond a local edit. Both default responses are wrong here:

  - "fix in place" is wrong — the fix is not local.
  - "escalate to the user" is wrong — the resolution is probe-able.

  The correct handling is to **re-enter `research`** with the finding as the task, then escalate only the genuinely user-owned residue (scope authority, taste, an external constraint).

- **invariant-premise-check** — the finding's *conclusion* may be correct, but its *premise* may be wrong. Applies to claims about mathematical properties, semantic validity, or precondition necessity. Before committing a fix, **verify the premise** — check whether the invariant the finding assumes actually holds, by reading code and tests and running targeted experiments. When the premise is an external-system-behavior claim, verify it per **Verifying external-system claims** below. Resolves to `actionable` (premise holds → fix it) or `false-positive` (premise fails → the finding's conclusion does not follow). The mechanism for verifying the premise is the caller's; this SSOT owns only the class.

- **defer** — the finding is valid and its fix is understood, but it is **out of scope** for the current task. Record it (follow-up issue, note) and do not fix now. Distinct from `opens-a-question`: here the resolution is known and local, only the *timing* is deferred; in `opens-a-question` the resolution itself is unknown. Distinct from `wontfix`: there the user directs that nothing be carried past this run.

- **wontfix** — the finding is valid and its fix is understood, and the user directs that it be closed within this run: no fix made, and no follow-up filed to carry it past. The decision is the user's alone; the run records the disposition and the user's reasoning, which states what the fix would have cost and, where the finding was assigned a severity, that tier. Both a reason to postpone and a reason to abandon can hold of one finding; where they do, the user's direction, not the reason, selects.

## Response selection (actionable findings)

An `actionable` disposition settles validity; it does not settle the edit. Select the edit with the rules below — per-finding and stateless, like every disposition above — and apply it in the current run.

**Inputs**: the finding; the target text; the evidence the run has already produced (test results, executed probes); and the predicate below.

**Predicate**:

- **load-bearing** — does the target text, taken as a whole across every copy the finding concerns, genuinely require the disputed content (e.g. the coverage an enumeration claims, the statement divergent copies make, the behavior a description asserts)? Judge the need for the content itself, not whether deleting one copy happens to leave it stated elsewhere.

**Axes**:

- **severity** — exclusive tiers; take the first that applies. `critical`: the specified behavior is wrong on the happy path. `may-fail`: a failure mode exists. `consistency-only`: behavior is identical under every admissible reading; only descriptions can drift. Severity does not choose the edit — the selection below is severity-independent. Severity's consumer is the `wontfix` decision.
- **case-space** — `bounded` / `unbounded`; defined whenever the finding is a coverage-gap claim — the rule's domain may be stated as an enumeration, stated as a prose predicate, or left implicit (`n-a` for findings that claim no coverage gap). A domain not shown bounded (finite, closed membership) is classified `unbounded`; an implicit domain is never shown bounded.

**Response kinds**:

- **fix-in-place** — the local edit the finding asks for.
- **generalize** — restate the coverage intensionally: replace an enumeration with its defining predicate, or correct a stated predicate so it covers the domain.
- **delete** — remove the claim that generates the disputed surface, together with the references to it.
- **deduplicate** — collapse divergent copies into one statement plus references.

**Selection — which edit.** Dispatch on the finding's class; take the first branch that fits:

- **Coverage-gap claim** (case-space is defined), `bounded` → add the missing case (`fix-in-place`) when load-bearing is true; `delete` the claim that declares the domain when it is false.
- **Coverage-gap claim**, `unbounded` → never add the case, at any severity. `generalize` when load-bearing is true; `delete` when it is false. When `generalize` is selected but the defining predicate is not derivable from the finding and the target text, re-triage to `opens-a-question` instead.
- **Drift between copies of one rule** — the same rule stated in more than one place, whether or not the drift affects behavior → `deduplicate` when load-bearing is true (the collapsed statement carries the corrected content); `delete` when it is false. Rewriting the divergent copies in place is not an outcome: it opens new consistency surfaces, and drift between N copies costs N comparisons to detect while a broken reference costs one grep.
- **Otherwise** (a statement misdescribes the behavior it annotates, a wrong action, a typo) → `fix-in-place`: correct it, when load-bearing is true; `delete` when it is false.

The selected edit is applied in the current run; a re-triage out of `actionable` exits instead. Declining the fix is such an exit; this section does not settle which disposition a declined finding takes, and the entry conditions in **The dispositions** above govern that question. A finding at `critical` does not ordinarily warrant `wontfix`.

The regeneration signal — whether the target sentence was written to answer a prior finding — is iteration history, out of scope here per **Scope: stateless, per-finding**.

## Pre-existing instances do not license dismissal

A finding is not downgraded to `false-positive`, `defer` or `wontfix` merely because the surrounding code already exhibits the same flaw. Pre-existing instances of a problem are unextracted debt, not a convention that licenses adding another — "matches the surrounding code" describes the debt, it does not dismiss the finding. Dismissal still requires the disposition's own bar: for `false-positive`, context that makes *this* finding wrong; for `defer`, an explicit out-of-scope decision; for `wontfix`, the user's direction to close it, with the cost of the fix stated. The mere presence of prior offenders meets none of them.

## opens-a-question vs uncertain-validity

The two name **different unknowns**:

- `uncertain-validity` — "**is the finding real?**" Validity unknown; resolution (if real) presumed local.
- `opens-a-question` — "the finding **is** real, but its **resolution is non-local**." Validity known; resolution unknown.

A finding can pass through both in sequence: resolve validity first (`uncertain-validity` → real), then, if the fix turns out non-local, re-triage to `opens-a-question`.

## The tell for opens-a-question

An `opens-a-question` finding often first reads as a **user gate** — "ask the user to decide X." The diagnostic: a *genuine* user gate stays a gate after investigation, whereas an `opens-a-question` **dissolves the moment someone investigates** — it was never user-owned. If the escalation would evaporate once a probe runs, route it through `research`, not straight to the user. Escalate only the residue that survives investigation: scope authority, taste, external constraint.

## Verifying external-system claims

Three dispositions can rest a committed verdict on a claim about an **external system's behavior** (a markdown renderer, parser, compiler, ABI, API, runtime): `false-positive` (the system rules out the input), `uncertain-validity` (a targeted probe judges the claim), and `invariant-premise-check` (the premise is an external-system fact) — including when the verdict is `actionable` and ships a fix.

**Requirement.** Before committing a verdict that rests on such a claim, run the finding's input through that system's **authoritative implementation** (`gh api /markdown` for GitHub rendering; the actual compiler / parser / runtime otherwise). A local proxy (a regex standing in for a renderer, a reimplemented parser) or a hand-derivation is built from your own mental model of how the system behaves — the same model that produced your reading — so it can only confirm that reading; only the authoritative implementation can test whether the reading holds.

**Scope.** This fires only for claims about an external system's *behavior*, and only at the point a verdict is committed (a fix shipped, a finding dismissed) — not for intermediate reasoning.

**When the authoritative implementation is unavailable or too costly to run.** Cost decides whether you can pay to confirm; it never makes a proxy into sufficient evidence. If you cannot run the authoritative implementation, the claim does not resolve via a proxy: the finding stays unresolved rather than advancing to a committed verdict, and whether the verification is worth its cost — or whether an alternative authoritative source exists — escalates to the user.
