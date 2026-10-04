---
name: code-review-gate
description: Run the built-in /code-review against the current diff through a fallback lane chain with lane-failure, retry, and exhaustion handling.
---

# Code-Review Gate

Runs a `/code-review` pass through a lane chain.

The caller supplies three inputs:

- **effort** — the `/code-review` level every lane reviews at, `medium` or `high`. `medium` reports only the findings the review is most confident in; `high` covers more and may report findings it is less sure of. Pass `high` if at least one behavior the change alters meets at least one of these three conditions, judged from the caller's prompt, its memory, and its knowledge of the project; pass `medium` otherwise. Held fixed across a gate loop.
  1. In the caller's current execution environment, it cannot be exercised with the inputs, scale, and dependencies of its intended use.
  2. It changes persistent external state that reverting the change does not restore.
  3. It computes a numerical or other non-prose data result whose value no test verifies.
- **root** — the ref the change under review is measured from, supplied on `diff-root`'s consumer contract. Apply that contract here, halt included.
- **review tree** — the absolute path of the working tree that holds the change under review.

A **gate loop** is a run of this gate together with each re-run that follows it. A run made to review a fix for an earlier run's findings is a re-run, in that earlier run's loop; every other run starts a new loop. Each run is one iteration of its loop.

The **gate scope** is what every lane reviews, read in the review tree: the branch's committed diff against the root, by `diff-root`'s per-command conversion (`git diff <root-rev>...HEAD`, after that conversion's refresh), plus uncommitted changes (`git diff HEAD`), plus untracked files (`git ls-files --others --exclude-standard`).

When all three parts are empty, halt before entering any lane and surface to the user that the gate scope is empty. This is neither a lane failure nor exhaustion.

The **review command** is `/code-review <effort> <root-rev>...HEAD`, with both substituted. Every lane that runs it runs it in the review tree.

## Output validity

A genuine `/code-review` run engages with the diff and returns one of two things: a list of findings, or an explicit clean verdict (a bare `[]`, "no issues", or equivalent). Its exact shape varies by model — findings may arrive as a fenced JSON array or as prose with `file:line` refs — so validity is judged by content, not format. It does **not** enumerate the files it inspected, so do not require that.

**Lane failure** = timeout, nonzero exit, empty output, or output that does not engage the diff: a limit / session / billing advisory (e.g. "You've reached your … limit", "You've hit your session limit"), or any text that neither lists findings nor gives a clean verdict. These carry exit 0 and non-empty text, so they are caught by content, not by exit code. Never read a non-engaging output as a clean pass.

## Lane chain

Build the chain at each gate run. When the gate scope's untracked part is non-empty, the chain is the subagent lane alone. Otherwise it is the direct, headless, user, and subagent lanes, in that order, except that the direct lane is in it only when the session's primary working directory — as the harness states it in the session's environment, not the shell's current directory — is the review tree; when that cannot be established, the direct lane is not in it. A lane not in the chain is neither entered nor abandoned, and a lane abandoned earlier in the gate loop stays abandoned whatever chain a later run builds. Use the first lane in the chain that produces a valid review. On lane failure, retry the same lane once — a bare retry only helps a cause that clears on its own (network blip, cold start). When the failure names a reset condition an immediate retry cannot satisfy (a session or model-usage limit with a reset time, an announced outage), skip the retry. After the failed retry or the skip, abandon the lane for the rest of the gate loop and advance to the next lane.

- **Direct.** Invoke the review command through the Skill tool. When the Skill tool runs it in the background, the lane's output is that run's final result, never the acknowledgment the launch returns. When the Skill tool is absent or refuses the call, abandon the lane without retry.
- **Headless.** Via Bash with a 10-minute timeout: `claude -p --model opus "<review command>" --output-format text`, capturing stdout as the review output. `--model opus` is pinned so the review — and the finder subagents, which inherit the session model — does not run on whatever small CLI-default model is set. Skip this lane — its abandonment, no retry — when the user has announced that the billing watch in ultimatile/development-skills#117 has fired (`claude -p` no longer draws from the subscription pool).
- **User.** Pause, give the user the review tree's path, and ask them to run the review command there and report the output. An explicit decline abandons the lane without retry; the reported output is judged by Output validity like any lane's.
- **Subagent.** Spawn a fresh-context subagent. Give it the gate scope, with the contents of each untracked file read in. Instruct it to review adversarially for bugs, contract drift, and quality issues, and to return findings as `file:line — description — severity` or an explicit clean verdict. Tell it which findings to report by giving it what the effort input says the caller's level reports. At `high`, also tell it to go through the gate scope hunk by hunk.

## Exhaustion

If every lane in the chain is abandoned without a valid review of the current diff, **halt and surface the state to the user** — never proceed toward a commit with an unreviewed diff. Only the user may waive. A waiver does not delete telemetry: iterations that produced a valid review are still recorded with their data; the waived, unreviewed final diff is named in the gate's `gaps`. Omit the gate entirely only when no iteration ever produced a valid review.

## Telemetry notes

At gate time, note the root and the lane used for each iteration (e.g. `root: main`, `lanes: [direct, direct, headless]`) so the post-run `review-telemetry` record can carry both in the gate's `config`. Record the waiver (if any) per the Exhaustion rule above: name it in `gaps`, and apply `review-telemetry`'s skipped-gate omission only when no iteration ever produced a valid review.
