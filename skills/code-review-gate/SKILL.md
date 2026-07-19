---
name: code-review-gate
description: Run the built-in /code-review against the current diff through a fallback lane chain (headless claude -p, user-run, fresh-context subagent) with lane-failure, retry, and exhaustion handling, for when the Skill tool cannot invoke it directly.
---

# Code-Review Gate

Runs a `/code-review` pass through a lane chain — the built-in skill is `disable-model-invocation`, so the Skill tool cannot invoke it directly. The caller supplies the effort: `medium` by default, `high` for a large or risky diff, held fixed across a PR's iterations. `/code-review` reviews the working tree (committed-on-branch + staged + unstaged + untracked), so no lane needs to be handed an explicit diff range.

## Output validity

A genuine `/code-review` run engages with the diff and returns one of two things: a list of findings, or an explicit clean verdict (a bare `[]`, "no issues", or equivalent). Its exact shape varies by model — findings may arrive as a fenced JSON array or as prose with `file:line` refs — so validity is judged by content, not format. It does **not** enumerate the files it inspected, so do not require that.

**Lane failure** = timeout, nonzero exit, empty output, or output that does not engage the diff: a limit / session / billing advisory (e.g. "You've reached your … limit", "You've hit your session limit"), or any text that neither lists findings nor gives a clean verdict. These carry exit 0 and non-empty text, so they are caught by content, not by exit code. Never read a non-engaging output as a clean pass.

## Lane chain

Use the first lane that produces a valid review. On lane failure, retry the same lane once — a bare retry only helps a cause that clears on its own (network blip, cold start). When the failure names a reset condition an immediate retry cannot satisfy (a session or model-usage limit with a reset time, an announced outage), skip the retry. After the failed retry or the skip, abandon the lane for the rest of this PR's iterations and advance to the next lane.

- **Lane 1 — headless.** From the repo root, via Bash with a 10-minute timeout: `claude -p --model opus "/code-review <effort>" --output-format text`, capturing stdout as the review output. `--model opus` is pinned so the review — and the finder subagents, which inherit the session model — does not run on whatever small CLI-default model is set. Skip this lane — its abandonment, no retry — when the user has announced that the billing watch in ultimatile/development-skills#117 has fired (`claude -p` no longer draws from the subscription pool).
- **Lane 2 — user gate.** Pause and ask the user to run `/code-review <effort>` and report the output. An explicit decline abandons the lane without retry; the reported output is judged by Output validity like any lane's.
- **Lane 3 — subagent.** Spawn a fresh-context subagent. Give it the full gate scope, matching what `/code-review` sees: the branch's committed diff against the default branch (`git diff "$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's@^origin/@@')"...HEAD` — do not use `@{upstream}`, which names the branch's own pushed copy and yields an empty diff once pushed), plus uncommitted changes (`git diff HEAD`), plus the contents of untracked files (list them with `git ls-files --others --exclude-standard`, then read each). Instruct it to review adversarially for bugs, contract drift, and quality issues at the caller's effort (`medium` = standard pass; `high` = exhaustive per-hunk pass), and to return findings as `file:line — description — severity` or an explicit clean verdict.

## Exhaustion

If every lane is abandoned without a valid review of the current diff, **halt and surface the state to the user** — never proceed toward a commit with an unreviewed diff. Only the user may waive. A waiver does not delete telemetry: iterations that produced a valid review are still recorded with their data; the waived, unreviewed final diff is named in the gate's `gaps`. Omit the gate entirely only when no iteration ever produced a valid review.

## Telemetry notes

At gate time, note the lane used for each iteration (e.g. `lanes: [1, 1, 2]`) so the post-run `review-telemetry` record can carry it in the gate's `config`. Record the waiver (if any) per the Exhaustion rule above: name it in `gaps`, and apply `review-telemetry`'s skipped-gate omission only when no iteration ever produced a valid review.
