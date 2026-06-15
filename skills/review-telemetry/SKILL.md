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
- per gate, in execution order: iterations run, config that varied (e.g. `/code-review` effort), and every triaged finding with its disposition. `iterations` (re-run count) and per-gate false-positive count are the cost proxies; both are reconstructable post-hoc. Do not record wall-clock — gate elapsed time is reconstructed after the run, so a duration nobody clocked at execution time is unrecoverable, and it conflates compute with external-service poll-wait (CodeRabbit / Copilot arrive async) and human approval-wait, which say nothing about the gate's own cost.
- per finding, two distinct relations to earlier gates:
  - `duplicate_of_gate` — strictly an **instance re-report**: the same defect (same location, same fix) an earlier gate already surfaced. `null` means the defect itself is new — the instance-level penetration signal.
  - `topic_opened_by` — the gate that **first surfaced this topic** in the run (the gate's own slug when it opened the topic). A new instance of an earlier gate's topic is `duplicate_of_gate: null` + `topic_opened_by: <earlier gate>` — value added, but no topic novelty.
  - `injected_at_gate` — the in-run gate whose **fix loop introduced** this defect (its slug), or `null` for the default: the defect was present in the original diff, i.e. injected upstream of gate 0. Most findings are `null`. A non-null value marks a **fix-induced regression** — sharpest case: a `review-hotfix` that re-diverges the actual from the plan (a `plan-actual-drift` topic). The point of recording it: gates at or before the injection point could not have seen the defect and must be **exonerated** in penetration/escape stats — only gates strictly between injection and surfacer missed it.

**Do not fabricate.** Any value the conversation does not evidence (an iteration count lost to compaction, a config value you cannot reconstruct) is `null`, and the gap is named in the `gaps` array. A wrong number is worse than a hole — the log exists to be aggregated.

## Record shape

```json
{
  "schema": 3,
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
      "findings": [
        {
          "topic": "stale-docstring",
          "summary": "one-line description of the finding",
          "disposition": "actionable",
          "duplicate_of_gate": null,
          "topic_opened_by": "code-review",
          "injected_at_gate": null,
          "fixed": true
        }
      ]
    }
  ],
  "gaps": ["copilot-pr gate skipped per user request"]
}
```

Schema 1 records lack `topic_opened_by`; gate the schema-2 queries with `select(.schema >= 2)`. Schema ≤2 records lack `injected_at_gate` (read absent as `null` = pre-pipeline injection); gate the escape-distance query with `select(.schema >= 3)`.

Normalization rules:

- `gates[].gate` slugs: `done-check`, `code-review`, `codex-review`, `copilot-pr`, `coderabbit-pr`, `coderabbit-local`. Array order = execution order.
- `findings[].disposition` uses the `finding-triage` SSOT slugs verbatim (`actionable`, `false-positive`, `uncertain-validity`, `opens-a-question`, `invariant-premise-check`, `defer`).
- `findings[].topic` is a short kebab-case slug at **class level**, reused across gates and runs for grouping; per-variant detail goes in the one-sentence `summary`. Splitting one class into per-variant slugs breaks every topic aggregation.
- `duplicate_of_gate` is instance-strict (same defect re-reported); `topic_opened_by` carries class recurrence. Never encode class recurrence in `duplicate_of_gate` — that conflation is exactly what the two fields exist to prevent.
- `injected_at_gate` defaults to `null` (defect in the original diff). Set it only when an **earlier gate's fix loop in this same run introduced** the defect — the gate's slug. `plan-actual-drift` is the reserved class-level `topic` for a finding where the implementation diverged from the research plan; when a `review-hotfix` re-introduces such a divergence, its `injected_at_gate` is the hotfixing gate. Surfacer ordinal comes from `topic_opened_by`'s position in `gates[]`; injection ordinal from `injected_at_gate`'s position (`null` ⇒ −1). escape-distance = surfacer − injection − 1 = the count of gates that had the defect in front of them and still missed it; gates at index ≤ injection are exonerated (the defect did not exist yet) and the surfacer is the catcher, so a defect caught at the first opportunity has distance 0. This is why no gate after a hotfix re-checks plan-conformance unless one is placed there — a deep `review-hotfix`→`plan-actual-drift` cluster in the aggregate is the signal to add that recheck gate.
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

# Escape-distance: per surfaced defect, how many gates had it in front of them and missed
# it (surfacer − injection − 1). injected_at_gate=null ⇒ upstream of gate 0; a defect caught
# at the first opportunity is distance 0. Gates at/before injection are exonerated. Worst first.
jq -r 'select(.schema >= 3)
  | [.gates[].gate] as $order
  | .gates[] | .gate as $g | .findings[]
  | select(.topic_opened_by == $g and .duplicate_of_gate == null)
  | .injected_at_gate as $ig
  | ($order | index($g)) as $surf
  | (if $ig == null then -1 else ($order | index($ig)) end) as $inj
  | [($surf - $inj - 1), .topic, ($ig // "pre-pipeline"), $g] | @tsv' \
  ~/.claude/review-telemetry/runs.jsonl | sort -rn

# review-hotfix-sourced drift: the structural blind spot (no post-hotfix plan recheck)
jq -r 'select(.schema >= 3) | .gates[] | .findings[]
  | select(.topic == "plan-actual-drift" and .injected_at_gate != null)
  | [.injected_at_gate, .topic_opened_by] | @tsv' \
  ~/.claude/review-telemetry/runs.jsonl | sort | uniq -c
```

Interpret only across many runs — single-run records are anecdotes by definition.
