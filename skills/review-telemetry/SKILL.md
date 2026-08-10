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

Reconstruct from the current conversation's triage records, from `git` / `gh` for repo facts, and from the recording session itself for the model and effort it runs under:

- repo, PR number, pipeline skill name, diff stats (`gh pr view <N> --json additions,deletions,changedFiles`)

- `skills_version` — the development-skills state the gates ran under, attested by the recording session: `git -C ~/.claude/skills/review-telemetry describe --tags --always --dirty`, recorded verbatim. Run-level. Ask the user when you cannot vouch that what came back names the state the gates ran under.

- `fixer_model` and `fixer_effort` — the model and reasoning effort the run's triage and fix loops ran under, run-level. The recording session's transcript records them per message; read the pair of columns from it:

  ```bash
  jq -r 'select(.message.model != null and .message.model != "<synthetic>")
         | [.message.model, .effort] | @tsv' \
    ~/.claude/projects/$(pwd | tr './' '--')/$CLAUDE_CODE_SESSION_ID.jsonl | sort -u
  ```

  Each field is settled from its own column, independently of the other. A column holding one value throughout gives the field that value; a column holding two or more, or any empty cell, gives `null` with `gaps` naming what the column held. An effort column is empty for a session the harness recorded without one, which is why the columns are read apart: the same run can settle its model and not its effort. The transcript writes the model id without the harness's context-variant marker, so the bare id is what lands here. Ask the user when the transcript is not readable.

  The read covers the whole session, which the run's loops are part of, so a single-valued column settles the run without the session's extent having to be established. A column holding several values leaves the run's own value unsettled — the change may lie outside the loops — and `null` records that rather than a guess.

- per gate: iterations run, config that varied (e.g. `/code-review` effort), the reviewer model per the normalization rules below, and every triaged finding with its disposition. `iterations` and per-gate false-positive count are the cost proxies. Do not record wall-clock — gate elapsed time is reconstructed after the run, so a duration nobody clocked at execution time is unrecoverable, and it conflates compute with external-service poll-wait (Copilot arrives async) and human approval-wait, which say nothing about the gate's own cost.

