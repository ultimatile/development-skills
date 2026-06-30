---
name: file-adr
description: Draft an Architecture Decision Record (a timeless decision, distinct from an implementation schedule) and write the file. Use file-issue instead when the artifact is a task list, bug report, or phase plan.
---

# File ADR

Draft a project Architecture Decision Record (ADR) body that matches the project's existing structure and follows a timeless-decision discipline. Show for approval, then write to the project's ADR directory.

## The classification step — MANDATORY before drafting

Before any drafting, classify the topic against this distinction:

| Artifact kind | What it captures | Skill |
| -- | -- | -- |
| **Decision** | A choice between alternatives with context and consequences, expressed in timeless tense. | `file-adr` |
| **Schedule** | When / by whom / in what order something is implemented. Phases, checklists, dates. | `file-issue` |

If the topic mixes both, separate them. The decision goes in the ADR, the implementation schedule goes in an Issue. Do NOT write Phase-N sections inside the ADR — that conflates schedule with decision and ages the document the moment phases complete.

Diagnostic question: read the candidate body imagining the project is two years older and every Phase mentioned has long completed. Does the body still read as a coherent decision record? If no, the body has schedule content that belongs in an Issue.

## Status taxonomy

| Status | Meaning | Body mutability |
| -- | -- | -- |
| **Proposed** | Drafted, under review. Not yet in force. | Mutable until acceptance. |
| **Accepted** | Decision in effect. | **Frozen.** Refinements go in a new ADR or downstream Issue body, not in this file. |
| **Superseded by ADR-NNNN** | Replaced by a later ADR. | Frozen, mark status and cross-link. |
| **Deprecated** | No longer in force, no successor (e.g. constraint went away). | Frozen, mark status only. |
| **Rejected** | Drafted but not adopted. Kept as a record. | Frozen at draft state. |

Lifecycle transitions:

- `Proposed → Accepted` — decision finalized.
- `Proposed → Rejected` — decided against; keep the file as a record of the considered path.
- `Accepted → Superseded by ADR-X` — replaced by a later ADR. Add the cross-link in the status line.
- `Accepted → Deprecated` — no longer relevant, no successor.

Status changes are reserved for decision-lifecycle transitions above. Do not add dated amendment footnotes to an Accepted ADR body. Later clarification, drift, or supplemental decisions belong in a new ADR, a downstream Issue, or an implementing PR description.

## Discipline rules

- **Frozen-after-Acceptance.** Once an ADR is Accepted, its body is not edited for drift, clarification footnotes, or retrospective cleanup. Drift discovered during implementation goes to PR descriptions, Issue bodies, or new ADRs (Superseded / follow-up decision) — never back to the original. Editing an Accepted body rewrites history that commit messages and cross-references already point to.
- **Timeless tense.** Present-tense description of the decision and its consequences. No "this PR will...", no "after Phase 1d...", no "the next step is...".
- **API identifiers only when they are the decision.** ADRs state durable API patterns and any concrete identifiers that are themselves part of the architectural decision. Exhaustive implementation inventories belong in Issues (e.g., the ADR states "each op gets a `*_with_policy` sibling"; the Issue enumerates every concrete op name).
- **Scope-out framing.** Frame out-of-scope items as "decisions this ADR does not commit to" or "out-of-scope design concerns", NOT "Phase N does not cover X".
- **Alternatives.** Each rejected alternative gets a one-line rationale. Table form is conventional.
- **Cross-references.** From ADR to Issue: "tracked in Issue #N". From ADR to ADR: link to file. Issue → ADR cross-references are governed by the project's audience-model rules and may be omitted — check project memory.

## Procedure

### 1. Read the project's existing ADRs

Locate the ADR directory. Default convention is `dev-docs/design/adr/`; check project memory or `CLAUDE.md` for the configured path. If no ADR directory or project convention exists, propose creating `dev-docs/design/adr/` and get user confirmation before making the directory.

```bash
ls <adr-dir>
```

Read the most recent 1–2 ADRs to recover:

- The project's language (English / Japanese / other).
- Section names and structure (e.g., `コンテキスト / 決定 / 代替案 / 帰結` vs. `Context / Decision / Alternatives / Consequences`).
- Header format and metadata fields.
- Numbering pattern (typically zero-padded `NNNN`).
- Filename slug convention (`NNNN-kebab-case-slug.md`).

Match what is already there. Do not impose the skeleton in this skill if the project uses a different shape.

### 2. Determine the new ADR number and status

Take the maximum number from existing ADR filenames and add 1. Match the file-name pattern. If there are no existing ADRs and no project-specific numbering rule exists, start at `0001`.

Determine the intended status before drafting:

- Use `Accepted` only when the user is asking to record a decision already made or explicitly says the decision is accepted.
- Use `Proposed` when the ADR is being prepared for review, the decision is still being evaluated, or the user's intent is ambiguous.
- Do not treat approval to write the file as approval of the architectural decision. File-write approval only means the drafted artifact may be saved.
- Use `Rejected`, `Superseded by ADR-NNNN`, or `Deprecated` only when recording that lifecycle state explicitly.

### 3. Classify (mandatory)

Before drafting body text, answer these explicitly:

- What is the decision being recorded?
- What alternatives were considered, and why are they rejected?
- What are the consequences (API, behavior, design premises)?
- What is explicitly out of scope (= not committed by this ADR)?

If the answer to "what is the decision" reduces to "implement X by Y", the artifact is not an ADR. Stop and use `file-issue` instead.

### 4. Draft

Apply the project's section structure recovered in step 1. A lean fallback skeleton when no project precedent exists:

```
# ADR-NNNN: <topic>

**Status**: Proposed | Accepted | ...
**Date**: YYYY-MM-DD
**Related**: [ADR-NNNN](path) (optional)

## Context

<state of the project, forces driving the decision>

## Decision

<the decision, optionally numbered sub-points>

## Alternatives

| Option | Reason rejected |
|---|---|
| A. ... | ... |

## Consequences

<API impact, behavior changes, design premises, items explicitly not committed>

## References

<related ADRs, Issues, PRs, external sources>
```

### 5. Show for approval

Present the drafted body to the user verbatim. Do not write the file without confirmation.

If the user requests changes, revise and re-show. Do not write a partial draft.

### 6. Write the file

```bash
mkdir -p <adr-dir>                       # idempotent
test ! -e "<adr-dir>/<NNNN>-<slug>.md"   # refuse to clobber
```

Write the approved body to `<adr-dir>/<NNNN>-<slug>.md`. If the target file already exists, surface to the user before proceeding (number collision or accidental re-draft).

### 7. Report

Show the user:

- The new ADR file path and number.
- Any follow-up actions (linking from related Issues, updating the project's ADR index if one exists, marking superseded ADRs).

## Anti-patterns

Do not write into the ADR body:

- **Phase-N sections** (`## Phase 1d の具体的 API`, `## Phase N スコープ外`). Schedule content belongs in Issues.
- **Exhaustive API identifier inventories.** State the durable pattern in the ADR; list implementation inventories in the Issue. Include concrete identifiers only when the identifiers themselves are part of the decision.
- **Time-bounded language.** "Next week", "after the refactor lands", "during Phase 2". Reframe in timeless terms or move to the Issue.
- **"Pending decision" placeholders.** If the decision is not ready, do not draft yet. `Proposed` is for "I am proposing this decision now", not "I will decide later".
- **Re-editing Accepted bodies for drift or amendment footnotes.** Drift goes in a new ADR or in the implementing PR / Issue body.
