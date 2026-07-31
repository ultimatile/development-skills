---
name: finding-triage
description: Single source of truth for per-finding review-triage dispositions — actionable / false-positive / uncertain-validity / opens-a-question → research / invariant-premise-check / defer / waive — what closes each, and response selection for actionable findings. Definition file, not a procedure.
---

# Finding Triage (SSOT)

This skill is **a definition file, not a runnable procedure**. Skills that triage review findings apply these dispositions by reference. Do not copy the class definitions into them; point at them by name.

A reviewer (Codex, Copilot, a fresh-context auditor) produces findings without the project context you hold — test results, design intent, scope constraints, conversation history. Triage is the step that converts a raw finding into a disposition. This file is the catalogue of dispositions, the rules for closing them, and the response-selection rules for actionable findings; none of the three varies by reviewer, so all live in one place.

## Scope: stateless, per-finding

Every disposition here is judged on **one finding in isolation** — no dependence on what other findings said or on prior iterations. Loop-level criteria that depend on history across review iterations (oscillation detection, re-triage carryover policy) are **out of scope for this SSOT** — they belong to whatever orchestrates the review loop. A standalone review run applies these per-finding classes without the loop machinery — which is exactly why the classes cannot live in the loop orchestrator alone.

## The dispositions

Each finding receives exactly one disposition. A finding may be *re-triaged* to a different disposition after investigation (e.g. `uncertain-validity` → `actionable`), but at any moment it holds one.

- **actionable** — a real issue the reviewer correctly identified, whose resolution is a **local edit**: one the run makes directly, needing none of the non-local work that defines `opens-a-question` below, however many sites it touches — `generalize`, `delete`, and `deduplicate` below are local in this sense. Which edit is selected per **Response selection (actionable findings)** below.

- **false-positive** — plausible but wrong given context the reviewer lacked (test results, deliberate design choice, a system constraint that rules out the hypothesized input). Dismiss **with explicit reasoning** stated to the user. Never silently override a finding: false-positive classification is itself a triage step the user can challenge. This should be rare enough to be worth paper-trailing. When the dismissal rests on the behavior of an external system (a markdown renderer, parser, compiler, ABI, API), verify it before dismissing per **Verifying external-system claims** below.

- **uncertain-validity** — you cannot yet tell whether the finding is real. The open question is **validity**. Investigate — read code, run a targeted probe — until it resolves to `actionable` or `false-positive`. When the targeted probe judges an external-system-behavior claim, verify it per **Verifying external-system claims** below. Do not carry an unresolved `uncertain-validity` past the point where a fix would be committed.

- **opens-a-question → research** — the finding **is real**, but its resolution is **non-local**: it needs investigation, a design choice, or a scope judgment beyond a local edit. Both default responses are wrong here:

  - "fix in place" is wrong — the fix is not local.
  - "escalate to the user" is wrong — the resolution is probe-able.

  The correct disposition is to **re-enter `research`** with the finding as the task, then escalate only the genuinely user-owned residue (scope authority, taste, an external constraint). Do not carry an unresolved `opens-a-question` past the point where a fix would be committed.

- **invariant-premise-check** — the finding's *conclusion* may be correct, but its *premise* may be wrong. Applies to claims about mathematical properties, semantic validity, or precondition necessity. Before committing a fix, **verify the premise** — check whether the invariant the finding assumes actually holds, by reading code and tests and running targeted experiments. When the premise is an external-system-behavior claim, verify it per **Verifying external-system claims** below. Resolves to `actionable` (premise holds → fix it) or `false-positive` (premise fails → the finding's conclusion does not follow). The mechanism for verifying the premise is the caller's; this SSOT owns only the class.

- **defer** — the finding is valid and its fix is understood, but it is **out of scope** for the current task. File a **follow-up issue** for it, with the user's approval, and do not fix now. Distinct from `opens-a-question`: here the resolution is known and local; in `opens-a-question` the resolution itself is unknown.

