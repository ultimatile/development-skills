---
name: finding-to-audit
description: Promote a review finding into a pre-commit audit rule that catches the diff-inspectable issue class (import direction, pub widening, debug artifacts, dropped FFI output). Companion to bug-to-contract.
---

# Finding-to-Audit

A single fix prevents one bug. An audit rule prevents the entire class without waiting for the next bug to surface.

## Inputs

| Input | What to collect |
| -- | -- |
| Review findings | Actionable findings that resulted in code changes — the reviewer's framing of the issue |
| Fix commits | Branch commits whose subject signals a fix: `git log main..HEAD --oneline --grep="fix" -i`, then `git show <sha>` |

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
| General code-quality / pre-commit checklist | `done-check` (add a section, or extend an existing one) |
| FFI safe-wrapper rules | `rust-ffi-rule` (or language-specific equivalent) |
| Other domain-specific audit | The matching skill |

If no host fits, scaffold a new audit skill rather than forcing the rule into an unrelated one.

### 4. Draft the rule

Use the host's existing format. For `done-check`:

```
### N. <Item name>

<rule description: what to check, in 1–2 sentences>

**Concern conditions:**

- <specific diff-inspectable signal>
- ...

**N/A:** <when the rule does not apply>
```

The rule must be **diff-inspectable** — verifiable against `git diff` output, file paths, or grep, without running the code. If the check requires execution, it belongs in `bug-to-contract`.

### 5. Land the rule

Promoting a finding to a rule is a proposal to be reviewed, not an edit to apply from wherever the finding surfaced.

**Default — file an issue** against the host skill's repository via `file-issue`, handing it:

- **Host (proposed)** — the audit skill from step 3 (`done-check`, `rust-ffi-rule`, or a new skill); a hypothesis the issue confirms or redirects.
- **Finding** — what the review caught and where the fix landed; link the work-repo PR / issue for provenance.
- **Issue class** — the generalizable diff-inspectable class, not the one token that slipped.
- **Proposed rule** — the step-4 draft (item name, concern conditions, N/A carve-out).

The rule then lands as a reviewed change in that repository. On recurrence of a class that already has an open proposal, comment on it instead of filing a duplicate.

**Escape hatch — edit the host skill directly** only when filing is inappropriate: a skill not under version control, or an explicit opt-in for the case at hand. The same failure-mode-plus-proposal content still travels with the change (e.g. in the PR body), so the diff is never bare. Renumber if needed and update any output tables in the host file.

### 6. Backfill check

If the same issue class has surfaced more than once historically, strengthen the rule (tighter conditions, additional concern signals) rather than relying on a single occurrence.

## Principles

- **Propose, don't apply.** A rule promotion targets a shared audit surface; default to a reviewed issue against its repository, not an in-place edit from the finding's context.
- **General over specific.** The rule catches the bug class, not the reviewer's exact wording.
- **Diff-inspectable only.** Anything requiring code execution belongs in `bug-to-contract`.
- **Extend before adding.** Strengthening an existing audit item is preferable to creating a new section unless the topic is orthogonal to all existing items.
