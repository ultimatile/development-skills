---
name: finding-to-audit
description: Promote a review finding into a pre-commit audit rule that catches the diff-inspectable issue class (import direction, pub widening, debug artifacts, dropped FFI output). Companion to bug-to-contract.
---

# Finding-to-Audit

A single fix prevents one bug. An audit rule prevents the entire class without waiting for the next bug to surface.

## Inputs

The fix-commit lane uses a **root** on `diff-root`'s consumer contract, halt included; the review-findings lane uses none.

| Input | What to collect |
| -- | -- |
| Review findings | Actionable findings that resulted in code changes — the reviewer's framing of the issue |
| Fix commits | Branch commits whose subject signals a fix: `git log <root-rev>..HEAD --oneline --grep="fix" -i`, then `git show <sha>` |

## Procedure

### 1. Collect signals

For each finding or fix, note what the issue was and what changed.

### 2. Classify

Would a structured inspection of the diff have caught it?

- **Yes** → continue here.
- **No, only runtime testing would** → switch to `bug-to-contract`.

Examples that fit this skill:

- Import direction violation (lower module imports from higher)
- `pub` exposed beyond what the architectural rule allows
- Missing standard trait impl on a public type (e.g. `Display`, `std::error::Error`, `Send`/`Sync` on a public error)
- New behavior added but no test reads its outputs
- Hardcoded constant that should be a parameter
- Debug artifact (`dbg!`, trace `println!`, commented-out code)
- FFI output channel silently dropped
- Public enum without `#[non_exhaustive]` where future variants are expected

### 3. Identify the host audit skill

| Concern | Host |
| -- | -- |
| Universal code quality | `quality-list` |
| Quality of text the agent executes as instructions | `authoritative-text-rules` |
| FFI safe-wrapper rules | `rust-ffi-rule` (or language-specific equivalent) |
| Other domain-specific audit | The matching skill |

If no host fits, scaffold a new audit skill rather than forcing the rule into an unrelated one.

### 4. Draft the rule

Use the host's existing format, read from a sibling item in that host. For a rule-set SSOT, an item is its own file under the SSOT's `items/` directory, added to the SSOT's Items index in the same change, and shaped:

```
# <Item name>

<rule description: what to check, in 1–2 sentences>

**Concern conditions:**

- <specific diff-inspectable signal>
- ...

**N/A:** <when the rule does not apply>
```

A host may require more, in the body and in the index entry alike — `quality-list` tags each index entry with the lane that routes it, and `authoritative-text-rules` items additionally carry a Trigger, a Sweep the auditor executes, and a tie-break against sibling items. The sibling entry and sibling body you read are the authority on which parts are required; an item whose index entry omits what its host's runners select on is reachable by no lane.

The rule must be **diff-inspectable** — verifiable against `git diff` output, file paths, or grep, without running the code. If the check requires execution, it belongs in `bug-to-contract`.

### 5. Land the rule

Promoting a finding to a rule is a proposal to be reviewed, not an edit to apply from wherever the finding surfaced.

**Default — file an issue** against the host skill's repository via `file-issue`, handing it:

- **Host (proposed)** — the host from step 3 (`quality-list`, `authoritative-text-rules`, `rust-ffi-rule`, or a new skill); a hypothesis the issue confirms or redirects.
- **Finding** — what the review caught and where the fix landed; link the work-repo PR / issue for provenance.
- **Issue class** — the generalizable diff-inspectable class, not the one token that slipped.
- **Proposed rule** — the step-4 draft (item name, concern conditions, N/A carve-out).

The rule then lands as a reviewed change in that repository. On recurrence of a class that already has an open proposal, comment on it instead of filing a duplicate.

**Escape hatch — edit the host skill directly** only when filing is inappropriate: a skill not under version control, or an explicit opt-in for the case at hand. The same failure-mode-plus-proposal content still travels with the change (e.g. in the PR body), so the diff is never bare. Update any output tables in the host file.

### 6. Backfill check

If the same issue class has surfaced more than once historically, strengthen the rule (tighter conditions, additional concern signals) rather than relying on a single occurrence.

## Principles

- **Propose, don't apply.** A rule promotion targets a shared audit surface; default to a reviewed issue against its repository, not an in-place edit from the finding's context.
- **General over specific.** The rule catches the bug class, not the reviewer's exact wording.
- **Diff-inspectable only.** Anything requiring code execution belongs in `bug-to-contract`.
- **Extend before adding.** Strengthening an existing audit item is preferable to adding a new one unless the topic is orthogonal to all existing items.
