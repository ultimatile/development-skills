---
name: diff-root
description: Single source of truth for the diff root — the ref a change is measured from — covering the consumer contract, where the root comes from, and the per-command range conversion. Definition file, not a procedure.
---

# Diff Root (SSOT)

This skill is **a definition file, not a runnable procedure**. Skills that use a root, and the callers that supply one, apply the rules below by reference. Do not copy these rules into them — point at them by name.

## What the root is

The **root** is the ref a change is measured from: what the branch's work is diffed and logged against.

It is a property of the work, not of the repository. Which ref the work is against is what the caller knows and the repository does not record — a branch ref carries no parent, and the reflog entry naming a branch's creation point is local, expires, and is absent from a fresh clone. No consumer can recover a root by inspecting the repository, and `git merge-base --fork-point` does not help, since it reads that same reflog.

## Consumer contract

A step that uses the root takes it as an input. It never resolves one and never defaults to one. Reached with no root, it **halts**, naming the missing input — whether or not a caller is present to ask, since the halt is the ask.

The root is one ref, not a range. Each step converts it to what its own command needs.

## Where the root comes from

The caller supplies it, **per gate invocation**. A caller whose gates all measure one change from one ref supplies that ref to each. A caller whose gates measure from different refs — a per-PR audit against an integration branch and a final PR against the default branch, say — supplies each gate its own.

Two ways a caller holds a root without guessing:

- **It created the branch.** An entry point that cut the working branch in this run records the ref it cut from. That is a record, not an inference.
- **It knows the arrangement.** A skill that set up a long-lived integration branch knows which gate measures from which ref, and states it per gate.

A caller with neither **asks the user**. Do not substitute a guess — not the default branch, not a PR's base, not a fork point. Each is right in some arrangement and silently wrong in others, and nothing in the repository distinguishes them.

## Spelling

The root arrives spelled as whoever supplied it wrote it. Use it as a revision unchanged. A step comparing it **by name** against the default branch strips the leading `origin/` from both first, and only that — `upstream/main` and `integration/x` keep their prefixes, so neither is ever mistaken for the default branch.

Where a rule needs the repository default branch, read it with `git symbolic-ref --short refs/remotes/origin/HEAD`, which prints `origin/<default>`. Empty output or a nonzero exit means remote HEAD was never fetched: run `git remote set-head origin -a`, and halt if that still resolves nothing. Never treat the unset result as a value — an empty string compares unequal to every branch name, so a guard built on one passes exactly when it should fire.

## Per-command conversion

| Command | Form | Why this form |
| -- | -- | -- |
| `git log` | `git log <root>..HEAD` — two dots | lists this branch's own commits; the three-dot form is the symmetric difference and adds the root's |
| `git diff` | `git diff <root>...HEAD` — three dots | measures from the merge base; the two-dot form is the endpoint diff and reports as this branch's own whatever landed on the root after the branch was cut |
| `codex exec review` | `--base` the merge base of the root and `HEAD` | the flag takes a single revision, and the merge base is correct whether the tool diffs endpoints or selects a merge base itself |

The dot forms do not normalize across commands. A sweep that makes them uniform reintroduces in one command the defect it removes from the other.

Resolve that merge base and check it non-empty **in the same shell invocation as the command that uses it** — a variable set in one shell is gone in the next, so a resolve step written elsewhere leaves the command with an empty base. Unquoted, an empty expansion also makes `--base` consume the following flag as its value.

**Never use `@{upstream}` as the root**, and do not repair it with a `--track` convention. It names the branch's own pushed copy: it errors before the first push, yields an empty diff after it, and `push -u` rebinds it.