- per finding, three distinct gate relations:

  - `duplicate_of_gate` — strictly an **instance re-report**: the same defect (same location, same fix) a gate already surfaced earlier in the run. `null` means the defect itself is new — the instance-level penetration signal.
  - `topic_opened_by` — the gate that **first surfaced this topic** in the run (the gate's own slug when it opened the topic). A new instance of an earlier gate's topic is `duplicate_of_gate: null` + `topic_opened_by: <earlier gate>` — value added, but no topic novelty.
  - `injected_at_gate` — the in-run gate whose **fix loop introduced** this defect (its slug), or `null` for the default: the defect was present in the original diff. Most findings are `null`. A non-null value marks a **fix-induced regression**.

**Do not fabricate.** A value neither the session nor the user can vouch for, and any value the conversation does not evidence (an iteration count lost to compaction, a config value you cannot reconstruct) is `null`, and the gap is named in the `gaps` array — except where the field's own normalization rule names a value for that case, which then governs both. A wrong number is worse than a hole — the log exists to be aggregated.

## Record shape

```json
{
  "schema": 4,
  "recorded_at": "<ISO8601 UTC>",
  "repo": "owner/name",
  "pr": 123,
  "pipeline": "review-pipeline",
  "skills_version": "2026.8.4-4-g7c1d9ab-dirty",
  "fixer_model": "claude-opus-5",
  "fixer_effort": "high",
  "diff": {"files": 6, "additions": 964, "deletions": 0},
  "gates": [
    {
      "gate": "done-check",
      "reviewer_model": "claude-opus-5",
      "iterations": 1,
      "findings": []
    },
    {
      "gate": "code-review",
      "config": {"effort": "medium"},
      "reviewer_model": null,
      "iterations": 1,
      "findings": [
        {
          "topic": "stale-docstring",
          "summary": "one-line description of the finding",
          "disposition": "actionable",
          "duplicate_of_gate": null,
          "topic_opened_by": "code-review",
          "injected_at_gate": null
        }
      ]
    },
    {
      "gate": "codex-review",
      "reviewer_model": "gpt-5-codex",
      "iterations": 1,
      "findings": []
    },
    {
      "gate": "copilot-pr",
      "reviewer_model": "unobservable",
      "iterations": 1,
      "findings": []
    }
  ],
  "gaps": ["code-review ran in the user's own session; reviewing model not stated"]
}
```

Schema 1 records lack `topic_opened_by`; gate every query reading that field with `select(.schema >= 2)`. Schema ≤2 records lack `injected_at_gate`; gate every query reading that field with `select(.schema >= 3)`. Schema ≤3 records lack `skills_version`, `fixer_model`, `fixer_effort`, and `gates[].reviewer_model`; gate every query reading any of them with `select(.schema >= 4)`.

Normalization rules:

- `gates[].gate` slugs: `done-check`, `code-review`, `codex-review`, `copilot-pr`. One entry per gate, however many times it ran.
- Records predating the CodeRabbit lane's retirement carry values from it: the gate slug `coderabbit-pr`, and the `pipeline` values `review-pipeline-coderabbit` and `coderabbit-review`. They are history — read them, never write them. `coderabbit-pr`'s counts end at the retirement; a reader who takes that ending for a gate that went quiet misreads it.
- `findings[].disposition` uses the `finding-triage` SSOT slugs verbatim; that file's catalogue is the value set.
- `findings[].topic` is a short kebab-case slug at **class level**, reused across gates and runs for grouping; per-variant detail goes in the one-sentence `summary`. Splitting one class into per-variant slugs breaks every topic aggregation.
- `duplicate_of_gate` and `topic_opened_by` are written per their definitions in **Collect the run's facts**. Never encode class recurrence in `duplicate_of_gate` — that conflation is exactly what the two fields exist to prevent.
- `injected_at_gate` is written per its definition in **Collect the run's facts**. `plan-actual-drift` is the reserved class-level `topic` for a finding where the implementation diverged from the research plan. **Do not derive an escape-distance — how many gates had the defect in front of them and missed it — from this record.**
- A gate that ran and found nothing gets `"findings": []` — that zero is data. A gate that was skipped is omitted from the array and named in `gaps`.
- `fixer_model` and `fixer_effort` are written per their definitions in **Collect the run's facts**. Neither is `config.effort`, a gate's own review-depth argument that stays in `config` — same word, different quantity.
- Each iteration's reviewing model comes from the first of these that yields one: the reviewer's own output names it; the invocation pinned one, recorded as written — an alias stays an alias and is its own token, never folded into `fixer_model`; the session ran it, including through a subagent inheriting its model, which makes it `fixer_model`, and none when that is itself `null`; or a person who ran it states it. An iteration matching none has no known model.
- `gates[].reviewer_model` is always written, and its value space is bounded: one model token, `"unobservable"`, or `null` — never a set encoded into a string. It takes the first branch that applies. **`"unobservable"`** — some iteration ran under a reviewer that exposes its model to nobody, `copilot-pr` being the case that reaches it. **`null`** — otherwise the gate is not attributable to one model, because some iteration's model is not known or the iterations did not all run under the same one. **A model token** — otherwise every iteration ran under that one model. Whatever the branch, `gaps` names every iteration whose model was knowable and went uncaptured.

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

The log is append-only (`chflags uappnd`), so `>>` works and any rewrite fails with
`Operation not permitted`. If the path is a symlink, the flag is on the target. To change the file,
unlock it, change it, and re-lock:

```bash
chflags nouappnd <log>
# change
chflags uappnd <log>
```

## Reading the log

Aggregation one-liners for later analysis sessions. One derivation is prohibited; see the `injected_at_gate` normalization rule.

```bash
# Instance-level penetration: new actionable defects each gate added
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
# `-pr$` spans both PR-side gates, the retired `coderabbit-pr` included; swap it for
# `.gate == "copilot-pr"` when the question is about that gate alone
jq -c 'select(any(.gates[] | select(.gate | test("-pr$")) | .findings[]; .duplicate_of_gate == null))' \
  ~/.claude/review-telemetry/runs.jsonl

# Actionable fix-induced regressions per injecting gate (the regeneration signal)
jq -r 'select(.schema >= 3) | .gates[].findings[]
  | select(.disposition == "actionable" and .injected_at_gate != null and .duplicate_of_gate == null)
  | .injected_at_gate' \
  ~/.claude/review-telemetry/runs.jsonl | sort | uniq -c | sort -rn

# Actionable fix-loop-sourced plan drift, by injecting and surfacing gate; a recurring pair is the signal
# to add a plan-conformance recheck after the fix loops
jq -r 'select(.schema >= 3) | .gates[] | .gate as $g | .findings[]
  | select(.disposition == "actionable" and .topic == "plan-actual-drift"
           and .injected_at_gate != null and .duplicate_of_gate == null)
  | [.injected_at_gate, $g] | @tsv' \
  ~/.claude/review-telemetry/runs.jsonl | sort | uniq -c
```

Interpret only across many runs — single-run records are anecdotes by definition.
