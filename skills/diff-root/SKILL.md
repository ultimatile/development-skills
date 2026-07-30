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

The caller supplies it, **per gate invocation**, and the two kinds of gate take different values.

A **PR-scope gate** — the audit that closes the work, the code-review gate, the pre-open codex review, the reviewer on the open PR — takes the **branch the change merges into**, spelled as its remote-tracking ref. That is the PR's base, whether or not the PR exists yet. Anything else makes the gate review something other than what merges, in one of two directions: a root ahead of the base drops commits the branch inherited without authoring, and those land unreviewed; a root behind it pulls in work other branches already merged and reviewed, which cannot be fixed here and yields findings indefinitely.

An **incremental gate** — a per-unit review, a per-commit audit during implementation — takes the last approved point instead, and deliberately reviews less. Incremental gates exist for early feedback and establish no coverage: every commit that lands must fall inside some PR-scope gate's range.

A caller that does not know the merge target **asks the user**. Do not substitute a guess — not the repository default branch, not the ref the branch was cut from, not a fork point. The cut-from ref is the sharpest of those traps: a branch is routinely cut from a local ref that is ahead of or behind what it will merge into, and nothing in the repository records the merge target at all.

## Spelling

A root is either a **branch** or a **commit**. A commit root — a SHA or tag, which an incremental gate uses to fix a point a moving branch ref cannot name — is a revision already: use it unchanged, and note it never reaches a forge argument, since no PR opens against a SHA.

A branch root is supplied as a **bare branch name**, and that is the only spelling a caller may pass. Two uses follow from it:

- **A revision argument** — `git log`, `git diff`, `git merge-base` — takes `origin/<root>`. The bare name would resolve to the local branch, which is routinely ahead of or behind the remote one the work merges into.
- **A branch name on the forge** (`gh pr create --base`, `gh pr edit --base`) and **a comparison against this repository's default branch** take the root as supplied.

One input spelling is what keeps this decidable. A rule accepting either could not tell a remote-tracking ref from a branch whose own first segment happens to match a remote's name — `upstream/release` under an `upstream` remote is both readings at once, and picking wrong selects a different history and a different PR base.

**One repository.** These rules assume `origin` is the repository the work merges into — the one the branch is pushed to and the PR opens in. A cross-fork arrangement, where `origin` is a fork and the PR targets a different repository, is outside them: a bare branch name cannot name a repository, so a root supplied there would send the gates to the fork's branch while the PR targets the other one's. Nothing else in this skill set carries a target remote either — the pipeline's branch guard, the PR-base derivation, and the push all read `origin`. In that arrangement, halt and surface it rather than stretching these rules over it.

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
