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

The caller supplies it **per gate invocation**, and states which of two kinds that invocation is. The kind belongs to the invocation, not to the skill invoked — the same skill is one kind in one flow and the other elsewhere — and the caller is the only party that knows which.

A **coverage** invocation must hold everything the change will merge, so that no defect inside its range reaches the merge unseen. Its root is therefore the **branch the change merges into**: the PR's base, whether or not the PR exists yet. Anything else reviews something other than what merges, in one of two directions. A root ahead of the base drops commits the branch inherited without authoring, and those land unreviewed. A root behind it pulls in work other branches already merged and reviewed, which cannot be fixed from here and yields findings indefinitely.

An **incremental** invocation reviews only what is new since a point some coverage invocation already held, for early feedback on that increment. Its root is that point — usually the last approved commit, named as a SHA because a branch ref moves off it. It establishes no coverage of its own, so every commit that lands must still fall inside some coverage invocation's range.

A caller that does not know the merge target **asks the user**. Do not substitute a guess — not the repository default branch, not the ref the branch was cut from, not a fork point. The cut-from ref is the sharpest of those traps: a branch is routinely cut from a local ref that is ahead of or behind what it will merge into, and nothing in the repository records the merge target at all.

## Spelling

A root is either a **branch** or a **commit**. A commit root — a SHA or tag, which an incremental gate uses to fix a point a moving branch ref cannot name — is a revision already: use it unchanged, and note it never reaches a forge argument, since no PR opens against a SHA.

A branch root is supplied as a **bare branch name**, and that is the only spelling a caller may pass.

Two metavariables keep the uses apart, and every rule below and in every consumer spells the one it means:

- `<root>` — the root as supplied.
- `<root-rev>` — its revision spelling. For a branch root that is `origin/<root>`; for a commit root the two are the same string.

`<root-rev>` is a local cache of a branch that lives on the forge, so **refresh it before building a range**: `git fetch origin <root>`. Without that the range measures from wherever the cache last stood, which goes stale exactly where it matters most — a long-lived integration branch advances on the forge every time one of its pull requests merges.

**Revision arguments take `<root-rev>`** — `git log`, `git diff`, `git merge-base`, and anything else resolving a ref. A bare branch name there resolves to the local branch, which is routinely ahead of or behind the remote one the work merges into, so writing `<root>` where `<root-rev>` belongs reintroduces exactly the wrong-scope review this contract exists to prevent.

**A branch name on the forge takes `<root>`** — `gh pr create --base`, `gh pr edit --base`. So does a comparison against this repository's default branch, which is read prefixed and must have that prefix stripped before comparing, since `<root>` carries none.

One input spelling is what keeps this decidable. A rule accepting either could not tell a remote-tracking ref from a branch whose own first segment happens to match a remote's name — `upstream/release` under an `upstream` remote is both readings at once, and picking wrong selects a different history and a different PR base.

**One repository.** These rules assume `origin` is the repository the work merges into — the one the branch is pushed to and the PR opens in. A cross-fork arrangement, where `origin` is a fork and the PR targets a different repository, is outside them: a bare branch name cannot name a repository, so a root supplied there would send the gates to the fork's branch while the PR targets the other one's. Nothing else in this skill set carries a target remote either — the pipeline's branch guard, the PR-base derivation, and the push all read `origin`. In that arrangement, halt and surface it rather than stretching these rules over it.

Where a rule needs the repository default branch, read it bare, in one block:

```bash
default=$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's@^origin/@@')
test -n "$default" || { echo "remote HEAD unset — run: git remote set-head origin -a"; exit 1; }
```

Both lines are load-bearing. The `sed` is what makes the result comparable with `<root>`, which carries no prefix, since the ref prints as `origin/<default>`. Empty output or a nonzero exit means remote HEAD was never fetched; the check catches that, because an unset value is the empty string, which compares unequal to every branch name — a guard built on one passes exactly when it should fire. Never treat that result as a value: run `git remote set-head origin -a`, and halt if it still resolves nothing.

## Per-command conversion

| Command | Form | Why this form |
| -- | -- | -- |
| `git log` | `git log <root-rev>..HEAD` — two dots | lists this branch's own commits; the three-dot form is the symmetric difference and adds the root's |
| `git diff` | `git diff <root-rev>...HEAD` — three dots | measures from the merge base; the two-dot form is the endpoint diff and reports as this branch's own whatever landed on the root after the branch was cut |
| `codex exec review` | `--base` the merge base of the root and `HEAD` | the flag takes a single revision, and the merge base is correct whether the tool diffs endpoints or selects a merge base itself |

The dot forms do not normalize across commands. A sweep that makes them uniform reintroduces in one command the defect it removes from the other.

Resolve that merge base and check it non-empty **in the same shell invocation as the command that uses it** — a variable set in one shell is gone in the next, so a resolve step written elsewhere leaves the command with an empty base. Unquoted, an empty expansion also makes `--base` consume the following flag as its value.

**Never use `@{upstream}` as the root**, and do not repair it with a `--track` convention. It names the branch's own pushed copy: it errors before the first push, yields an empty diff after it, and `push -u` rebinds it.
