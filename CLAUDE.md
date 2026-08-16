# CLAUDE.md

Repo-specific rules for Claude Code when editing this repository.
Violations of any rule below are blockers — fix before declaring a task complete.

## Commit message conventions

**Prohibited forms:**

- `refactor(<anything>): ...` — SKILL has no "refactor" concept. The notion of refactoring does not apply at the skill level in this repo.
- `<type>(skills): ...` — the literal scope name `skills` is forbidden. The `skills/` tree is the global context of this repo; using `skills` as a scope adds no information. Use a bare `<type>: ...` (no scope) for repo-wide changes, or name the specific skill(s).

**Type selection:**

Surface-specific overrides (apply first):

- **Documentation-only** change (top-level doc files including `README.md` and `CLAUDE.md`, anything under `docs/` if added later) → `docs` (regardless of add/remove). These don't change plugin behavior, so no bump and no tag (see Versioning below).
- **Development tooling and repo metadata** — a surface no consumer of the installed plugin can observe, because no `SKILL.md` step reads or runs it: `.claude-plugin/marketplace.json`, `.pre-commit-config.yaml`, `.gitignore`, linter / formatter config, and a bundled test no `SKILL.md` invokes → `chore` (regardless of add/remove). Routine version bumps with no other change fall here. A file under `skills/` qualifies only when no `SKILL.md` step names it; anything a step names is skill content and takes the coarse rule below.
- **Pure formatting pass** (whitespace, table padding, list renumbering, or any other output of a formatter such as `mdformat` with no semantic content change) → `style`, regardless of which files it touches (`skills/` included). These change no plugin behavior, so no bump and no tag (see Versioning below).

For changes touching skills / code / other content (coarse rule):

- **Additions only** (new skill, new lines, no content removed or swapped) → `feat`
- **Removals or replacements** (line deletions, content swaps, behavior changes that overwrite prior content) → `fix`

**Scope selection:**

- Single skill change → `feat(<skill-name>): ...` / `fix(<skill-name>): ...`
- Multiple skills changed in one commit → `feat(<skill1>,<skill2>): ...` (comma-separated, no spaces)
- Repo-global change that touches no skill and doesn't fit a `docs` / `chore` surface override → no scope: `feat: ...` / `fix: ...`

`docs` commits per the type-selection overrides above carry no scope — that surface IS the entire change.
A `chore` commit takes the scope rules above: confined to one skill's directory it carries that skill's name, and a repo-global tooling surface leaves it bare.

## Versioning

`.claude-plugin/marketplace.json` carries `metadata.version` in CalVer **`YYYY.M.p`** form, where:

- `YYYY` = 4-digit year
- `M` = month (no zero-padding; `2026.5.51`, not `2026.05.51`)
- `p` = patch counter, **not** the day. Monotonically increases within a month.

**Bump rule:**