- **waive** — the finding is valid and its fix is understood and local, this run is not to make it, and the user directs that **nothing be carried past this run**: no follow-up issue is filed. Only the user may waive. The waiver carries the reasoning, which states what the fix would cost and, where the finding is `critical`, why shipping the specified behavior wrong on the happy path is acceptable. Stating the cost is a disclosure, not a threshold the disposition tests: what a thin waiver buys is visible in its own reasoning. The finding is closed once that reasoning is recorded with this run's other dispositions.

**Precedence across the three local-fix branches.** `actionable`, `defer` and `waive` all take a valid finding whose fix is understood and local, so a rule is needed to keep them single-valued. Decide first whether this run is to make the fix. It is → `actionable`. It is not → `defer` where the user directs that the finding be carried past this run, `waive` where the user declines to. Every branch turns on a decision the run holds at triage time, never on the act that decision leads to: the edit, the filed issue and the recorded reasoning all land afterwards, and what each discharges is stated under **Closure**. A finding classified by an artifact that does not exist yet would hold no disposition until it did.

## Response selection (actionable findings)

An `actionable` disposition settles validity; it does not settle the edit. Select the edit with the rules below — per-finding and stateless, like every disposition above — and apply it in the current run.

**Inputs**: the finding; the target text; the evidence the run has already produced (test results, executed probes); and the predicate below.

**Predicate**:

- **load-bearing** — does the target text, taken as a whole across every copy the finding concerns, genuinely require the disputed content (e.g. the coverage an enumeration claims, the statement divergent copies make, the behavior a description asserts)? Judge the need for the content itself, not whether deleting one copy happens to leave it stated elsewhere.

**Axes**:

- **severity** — exclusive tiers; take the first that applies. `critical`: the specified behavior is wrong on the happy path. `may-fail`: a failure mode exists. `consistency-only`: behavior is identical under every admissible reading; only descriptions can drift. Severity does not choose the edit — the selection below is severity-independent; its consumer is the `waive` decision, whose reasoning the severity belongs in.
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

The selected edit is applied in the current run; a re-triage out of `actionable` exits instead. Declining the fix is one such re-triage, and which disposition it lands on is the precedence above, not a choice made here — the finding's severity belongs in the reasoning that decision carries, which is where `waive` states what a `critical` one has to account for.

The regeneration signal — whether the target sentence was written to answer a prior finding — is iteration history, out of scope here per **Scope: stateless, per-finding**.

## Closure

A gate whose exit condition is stated as its findings being **closed** closes each one by its disposition; a loop that exits on a count of `actionable` findings is stating a different condition, and this section does not reach it. Four dispositions are **terminal**, and each closes once its own discharge has happened:

- `actionable` — the run applies the response selected above.
- `false-positive` — the run dismisses the finding, on that disposition's own terms.
- `defer` — the follow-up issue is filed, with the user's approval; filing it is what closes the finding.
- `waive` — the user waives it, and only the user may; the reasoning is recorded.

The other three are **transient** and close nothing. `uncertain-validity`, `invariant-premise-check` and `opens-a-question` each name an investigation that must return first, after which the finding re-triages to a terminal disposition. Such a gate reached with a finding still holding one of these has no closure available for it, and must resolve it rather than proceed. Where the investigation cannot return at all — the authoritative implementation is unavailable, the rule text the row would be judged against is missing — only the user may let the gate proceed with the finding still open. That is a decision about the gate, not a disposition of the finding, and it leaves the finding transient.

A dismissal's or a waiver's reasoning is recorded wherever the gate already records that finding's disposition — an audit row's note, a review thread's reply, a check's returned report. Naming that surface is the gate's only closure-side statement; what closes a disposition, and who may close it, is stated here.

## Pre-existing instances do not license dismissal

A finding is not downgraded to `false-positive`, `defer` or `waive` merely because the surrounding code already exhibits the same flaw. Pre-existing instances of a problem are unextracted debt, not a convention that licenses adding another — "matches the surrounding code" describes the debt, it does not dismiss the finding. Dismissal still requires the disposition's own bar: for `false-positive`, context that makes *this* finding wrong; for `defer`, the user's direction to carry it past this run; for `waive`, the user's reasoned decision not to. The mere presence of prior offenders meets none of them.

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
