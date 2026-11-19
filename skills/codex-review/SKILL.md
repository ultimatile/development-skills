---
name: codex-review
description: Pre-PR code review on the current branch using the OpenAI Codex CLI, with an iterative fix loop.
---

# Codex Review

Orchestrate `codex exec review` to review branch changes and iterate on fixes.

## The root

The caller supplies the **root** — the ref the change under review is measured from — on `diff-root`'s consumer contract. Apply that contract here, halt included. Every `--base` command below resolves the merge base in its own block, as that skill's per-command conversion requires.

## Core commands

### Review branch diff against base

```bash
mb=$(git merge-base <root-rev> HEAD)
test -n "$mb" || { echo "no merge base for <root>"; exit 1; }
"${CLAUDE_SKILL_DIR}/../run-codex/scripts/run-codex.sh" review --base "$mb"
```

This runs `git diff <base-SHA>` internally and reviews the entire diff. The review covers all committed changes on the current branch relative to the base — both the original work and any subsequent fix commits.

When a `run-codex.sh` command's status line reads `completed`, triage the file its `result:` line names. Otherwise, report what the script printed to the user and wait for their direction.

### Other review modes

| Command | Scope |
| -- | -- |
| `run-codex.sh review --uncommitted` | Staged + unstaged + untracked changes |
| `run-codex.sh review --commit <SHA>` | A single commit's diff |
| `run-codex.sh prompt "<inline prompt>"` | Free-form prompt with inline context (see "Switching to `exec` with inline context" below) |

`run-codex.sh` is `"${CLAUDE_SKILL_DIR}/../run-codex/scripts/run-codex.sh"`.

## Switching to `exec` with inline context

`codex exec review` starts without this conversation's history, and with `--base` it takes no instructions beyond its built-in review prompt, so nothing points it at design intent encoded outside the diff — a GitHub Issue, an ADR. For self-contained changes this is fine; for **phased rollouts** where the judgement criteria live outside the diff, `review` mode systematically misjudges intentional design decisions as regressions. Switch to free-form `run-codex.sh prompt "<inline prompt>"` to attach the context.

**Trigger — before every codex review, check:**

- Is this commit part of a numbered phase in a tracked Issue?
- Does the relevant ADR contain phrases like "unmeasured → sentinel X", "tracked separately in a follow-up", "intentional default until <later phase>", "out of this phase's scope"?
- Are there thresholds, defaults, or scoped-off paths that look like bugs from the diff but are ADR / Issue-intentional?

If any of the above is yes, skip `run-codex.sh review` and use `run-codex.sh prompt "<inline prompt>"` instead.

**Why the workaround is needed:** `--base` and the positional `[PROMPT]` are mutually exclusive on `codex exec review`, so phase context cannot be attached to a `review` invocation. The free-form `codex exec "..."` accepts an arbitrary prompt that can direct codex to read the surrounding context first.

**Inline prompt template** — when the change has a tracking Issue, save it before each prompt is written, to a fresh file from `mktemp`:

```bash
mktemp   # prints <issue-file>
"${CLAUDE_SKILL_DIR}/../read-issue/scripts/read-issue.sh" <n> > <issue-file>
```

When `read-issue.sh` exits nonzero, stop and report its message instead of running the review. Delete `<issue-file>` once the read has failed or codex has exited.

The prompt names, each by its absolute path so codex doesn't have to search, the relevant ADRs and, when the change has a tracking Issue, `<issue-file>` as that Issue. It should tell codex to:

1. Run `git log <root-rev>..HEAD --oneline` and `git show <sha>` to read the commits.
2. Read each file the prompt names in full, and re-read by line range any part a read reports as truncated.
3. Enumerate explicitly which states are intentional (sentinel values, scoped-off paths, deferred behaviors) and must NOT be flagged as regressions.
4. List what the review should focus on (forwarding correctness, default / expert contract consistency, docstring drift, missed call sites, etc. — project-specific).
5. List what to ignore — the enumerated intentional states from step 3.

**For non-phased self-contained changes**, keep using `run-codex.sh review --base ...` in the form Core commands gives. The inline-context workaround is only needed when judgement criteria live outside the diff.

## Triaging review output

The reviewer reads the repository and runs commands, but it starts without this conversation's history: the design rationale, scope decisions, and test results established here are not in front of it. This means a significant fraction of its findings will be false positives: technically plausible concerns that don't apply given information the reviewer can't see.

Typical false positive patterns:

- **Assumed standard behavior**: "this regex won't match standard X format" when the actual data uses a project-specific format (verified by tests)
- **Missing context on intentional decisions**: flagging a design choice as a bug when it was deliberate and tested
- **Hypothetical edge cases**: warning about inputs that can't occur given the system's constraints

When presenting review output, triage each finding:

1. **Read the review output** and identify each distinct finding (usually formatted as `[P1/P2] summary — file:line`)
2. **Cross-check against project context** you already have — test results, prior conversation, code you've read.
3. **Classify each finding** under the `finding-triage` SSOT dispositions, applying each per its definition there. The common codex-review cases are `actionable`, `false-positive`, and `uncertain-validity`.
4. **Present the triage** to the user, not the raw output. Lead with actionable items, note dismissed items with reasoning.

## Review-fix loop

Each iteration runs a full, unbiased review of the entire diff against base. Do NOT inject previous review comments into the prompt — this narrows the reviewer's focus and risks missing new regressions introduced by the fix. The reviewer should always see the code with fresh eyes.

### Procedure

1. **Run review**

   ```bash
   mb=$(git merge-base <root-rev> HEAD)
   test -n "$mb" || { echo "no merge base for <root>"; exit 1; }
   "${CLAUDE_SKILL_DIR}/../run-codex/scripts/run-codex.sh" review --base "$mb"
   ```

2. **Triage the output** using the process above. Present classified findings to the user.

3. **Take each finding that is not closed**, as `finding-triage` defines closed, as its disposition directs; where that is an edit, the user (or Claude) makes it and commits. If this step changed no file and the review is now clean, stop here.

4. **Re-run the review** — same command, same flags. The new diff includes the fix commits, so the reviewer sees the full picture: original changes plus fixes.

5. **Re-triage** — a finding dismissed as false positive in iteration N may become relevant in iteration N+1 if the fix changed the surrounding code. Don't carry over dismissals blindly.

6. **Repeat** steps 3–5 until the review is clean.

### What "clean" means

Every finding of the latest triage is closed, as `finding-triage` defines closed. A valid but minor finding keeps whichever SSOT disposition it earns — minor-ness alone never closes it.

## Important constraints

- **Run fresh**: run each review with fresh context — fresh reviews are the correct approach for iteration.
- **Timeout**: Set timeout to 600000ms (10 minutes) when calling from Bash. Reviews of large diffs can take several minutes.
