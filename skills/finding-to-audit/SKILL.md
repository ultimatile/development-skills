---
name: finding-to-audit
description: >
  Promote review findings or bug fixes into pre-commit audit rules
  that catch the entire class of issue at diff-inspection time. Use
  this skill when a review finding could have been caught by
  inspecting the diff itself — import direction, `pub` widening,
  missing trait impl on a public type, missing test for new
  behavior, debug artifacts, hardcoded values, FFI output
  silently dropped — where a runtime contract test is the wrong
  tool. Companion to `bug-to-contract`: that skill elevates findings
  to runtime tests; this one elevates to diff-time rules.
---

# Finding-to-Audit

A single fix prevents one bug. An audit rule prevents the entire
class without waiting for the next bug to surface.

## When to use vs `bug-to-contract`

| Catch at | Tool |
|---|---|
| Runtime — output value, behavior under input, invariant on data, concurrency | `bug-to-contract` (contract test) |
| Diff-inspection — structural property visible from `git diff`, imports, `pub` surface, presence of tests, debug artifacts, hardcoded values | `finding-to-audit` (this skill) |

A single finding can map to either, both, or neither. Use both
when both apply.

## Inputs

| Input | What to collect |
|---|---|
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
- Missing standard trait impl on a public type (e.g. `Display`,
  `std::error::Error`, `Send`/`Sync` on a public error)
- New behavior added but no test reads its outputs
- Hardcoded constant that should be a parameter
- Debug artifact (`dbg!`, trace `println!`, commented-out code)
- FFI output channel silently dropped
- Public enum without `#[non_exhaustive]` where future variants are
  expected

### 3. Identify the host audit skill

| Concern | Host |
|---|---|
| General code-quality / pre-commit checklist | `done-check` (add a section, or extend an existing one) |
| FFI safe-wrapper rules | `rust-ffi-rule` (or language-specific equivalent) |
| Other domain-specific audit | The matching skill |

If no host fits, scaffold a new audit skill rather than forcing
the rule into an unrelated one.

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

The rule must be **diff-inspectable** — verifiable against `git diff`
output, file paths, or grep, without running the code. If the check
requires execution, it belongs in `bug-to-contract`.

### 5. Edit the host skill

Add the rule directly. Renumber if needed and update any output
tables in the host file.

### 6. Backfill check

If the same issue class has surfaced more than once historically,
strengthen the rule (tighter conditions, additional concern signals)
rather than relying on a single occurrence.

## Principles

- **General over specific.** The rule catches the bug class, not
  the reviewer's exact wording.
- **Diff-inspectable only.** Anything requiring code execution
  belongs in `bug-to-contract`.
- **Extend before adding.** Strengthening an existing audit item
  is preferable to creating a new section unless the topic is
  orthogonal to all existing items.
