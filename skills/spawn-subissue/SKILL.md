---
name: spawn-subissue
description: >
  Spawn one next sub-issue from an umbrella tracking issue, populating
  body sections by extracting verbatim from the umbrella's Phases
  table / Decisions captured / Out of scope. Performs no research, no
  plan review, and no derivation at spawn time — verification happens
  later in the leaf cycle (`research-and-implement-egel`) against the
  spawned sub-issue. Use when the umbrella is trustworthy enough that
  a clerical spawn suffices and the plan-confirm gate at spawn time
  is undesirable. Invoked as `/spawn-subissue <umbrella#>` or when the
  user says "spawn the next sub-issue from the umbrella" / "issue
  spawn for #N".
---

# spawn-subissue

Spawn one next sub-issue from an umbrella tracking issue, with body
sections extracted from the umbrella and reformulated for leaf scope.
No research, no plan review, no derivation — verification belongs to
the leaf cycle.

## When to use vs `plan-and-spawn`

| Skill | Spawn-time work | Where verification lives |
|---|---|---|
| `plan-and-spawn` | Research + codex plan review; freezes a plan-confirmed contract into the sub-issue body | Spawn-time (frozen at spawn) |
| `spawn-subissue` | Clerical extraction from umbrella; no research | Leaf cycle (`research-and-implement-egel`) |

`plan-and-spawn` remains the conventional choice. `spawn-subissue` is
for the egel-leaning workflow where:

- The umbrella is detailed enough that a clerical spawn carries
  sufficient contract.
- The leaf cycle will run derivational + empirical verification
  against the spawned sub-issue (covers specific-example claim
  derivation, runtime probes, etc.).
- Front-loading research at spawn time would just be redone in the
  leaf cycle, so it is wasted effort.

When in doubt, prefer `plan-and-spawn`.

## Procedure

### Step 0 — Read the umbrella

```bash
gh issue view <umbrella#> --json number,title,body,state
```

If the issue does not look like an umbrella (no Phases table, no
sub-tasks list, single self-contained scope), stop and tell the user
— `/research-and-implement <umbrella#>` (or `-egel`) is the right
entry point instead.

### Step 1 — Identify the next phase

From the umbrella body:

1. Find the first phase row whose scope is **not yet** captured by
   an open or merged sub-issue (text-ref `(#N)` is the current
   convention; native `subIssues` is not consulted because `gh` CLI
   does not surface it).
2. If multiple phases are unspawned, pick the smallest-numbered one.
   State your selection so the user can override.

If every listed phase already has a sub-issue, ask the user whether
new phases need to be added to the umbrella or whether the umbrella
should be closed.

### Step 2 — Extract sections from the umbrella, reformulated for leaf scope

Extract umbrella content for the chosen phase and reformulate it for
the leaf's scope. Drop program-level framing ("subsequently", "across
phases"). Do not invent content the umbrella did not promise. Do not
weaken load-bearing technical terms.

- **Parent reference** — `Parent: #<umbrella>` on the first line.
  Always included.
- **Goal** — one sentence / paragraph from the umbrella's phase row
  description.
- **Scope** — bullets drawn from the umbrella's phase row plus any
  sub-table comment the umbrella references for that phase.
- **Out of scope** — bullets drawn from umbrella sub-table rows for
  **unspawned sibling phases later than the chosen one**, formatted
  as `<topic> (Phase <id>)`. The point is to pin scope-creep
  boundaries against work the umbrella has already promised to a
  future sub-issue. Umbrella-level deferrals shared across all
  phases (e.g. "1-site DMRG", "opsum DSL") are NOT copied — they
  live on the parent issue, and duplicating them adds noise without
  information. Already-completed earlier phases are also not
  listed (the boundary is forward-looking; nobody re-runs a closed
  phase by accident). If no later-than-self phase remains
  unspawned, omit the section entirely.
- **Acceptance** — bullets drawn from the umbrella's phase row
  acceptance criteria.

**Section omission rule.** If a section's extracted content is empty
(the umbrella is silent on it for this phase), **omit the section
entirely** — do not write the heading. No `TBD` placeholders, no
empty bullet lists, no synthesized content. The leaf-cycle research
is responsible for generating any section the umbrella did not
prescribe; making that absence visible (rather than papering over it
with `TBD`) is the point.

The clerical-extraction discipline produces back-pressure on
umbrella quality: a thin umbrella spawns a thin sub-issue, which
makes the leaf cycle's first action obvious — fill the gap, in the
sub-issue's research phase, not here.

### Step 3 — User confirm

Present the extracted sections to the user. The user can:

- Accept and proceed.
- Adjust which umbrella content maps to which section (the
  extraction is a heuristic; the user is authoritative).
- Cancel and run `/plan-and-spawn` instead, if research at spawn
  time is wanted after all.

### Step 4 — Spawn the sub-issue

Follow the conventions defined in `file-issue`.

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

Omitted sections (per Step 2) are not present in the body.

After creation, edit the umbrella body to add the new sub-issue's
number to its phase row in the Phases table. This is the only
permitted text-ref maintenance step on the umbrella during this
skill — design drift from the umbrella's perspective is handled by
`/review-pipeline` Phase 4 at sub-issue close, not here.

### Step 5 — Stop

Report the new sub-issue number and URL to the user. Do not proceed
to leaf-cycle research automatically. The user picks when to run
`/research-and-implement-egel <leaf#>` (or the non-egel variant).

## What this skill is NOT

- Not a research wrapper. Verification (empirical and derivational)
  belongs to the leaf cycle.
- Not a replacement for `plan-and-spawn`. Both coexist; choose by
  workflow preference.
- Does not consume the GitHub native sub-issue API. Body text-ref
  remains the SSOT.
- Does not modify umbrella body content beyond appending the new
  text-ref to the relevant phase row. Out-of-scope deferrals,
  decisions captured, references — those are the umbrella
  maintainer's responsibility, edited separately.
