---
name: file-issue
description: Draft and file a GitHub issue using gh-body-conventions and the issue body skeleton, via the gh-post wrapper.
---

# File Issue

Draft a GitHub issue body that follows the user's conventions, show the draft for approval, then file via `gh`.

## Conventions

Apply the rules in `gh-body-conventions` to the title and body. One issue-specific rule on top of them:

- **Omit empty sections.** If a heading's content would be empty (no bullets, no prose), drop the heading entirely. No `TBD` placeholders, no empty bullet lists, no synthesized filler.

### Length

A typical issue body is 5–25 lines. Longer is fine when warranted (e.g., a design proposal with alternatives), but every paragraph should earn its place. Aim for: problem statement, minimal reproduction or evidence, proposed direction (if any).

## Variants

### Umbrella sub-issue

When the new issue is a phase / sub-issue of an existing umbrella tracking issue, the body shape and title convention differ from a standalone issue.

- **Row.** The umbrella's Phases table row or sub-tasks list item this sub-issue covers: the one the caller hands, or else the one the user confirms. A change at step 5 that moves the sub-issue's work to another row moves the sub-issue to that row. The title and the umbrella edit after filing take this row, and it is "the chosen one" of the "Out of scope" extraction below.
- **First body line.** `Parent: #<umbrella#>`. Always included so tooling can detect the umbrella linkage.
- **Title.** `Phase N: <topic>` when the umbrella uses phase naming; otherwise mirror the umbrella's sub-task naming convention.
- **Body shape.** Goal / Scope / Out of scope / Acceptance (in place of the default problem-statement shape). When the caller hands a finished body, as step 2 defines one, the body after the `Parent:` first line is those of the four sections that have content, derived from the handed body except where the "Out of scope" extraction below says otherwise, followed by the handed body in full, as steps 3 to 5 may still correct it, and then any links step 2 adds; make each change to the plan's content that steps 3 to 5 call for in the handed body rather than in the four sections, and after each change derive again from it the sections that come from it — the sub-issue body is the canonical contract surface, not a thin pointer to a comment elsewhere.
- **"Out of scope" extraction.** When the row is a Phases table row: list only **unspawned sibling phases later than the chosen one**, formatted as `<topic> (Phase <id>)`. The point is to pin scope-creep boundaries against work the umbrella has already promised to a future sub-issue. Do not copy umbrella-wide deferrals shared across all phases (e.g. "1-site DMRG", "opsum DSL"). Already-completed earlier phases are also not listed (the boundary is forward-looking).
- **Frozen-contract discipline.** The sub-issue body is written at file time and not edited during implementation. Drift discovered during implementation goes to the PR's `Plan-vs-actual delta` (and, when a reader genuinely needs it, a `Notes` caveat in the PR body framed as the code's own limitation), never back to the issue body. Editing the body rewrites history that PR titles, commit messages, and `Closes #N` references already point to.

After filing, append the new sub-issue's number to the row the Row bullet settles, whether a Phases table row or a sub-tasks list item. This is the only umbrella-body edit performed at sub-issue spawn time; deeper umbrella drift (decisions captured, out-of-scope changes) is handled later at sub-issue close, not at spawn.

## Procedure

### 1. Confirm scope

Before drafting, identify:

- Target repo (`gh repo view` if unclear).
- Whether this is a bug, feature, design discussion, or umbrella sub-issue. The default body shape covers the first three; umbrella sub-issues use the shape defined in `Variants > Umbrella sub-issue` above.
- Related issues/PRs to link, including those that would obviate or reshape this issue.

### 2. Draft

Produce a title and body following the conventions above.

When the caller hands a finished body, written to be filed as it stands (as `research` hands its plan) rather than points to draft from, that body is the draft: at this step, write the title, add only two things — what the variant in use adds to a handed body, and, after the handed body, links to the related issues and PRs step 1 identified that the handed body does not already name — and do not reshape or shorten the handed body.

**Title** — a single descriptive line under ~70 characters. No leading type prefix unless the repo's existing issues use one.

**Body** — typical structure (adapt as needed):

```
<one-paragraph problem statement using semantic line breaks>

## Context  (optional — only if the reader needs background to follow the body)

<minimal context>

## Reproduction / Evidence  (for bugs)

<commands, inputs, observed vs expected, with code blocks where appropriate>

## Proposal  (optional)

<direction, not full implementation>
```

Section headings are optional for short issues — a 5-line body often needs no headings at all.

### 3. Discharge evidence claims

Discharge every evidence claim in the draft, as `gh-body-conventions` § Evidence claims defines one — across all sections, not only the `## Reproduction / Evidence` slot that asks for commands run and results observed.

Editing the body here is expected; the laundering pass runs on the result.

### 4. Laundering pass — run `gh-body-audit`

Run `gh-body-audit` against the drafted body with artifact kind `issue`. It returns a ✅ / ⚠ status. Mandatory before every `gh-post issue create` / `gh-post issue comment`. Any ⚠ blocks step 5 on `gh-body-audit` step 4's terms.

See `gh-body-audit/SKILL.md` for the procedure.

### 5. Show for approval

Present the laundered draft to the user verbatim before filing. Do not file without confirmation.

If the user requests changes, revise, re-discharge its evidence claims, re-run the laundering pass, and re-show. Do not file partially — the next step runs only after explicit approval.

### 6. File

Write the laundered body to a temp file, then invoke the wrapper:

```bash
gh-post issue create \
  --repo <owner>/<repo> \
  --title "<title>" \
  --body-file /tmp/<descriptive-name>.md
```

Add a `--label` flag to `gh-post issue create` for each label the user asked this issue to carry and each label the target repo states this issue must carry, and no other labels.

For an umbrella sub-issue, then make the umbrella edit that `Variants > Umbrella sub-issue` describes after filing. If that edit fails, do not stop: go on to step 7 and report the failure there with the new issue's number.

### 7. Report

After filing, show the user:

- The issue number and URL.
- A failed umbrella edit from step 6, if any.
- Any follow-up actions (e.g., mentioning in a PR).
