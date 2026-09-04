---
name: file-pullreq
description: Draft and file a GitHub PR using gh-body-conventions and the PR body skeleton, via the gh-post wrapper. Supports a gate mode that stops at user approval.
---

# File Pull Request

Draft a GitHub PR title and body that follow the user's conventions, show the draft for approval, then file via `gh` (or, in gate mode, hand off to a caller).

## Conventions

Apply the rules in `gh-body-conventions` to both the title and body. The PR-specific point to reinforce:

- **Semantic line breaks, not column wrapping.** This is the user's most-corrected formatting habit on PR bodies — commit-body-style hard wrapping renders as ragged text on GitHub's wide viewport.

### Length

A typical PR body is 10–40 lines pre-merge, plus a plan-vs-actual delta if one is appended later. Trivial fixes can be much shorter; major features or multi-file refactors can be longer. Every section in the skeleton below should earn its place — a one-line fix needs neither an Impact nor a Notes section.

### Title

A single descriptive line under ~70 characters. Use a conventional commit prefix (`feat:`, `fix:`, `refactor:`, `docs:`, `chore:`, etc.) when the surrounding repo's existing PR titles use one; otherwise no prefix.

## Procedure

### 1. Confirm scope

Before drafting, identify:

- **Target repo and base branch.** `gh repo view` and `git symbolic-ref --short refs/remotes/origin/HEAD` if unclear.
- **Linked issue.** Read the issue body and comments — especially any `research` plan they carry.
- **Whether the work went through `research`.** If yes: fold the plan's `Impact list` into `## Impact` when that section is kept; rewrite its `Checklist of changes` into `## Changes` entries per § Changes entries below; and report `## Verification` against its `Test plan` rather than folding that in. If no, derive `## Changes` and `## Impact` from the local diff and commits, and let `## Verification` report the checks this run made. Either way, do not transcribe the plan's process bookkeeping — see the reader-facing note below the skeleton.

### 2. Draft

Produce a title and body following the conventions above and the skeleton below.

#### Body skeleton

```
## Summary

<one-paragraph problem statement and resolution, semantic line breaks>
<Closes #N> on its own line; <Depends on #M> if applicable.

## Changes

<entries — see § Changes entries below>

## Impact

<callers / public APIs affected>
<omit when the change is genuinely local (single private function, etc.)>

## Verification

<invariants verified, tests added/modified, cross-API coverage>
<contract tests added during review, if any>
<verification results: cargo test / pytest / etc. — pass/fail summary>
<any check run against the tree, suite or not, backing a claim made in another section>

## Notes  (optional)

<known caveats, risks, follow-ups — including any behavior the plan
 deferred, framed as the limitation itself (what the PR does not do, and
 why), NOT as a "plan said X / actual Y" delta or a plan-comment link>
```

The PR body is **reader-facing**: it documents the merged artifact for a future bisect reader / maintainer, not the research process that produced it. Do **not** add a `Plan reference`, `Discovery contract status`, or `Open questions from the research plan` section even when the work went through `research-and-implement` — those transcribe plan-internal bookkeeping (opaque plan-comment IDs, inconclusive-item enumerations) that rots fast and means nothing to a reader without the plan in front of them. A deferred behavior a reader genuinely needs goes in `Notes`, framed as the code's own limitation rather than a plan delta. (A `## Plan-vs-actual delta` appended later by the caller is the one sanctioned exception — it is the audit surface for umbrella-tracked work and lives at the bottom of the body.)

The `## Plan-vs-actual delta` section is appended later by the caller; do not pre-create an empty delta section here.

Section headings are optional for trivial PRs — a 5-line body covering Summary + Verification often needs no headings.

#### Changes entries

An entry states what is now true, not what was done to make it true.
Before the body is posted, read every entry back as it then stands and restate any that describes the editing.

### 3. Discharge evidence claims

Discharge every evidence claim in the draft, as `gh-body-conventions` § Evidence claims defines one — across all sections, not only `## Verification`.
Run this in main context: the record the rule compares against is the drafting session's own, which a subagent does not have.

Editing the body here is expected; the laundering pass runs on the result.

### 4. Laundering pass — run `gh-body-audit`

Run `gh-body-audit` against the drafted body with artifact kind `pr`. It returns a ✅ / ⚠ status. Mandatory before every `gh-post pr create` / `gh-post pr edit`. Any ⚠ blocks step 5 on `gh-body-audit` step 4's terms.

See `gh-body-audit/SKILL.md` for the procedure.

### 5. Show for approval

Present the laundered draft to the user verbatim before filing. Do not file without confirmation.

If the user requests changes, revise, re-discharge its evidence claims, re-run the laundering pass, and re-show. Do not file partially — the next step runs only after explicit approval.

### 6. File

Two modes, distinguished by the caller.

#### 6a. Standalone mode (default)

Used when invoked directly by the user, not in gate mode. Write the laundered body to a temp file, then invoke the wrapper:

```bash
gh-post pr create \
  --repo <owner>/<repo> \
  --base <base-branch> \
  --title "<title>" \
  --body-file /tmp/<descriptive-name>.md
```

`gh-post` funnels every body through stream input and re-runs the hardwrap validator before forwarding to `gh`, so always create the PR through `gh-post` rather than `gh pr create --body ...` directly. Add `--draft` if the user wants a draft PR; extra flags (`--label`, `--reviewer <login>`, etc.) are forwarded to `gh` verbatim.

Do not auto-add `@copilot` here — Copilot review is `copilot-review`'s responsibility (gate mode below).

#### 6b. Gate mode

Used when invoked as a gate by a caller that creates the PR itself. Stop after approval; do NOT run `gh pr create`. Output the approved title and body for the caller to pass into its PR-creation step.

Output format:

```
APPROVED TITLE:
<title>

APPROVED BODY (HEREDOC-ready):
<body>
```

The caller then writes the approved body to a temp file and runs its PR-creation step, e.g.:

```bash
cat > /tmp/<descriptive-name>.md <<'EOF'
<approved body>
EOF

${CLAUDE_SKILL_DIR}/../copilot-review/scripts/pr-with-copilot-review.sh \
  --base <base-branch> \
  --title "<approved title>" \
  --body-file /tmp/<descriptive-name>.md
```

The script routes PR creation through `gh-post pr create`, which rejects inline `--body <string>` / `-b` to keep every body through the wrapper's validator stack — `--body-file` (preferred) or `--body-stdin` are the only accepted body inputs.

### 7. Report

After filing in standalone mode, show the user:

- The PR number and URL.
- Any follow-up actions (linking from a parent umbrella issue, triggering Copilot review separately via `copilot-review`, etc.).

In gate mode, just confirm the approval and hand off to the caller.
