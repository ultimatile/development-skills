---
name: review-telemetry
description: Append a normalized per-run record of reviewer-gate performance (findings, dispositions, duplicates, cost) to the local telemetry log after a review pipeline run finishes.
---

# Review Telemetry

Record how each reviewer gate performed in the pipeline run that just finished, as one append-only JSONL line. The accumulated log answers questions like "what does codex add over the code-review gate" and "does the PR gate ever surface non-duplicate findings" from operational data instead of anecdotes.

## Log location

```
~/.claude/review-telemetry/runs.jsonl
```

One line per pipeline run. Create the directory on first use (`mkdir -p ~/.claude/review-telemetry`).

## Collect the run's facts

Reconstruct from the current conversation's triage records, and from `git` / `gh` for repo facts:

- repo, PR number, pipeline skill name, diff stats (`gh pr view <N> --json additions,deletions,changedFiles`)
- per gate, in execution order: iterations run, config that varied (e.g. `/code-review` effort), wall-clock if it was reported, and every triaged finding with its disposition
- per finding: whether it duplicates a finding an earlier gate already surfaced (`duplicate_of_gate`) — a later-gate finding with `duplicate_of_gate: null` is by construction a penetration of every earlier gate

**Do not fabricate.** Any value the conversation does not evidence (a wall-clock nobody measured, an iteration count lost to compaction) is `null`, and the gap is named in the `gaps` array. A wrong number is worse than a hole — the log exists to be aggregated.

## Record shape

```json
{
  "schema": 1,
  "recorded_at": "<ISO8601 UTC>",
  "repo": "owner/name",
  "pr": 123,
  "pipeline": "review-pipeline-coderabbit",
  "diff": {"files": 6, "additions": 964, "deletions": 0},
  "gates": [
    {
      "gate": "code-review",
      "config": {"effort": "medium"},
      "iterations": 1,
      "wall_clock_s": null,
      "findings": [
        {
          "topic": "stale-docstring",
          "summary": "one-line description of the finding",
          "disposition": "actionable",
          "duplicate_of_gate": null,
          "fixed": true
        }
      ]
    }
  ],
  "gaps": ["codex wall-clock not recorded"]
}
```

Normalization rules:

- `gates[].gate` slugs: `done-check`, `code-review`, `codex-review`, `copilot-pr`, `coderabbit-pr`, `coderabbit-local`. Array order = execution order.
- `findings[].disposition` uses the `finding-triage` SSOT slugs verbatim (`actionable`, `false-positive`, `uncertain-validity`, `opens-a-question`, `invariant-premise-check`, `defer`).
- `findings[].topic` is a short kebab-case slug for cross-run grouping; `summary` is one sentence.
- A gate that ran and found nothing gets `"findings": []` — that zero is data. A gate that was skipped is omitted from the array and named in `gaps`.

## Append

1. Build the record and validate it before touching the log:

   ```bash
   jq -e . /tmp/review-telemetry-record.json > /dev/null
   ```

2. Check for an existing record of the same run:

   ```bash
   rg -c '"repo": "owner/name", "pr": 123' ~/.claude/review-telemetry/runs.jsonl
   ```

   On a hit, surface it to the user and ask before appending a second record — duplicate runs skew per-gate aggregates.

3. Append as a single line:

   ```bash
   jq -c . /tmp/review-telemetry-record.json >> ~/.claude/review-telemetry/runs.jsonl
   ```

4. Echo the appended line back to the user for a final visual check.

## Reading the log

Aggregation one-liners for later analysis sessions:

```bash
# Non-duplicate actionable findings per gate (the penetration signal)
jq -r '.gates[] | .gate as $g | .findings[] | select(.disposition == "actionable" and .duplicate_of_gate == null) | $g' \
  ~/.claude/review-telemetry/runs.jsonl | sort | uniq -c

# False-positive count per gate (the triage-cost signal)
jq -r '.gates[] | .gate as $g | .findings[] | select(.disposition == "false-positive") | $g' \
  ~/.claude/review-telemetry/runs.jsonl | sort | uniq -c

# Runs where a PR-side gate surfaced anything novel
jq -c 'select(.gates[] | select(.gate | test("-pr$")) | .findings[] | .duplicate_of_gate == null)' \
  ~/.claude/review-telemetry/runs.jsonl
```

Interpret only across many runs — single-run records are anecdotes by definition.
