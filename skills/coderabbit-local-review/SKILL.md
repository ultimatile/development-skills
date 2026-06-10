---
name: coderabbit-local-review
description: Pre-PR local review of uncommitted changes or the branch diff using the CodeRabbit CLI, with findings triaged before presentation. Second local reviewer alongside codex-review.
allowed-tools: Bash(coderabbit:*)
---

# CodeRabbit Local Review

Run the CodeRabbit CLI against local changes — no PR required — and triage the findings.

## Prerequisites

```bash
coderabbit auth status
```

If the command is missing, have the user install the CLI (https://www.coderabbit.ai/cli) — installation and login are interactive and user-owned. If unauthenticated, have the user run `coderabbit auth login`.

The CLI sends code diffs to the CodeRabbit API. Do not run it on a tree containing secrets or credentials, and surface to the user before reviewing anything they have not already decided to publish.

## Run the review

Review the branch diff against the base (the pre-PR default):

```bash
coderabbit review --plain --base main
```

Other scopes:

| Command | Scope |
| -- | -- |
| `coderabbit review --plain -t uncommitted` | Staged + unstaged changes only |
| `coderabbit review --plain -t committed` | Committed changes only |
| `coderabbit review --plain` | All changes (default `-t all`) |

`--plain` emits human-readable findings with fix suggestions — the right input for triage. `--agent` emits compact JSONL instead (`review_context` → `status` → `complete`, with a `findings` count on the `complete` event); use it only when a script consumes the output. A clean pass in `--agent` mode ends with `"status":"review_skipped"` / `"findings":0` when there are no changes, or `"findings":0` on a reviewed-but-clean diff — both are genuine zero-finding results, not errors.

Reviews run on CodeRabbit's servers: set the Bash timeout to 600000ms, and expect minutes on large diffs. The free tier is rate-limited — on a rate-limit error, report it to the user and stop; do not retry in a loop.

## Triage the output

The reviewer sees the diff and file contents but not test results, runtime behavior, prior conversation, or design rationale — expect false positives alongside real findings.

1. Identify each distinct finding in the output.
2. Cross-check against project context you already have — tests you've run, code you've read, decisions made with the user.
3. Classify each finding under the `finding-triage` SSOT dispositions — typically `actionable`, `false-positive` (with reasoning), or `uncertain-validity`; a real finding whose fix is non-local is `opens-a-question` → re-enter `research`.
4. Present the triage to the user — never the raw output. Lead with actionable items; note dismissed items with reasoning.

## Review-fix loop

1. Run the review.
2. Triage and present.
3. If actionable findings exist: fix, commit, and re-run the **same full review** — do not feed previous findings back into the next run, and do not narrow the scope to the fix. The fresh run must answer both "is the issue fixed" and "did the fix break something new".
4. Re-triage from scratch — a dismissal from iteration N may not survive iteration N+1's code.
5. Repeat until no actionable findings remain.

## Placement

This is a pre-PR gate at the same position as `codex-review`; the two are complementary local reviewers and can run in either order. The PR-side `coderabbit-review` skill talks to the same backend — when this skill already reviewed the final diff, a follow-up CodeRabbit PR review of the identical diff adds little and is expected to come back clean.
