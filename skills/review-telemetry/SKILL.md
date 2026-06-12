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
- per finding, two distinct relations to earlier gates:
  - `duplicate_of_gate` — strictly an **instance re-report**: the same defect (same location, same fix) an earlier gate already surfaced. `null` means the defect itself is new — the instance-level penetration signal.
  - `topic_opened_by` — the gate that **first surfaced this topic** in the run (the gate's own slug when it opened the topic). A new instance of an earlier gate's topic is `duplicate_of_gate: null` + `topic_opened_by: <earlier gate>` — value added, but no topic novelty.

**Do not fabricate.** Any value the conversation does not evidence (a wall-clock nobody measured, an iteration count lost to compaction) is `null`, and the gap is named in the `gaps` array. A wrong number is worse than a hole — the log exists to be aggregated.

## Record shape

```json
{
  "schema": 2,
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
          "topic_opened_by": "code-review",
          "fixed": true
        }
      ]
    }
  ],
  "gaps": ["codex wall-clock not recorded"]
}
```

Schema 1 records lack `topic_opened_by`; gate the schema-2 queries with `select(.schema >= 2)`.

Normalization rules:

- `gates[].gate` slugs: `done-check`, `code-review`, `codex-review`, `copilot-pr`, `coderabbit-pr`, `coderabbit-local`. Array order = execution order.
- `findings[].disposition` uses the `finding-triage` SSOT slugs verbatim (`actionable`, `false-positive`, `uncertain-validity`, `opens-a-question`, `invariant-premise-check`, `defer`).
- `findings[].topic` is a short kebab-case slug at **class level**, reused across gates and runs for grouping; per-variant detail goes in the one-sentence `summary`. Splitting one class into per-variant slugs breaks every topic aggregation.
- `duplicate_of_gate` is instance-strict (same defect re-reported); `topic_opened_by` carries class recurrence. Never encode class recurrence in `duplicate_of_gate` — that conflation is exactly what the two fields exist to prevent.
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
# Instance-level penetration: new defects each gate added
jq -r '.gates[] | .gate as $g | .findings[] | select(.disposition == "actionable" and .duplicate_of_gate == null) | $g' \
  ~/.claude/review-telemetry/runs.jsonl | sort | uniq -c

# Topic novelty: new defect classes each gate opened
jq -r 'select(.schema >= 2) | .gates[] | .gate as $g | .findings[] | select(.topic_opened_by == $g) | [$g, .topic] | @tsv' \
  ~/.claude/review-telemetry/runs.jsonl | sort -u | cut -f1 | uniq -c

# Unswept-class pressure: instances of a class an earlier gate opened but did not exhaust
# (high counts indicate the opening gate or the fix loop under-generalizes)
jq -r 'select(.schema >= 2) | .gates[] | .gate as $g | .findings[] | select(.topic_opened_by != $g and .duplicate_of_gate == null) | "\($g) <- \(.topic_opened_by) [\(.topic)]"' \
  ~/.claude/review-telemetry/runs.jsonl | sort | uniq -c

# False-positive count per gate (the triage-cost signal)
jq -r '.gates[] | .gate as $g | .findings[] | select(.disposition == "false-positive") | $g' \
  ~/.claude/review-telemetry/runs.jsonl | sort | uniq -c

# Runs where a PR-side gate surfaced anything novel
jq -c 'select(.gates[] | select(.gate | test("-pr$")) | .findings[] | .duplicate_of_gate == null)' \
  ~/.claude/review-telemetry/runs.jsonl
```

Interpret only across many runs — single-run records are anecdotes by definition.
