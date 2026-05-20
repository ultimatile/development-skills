---
name: codex-review
description: Pre-PR code review on the current branch using the OpenAI Codex CLI, with an iterative fix loop.
---

# Codex Review

Orchestrate `codex exec review` to review branch changes, iterate on fixes, and optionally proceed to PR creation with Copilot review.

## When to use

- Before creating a PR, to catch issues early
- When iterating on fixes and wanting to verify no regressions
- As part of a full PR pipeline: codex review → fix → PR → Copilot review

## Core commands

### Review branch diff against base

```bash
codex exec review --base <branch> -o <output-file>
```

This runs `git diff <base-SHA>` internally and reviews the entire diff. The review covers all committed changes on the current branch relative to the base — both the original work and any subsequent fix commits.

### Other review modes

| Command | Scope |
|---|---|
| `codex exec review --base main` | All commits since branching from main |
| `codex exec review --uncommitted` | Staged + unstaged + untracked changes |
| `codex exec review --commit <SHA>` | A single commit's diff |

### Output options

| Flag | Effect |
|---|---|
| `-o <file>` | Write final review message to file |
| `--json` | Emit JSONL event stream to stdout |
| `"custom prompt"` | Positional arg — additional review instructions |

## Triaging review output

codex review operates on `git diff` output alone — it has no access to the broader project context, test results, runtime behavior, or design rationale. This means a significant fraction of its findings will be false positives: technically plausible concerns that don't apply given information the reviewer can't see.

Typical false positive patterns:
- **Assumed standard behavior**: "this regex won't match standard X format" when the actual data uses a project-specific format (verified by tests)
- **Missing context on intentional decisions**: flagging a design choice as a bug when it was deliberate and tested
- **Hypothetical edge cases**: warning about inputs that can't occur given the system's constraints

When presenting review output, triage each finding:
1. **Read the review output** and identify each distinct finding (usually formatted as `[P1/P2] summary — file:line`)
2. **Cross-check against project context** you already have — test results, prior conversation, code you've read. You have far more context than the reviewer did.
3. **Classify each finding**:
   - **Actionable**: a real issue the reviewer correctly identified
   - **False positive**: plausible but wrong given context you have — explain why to the user
   - **Uncertain**: you can't tell without more investigation — flag it and investigate
4. **Present the triage** to the user, not the raw output. Lead with actionable items, note dismissed items with reasoning.

The user should never have to manually sift through false positives. That's your job.

## Review-fix loop

Each iteration runs a full, unbiased review of the entire diff against base. Do NOT inject previous review comments into the prompt — this narrows the reviewer's focus and risks missing new regressions introduced by the fix. The reviewer should always see the code with fresh eyes.

### Procedure

1. **Run review**
   ```bash
   codex exec review --base main -o /tmp/codex-review.md
   ```

2. **Triage the output** using the process above. Present classified findings to the user.

3. **If actionable issues are found**, the user (or Claude) fixes them and commits.

4. **Re-run the review** — same command, same flags. The new diff includes the fix commits, so the reviewer sees the full picture: original changes plus fixes.

5. **Re-triage** — a finding dismissed as false positive in iteration N may become relevant in iteration N+1 if the fix changed the surrounding code. Don't carry over dismissals blindly.

6. **Repeat** until no actionable findings remain or the user is satisfied.

### What "clean" means

No actionable findings after triage. A review with only false positives or minor style suggestions counts as clean — use judgment.

### Why fresh reviews matter

The goal of each iteration is to answer two questions:
- Did the fix correctly address the previous issue?
- Did the fix introduce any new problems?

A biased prompt ("check if X was fixed") answers only the first. A fresh review of the full diff answers both. The reviewer naturally focuses on whatever stands out in the current code, which is exactly what you want.

## Important constraints

- **No resume**: `codex review` does not support session resumption. Each invocation is independent. This is fine — fresh reviews are the correct approach for iteration.
- **Non-interactive only**: Always use `codex exec review`, not `codex review`, when running from scripts or automation. The `exec` variant runs non-interactively and exits when done.
- **Timeout**: Set timeout to 600000ms (10 minutes) when calling from Bash. Reviews of large diffs can take several minutes.

## Integration with PR creation

After the codex review loop produces a clean result, proceed to PR creation. If the Copilot review script is available:

```bash
${CLAUDE_SKILL_DIR}/../copilot-review/scripts/pr-with-copilot-review.sh --title "..." --body "..." --base main
```

This creates the PR, requests Copilot review, and polls until the review arrives. The full pipeline becomes:

```
codex review loop (local, fast feedback)
        ↓ clean
PR creation + Copilot review (remote, catches different issues)
        ↓ review received
Address Copilot feedback if needed
```

The two review stages are complementary: codex review catches implementation issues against the full diff, while Copilot review catches things visible only in the PR context (commit structure, description clarity, CI integration).