- Bump `metadata.version` on **`feat` and `fix` commits only**. These represent plugin-behavior changes that consumers should be able to pin to.
- **Do NOT bump on `docs`, `chore`, or `style` commits.** These are out-of-band housekeeping (README rewording, marketplace.json formatting / metadata edits that aren't a version, formatter output) and produce no consumer-visible behavior delta.
- When bumped, the new version becomes the git tag for that commit. No `v` prefix.
- Example: current `2026.5.51` → next `feat`/`fix` commit tags `2026.5.52`. A `docs` or `chore` commit between them carries no tag and leaves the version untouched.

If the month rolls over mid-series, reset `p` to `1` (e.g., `2026.5.99` → `2026.6.1`).

## Skill list maintenance

When adding or removing a skill, **both** lists must be updated in the same commit:

1. `.claude-plugin/marketplace.json` → `plugins[0].skills` array.
2. `README.md` → skill table under the appropriate category section.

Language-specific skills go under `skills/languages/<Language>/<skill-name>/` (current examples: `skills/languages/Rust/cargo-mutants`, `skills/languages/Rust/rust-ffi-rule`). The marketplace.json `skills` entries use the relative path including the `languages/<Language>/` prefix.

## Worktree development

Work on this repository in a **git worktree** by default. The main checkout is for reading and for the exceptional direct commit only. A worktree cannot check out `main` (the main checkout holds it), so worktree changes land through the "PR + squash merge" lane below.

### Wire the skills into the worktree

Immediately after creating the worktree, **before editing any file**, wire the worktree's own skills into it, from inside the worktree:

```sh
cd <worktree> && add-skill . --symlink-force
```

Verify before the first skill dispatch: `ls -l <worktree>/.claude/skills/done-check` must resolve to a path under the worktree. Any step that resolves `<SKILLS_DIR>` (`done-check`, `todo-check`, and the like) must land on the worktree side — check the resolved path, not the skill name.

### Settle the version number at the merge gate

Concurrent worktrees all bump from the same `main`, so the number a branch picks while implementing is provisional — another branch can land it first. At the merge gate, before merging, read the published value with `git show origin/main:.claude-plugin/marketplace.json` (fetch first). If the branch's `metadata.version` is no longer the next patch counter from that value, re-bump to the correct one and push that fix-up. This does not add a second bump: the branch still carries exactly one bump (see "Landing a branch"), and only its value is revised. The tag applied after the merge is the settled value.

## Commit workflow

A change reaches `main` one of two ways; determine which before you bump or tag, because the timing differs:

- **Direct commit to `main`** — available only in the main checkout, which is the exception (see "Worktree development"). The commit you create is itself the published change. Bump and tag on it, following "Landing a direct commit" below.
- **PR + squash merge** — any reviewed-implementation flow (`reimre`, `review-pipeline`, and the like) puts several commits on a feature branch that collapse into one squash-merge commit on `main`. The published unit is that merge commit, not the branch commits. Follow "Landing a branch" below.

"Every commit" below applies to both lanes, worktree branches included; the lanes diverge only in when the version is tagged and pushed.

### Every commit

For every commit, on `main` or on a branch:

1. Make the code / skill / doc changes.

2. Update `.claude-plugin/marketplace.json` as applicable:

   - Bump `metadata.version` — **only on `feat` / `fix` commits**; skip on `docs` / `chore`. On a branch this happens once for the whole branch, not once per commit (see "Landing a branch").
   - Update `plugins[0].skills` (only if adding or removing a skill).

3. Update `README.md` skill table (only if adding or removing a skill).

4. Stage and commit with a conventional-commit message per the rules above.

   **Formatter-hook abort.** A pre-commit hook that reformats files and reports `Failed` because it _modified_ files has **aborted the commit** — no commit was created and `HEAD` did not move. Re-stage the hook's output (`git add` the reformatted paths) and re-run the commit until the hook reports `Passed`. Do not proceed to tagging until a commit actually lands.

### Landing a direct commit

1. **On `feat` / `fix` commits only**: `git tag <new-version>` on the commit just created. `docs`, `chore`, and `style` commits are not tagged.

   **Verify before tagging.** Confirm the commit landed and `HEAD` is the new commit (`git log --oneline -1`) _before_ `git tag`. Tagging blind after a formatter-aborted commit ("Every commit", step 4) applies the version to the previous, unrelated `HEAD` — a broken state. If a tag was misapplied, `git tag -d <version>` and re-tag once the real commit exists.

2. Push:

   - `feat` / `fix`: `git push && git push origin <new-version>` (commit then tag explicitly).
   - `docs` / `chore` / `style`: `git push`.

   Tags in this repo are **lightweight** (`git tag <name>`, no `-a`). `git push --follow-tags` only pushes annotated tags, so it will silently skip lightweight tags — always push lightweight tags by name. If a `feat` / `fix` commit lands on the remote without its corresponding tag, that is a broken state — push the tag immediately.

### Landing a branch (PR + squash merge)

The branch commits are drafts; only the squash-merge commit lands on `main`. Two consequences:

- **Bump at most once.** Bump `metadata.version` a single time on the branch — on the first `feat` / `fix` change — and leave it untouched on the fix-up commits that answer review feedback. All branch commits squash into one, which must carry exactly one bump; re-bumping per fix-up commit is wrong.
- **Tag after the merge, never on the branch.** The squash merge creates a new commit on `main` whose SHA exists nowhere on the branch, so a tag placed on a branch commit would not point at the published change. Once the PR merges, check out `main`, pull, then `git tag <version>` on the squash-merge commit and `git push origin <version>`.
