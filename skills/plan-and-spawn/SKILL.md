---
name: plan-and-spawn
description: >
  Decompose an umbrella GitHub issue into one next sub-issue with a
  plan-confirmed, frozen contract body. Use this skill when the user
  wants to advance an umbrella tracking issue by spawning the next
  sub-issue, says "next phase of #N", "spawn the next sub-issue for
  the umbrella", "plan and spawn for #N", or invokes it with an
  umbrella issue number. Operates on one sub-issue per invocation —
  the umbrella is expected to remain partially-completed between
  calls. Skip this skill when the next leaf scope is already obvious
  and the user just wants to start `/research-and-implement` directly
  on a known leaf.
---

# plan-and-spawn

Spawn one next sub-issue from an umbrella issue, with a body that
captures the plan-confirmed contract for that single phase. Stops
after spawning. Does not implement.

## When to use

- The current work is tracked under a multi-phase umbrella issue
  (e.g., a Phases table).
- The next phase scope is not yet captured as its own GitHub issue.
- You want a deterministic gate to decide *what the next sub-issue
  should contain* before code is written.

If the next phase already has a sub-issue (text-ref or otherwise),
skip this skill and run `/research-and-implement <leaf#>` directly.

## Mental model

This skill exists because:

- `/research-and-implement` is umbrella-agnostic by design and
  operates on a single leaf scope.
- Sub-issues are static contract documents, not journals. Their
  body is written once at spawn and **frozen** during implementation.
  Drift accumulates in the PR description / TaskCreate state, not
  in the sub-issue body.
- An umbrella naturally sits in a *partially phase-finished* state
  between sub-issue completions. That is the correct steady state,
  not a problem to fix.

So the lifecycle of a sub-issue is:

```
plan-and-spawn         research-and-implement      review-pipeline
─────────────────      ────────────────────────    ─────────────────
read umbrella           Phase 0 branch baseline    done-check
identify next phase     Phase 1 /research          codex review
research it             Phase 2 /implement         copilot review
codex-plan-review                                  bug-to-contract
user confirm                                       umbrella drift join
spawn sub-issue                                    (Phase 4, conditional)
   (frozen body) ──→  hand off ──→
```

## Procedure

### Step 0 — Read the umbrella

```bash
gh issue view $ARGUMENTS --json number,title,body,state
```

If the issue does not look like an umbrella (no Phases table, no
sub-tasks list, single self-contained scope), stop and tell the
user — `/research-and-implement $ARGUMENTS` is the right entry
point instead.

### Step 1 — Identify the next phase

From the umbrella body:

1. Find the first phase row whose scope is **not yet** captured by
   an open or merged sub-issue (text-ref `(#N)` is the current
   convention; native `subIssues` is **not** consulted because
   `gh` CLI does not surface it).
2. If multiple phases are unspawned, pick the smallest-numbered
   one. State your selection so the user can override.
3. Note the deferrals / out-of-scope items the umbrella has
   already pinned to that phase — they belong in the new sub-issue
   body verbatim.

If every listed phase already has a sub-issue, ask the user
whether new phases need to be added to the umbrella or whether
the umbrella should be closed.

### Step 2 — Research the next phase

Run the equivalent of `/research <next-phase-scope>` with the
phase scope as a free-text task description (not as an issue
number — the issue does not exist yet).

The Research output should produce:

- Concrete file / module surface for the new phase
- Invariants and contract guards that must be encoded
- Test plan (representative + corner + error paths; behavior
  coverage, not code-path coverage)
- Out-of-scope items inherited from the umbrella plus any new
  deferrals discovered during research
- Acceptance criteria

Do not write code. The plan is a draft for review.

### Step 3 — Codex plan review

Run `codex exec` against the draft plan with whatever ADR /
phased-rollout context is needed for the codebase. Triage the
review per `/codex-review` rules (actionable / false-positive /
uncertain). Revise the plan until clean.

### Step 4 — User confirm

Present the revised plan to the user. The user must explicitly
approve before spawning. This is the **plan-confirm gate** — the
sub-issue body is determined by what is approved here.

### Step 5 — Spawn the sub-issue

Create the sub-issue with the approved plan as the body. The body
must contain (and only contain):

1. **Parent reference** — `Parent: #<umbrella>` on the first line.
2. **Goal** — one paragraph stating what the phase delivers.
3. **Scope** — bullet list of in-scope items.
4. **Out of scope** — bullet list of deferrals (umbrella-inherited
   plus any new ones from research).
5. **Acceptance** — bullet list of measurable criteria.

The body is the **frozen static contract**: it represents what
was agreed at this gate. Do not edit it during implementation.
Drift goes elsewhere (PR description, TaskCreate, working notes).

```bash
gh issue create \
  --title "Phase N: <topic>" \
  --body "$(cat <<'EOF'
Parent: #<umbrella>

## Goal
...

## Scope
...

## Out of scope
...

## Acceptance
...
EOF
)"
```

After creation, edit the umbrella body to add the new sub-issue's
number to its phase row in the Phases table. This is the only
permitted text-ref maintenance step on the umbrella during this
skill — design drift from the umbrella's perspective is handled
by `/review-pipeline` Phase 4 at sub-issue close, not here.

### Step 6 — Stop

Report the new sub-issue number and URL to the user. Do **not**
proceed to research-and-implement automatically. The user picks
when to start the leaf cycle (immediately in the same session, or
later).

## What this skill is NOT

- It is not a recursive R&I. It spawns one sub-issue and stops.
- It does not consume the GitHub native sub-issue API. Body
  text-ref remains the SSOT until `gh` CLI catches up with the
  GraphQL `subIssues` feature.
- It does not modify other umbrella body content. Out-of-scope
  deferrals, decisions captured, references — those are the
  umbrella maintainer's responsibility, edited separately.
- It does not check whether implementation has started; it only
  cares about contract spawning.
