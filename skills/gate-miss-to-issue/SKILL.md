---
name: gate-miss-to-issue
description: Promote a late-caught defect — one an earlier gate should have caught — into a development-skills issue proposing a fix to that gate's procedure.
---
# Gate-Miss-to-Issue

A gate's failure is invisible to the gates downstream of it — they judge the product, not which earlier step should have caught the defect. This skill captures that gap as a development-skills issue.

## When to use

- A defect surfaced **later than the earliest gate that could have caught it** — at external review, post-merge, or user pushback.
- Not when every defect was caught at its earliest gate: nothing underperformed.

## Do

- Propose which gate should have caught it — skill + step, or *no existing gate* if none owns the class. This is a hypothesis the issue confirms or redirects, not a blame verdict.
- State the blind spot as a **general class**, not the one token that slipped.
- File the proposal as an issue against `ultimatile/development-skills`, via `file-issue`, with the four points below.
- On recurrence of a class that already has an open issue, comment on it instead of filing a duplicate.

## Don't

- Don't edit the gate's `SKILL.md` inline. File an issue; the fix is deliberated async so the work-repo PR that surfaced the miss is not blocked.
- Don't file for a one-off execution lapse the gate already covers — only for a generalizable procedure gap.
- Don't propose a code change here.
- Don't recurse: this skill has no gate of its own to postmortem.

## Issue content

Hand `file-issue` these four points:

- **Gate (proposed)** — the skill + step you argue should have caught it, or *none yet*; the gate-owner confirms or redirects.
- **Miss** — the defect, and where it was finally caught; link the work-repo PR / issue for provenance.
- **Blind spot** — the generalizable procedure gap.
- **Proposed improvement** — a concrete procedure change (a new sweep, a tightened definition, an added probe class). A proposal; the fix is settled in the issue.

Toolchain names (skills, gates, review tools) are in-context for this repo — it *is* that toolchain — so the issue may reference them freely, unlike work-repo artifacts.
