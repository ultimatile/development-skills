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
- **`.claude-plugin/marketplace.json` only** change → `chore` (regardless of add/remove). Routine version bumps with no other change fall here.

For changes touching skills / code / other content (coarse rule):

- **Additions only** (new skill, new lines, no content removed or swapped) → `feat`
- **Removals or replacements** (line deletions, content swaps, behavior changes that overwrite prior content) → `fix`

**Scope selection:**

- Single skill change → `feat(<skill-name>): ...` / `fix(<skill-name>): ...`
- Multiple skills changed in one commit → `feat(<skill1>,<skill2>): ...` (comma-separated, no spaces)
- Repo-global change that touches no skill and doesn't fit a `docs` / `chore` surface override → no scope: `feat: ...` / `fix: ...`

`docs` and `chore` commits per the type-selection overrides above also carry no scope — those surfaces ARE the entire change.

## Versioning

`.claude-plugin/marketplace.json` carries `metadata.version` in CalVer **`YYYY.M.p`** form, where:

- `YYYY` = 4-digit year
- `M` = month (no zero-padding; `2026.5.51`, not `2026.05.51`)
- `p` = patch counter, **not** the day. Monotonically increases within a month.

**Bump rule:**

- Bump `metadata.version` on **`feat` and `fix` commits only**. These represent plugin-behavior changes that consumers should be able to pin to.
- **Do NOT bump on `docs` or `chore` commits.** These are out-of-band housekeeping (README rewording, marketplace.json formatting / metadata edits that aren't a version) and produce no consumer-visible behavior delta.
- When bumped, the new version becomes the git tag for that commit. No `v` prefix.
- Example: current `2026.5.51` → next `feat`/`fix` commit tags `2026.5.52`. A `docs` or `chore` commit between them carries no tag and leaves the version untouched.

If the month rolls over mid-series, reset `p` to `1` (e.g., `2026.5.99` → `2026.6.1`).

## Skill list maintenance

When adding or removing a skill, **both** lists must be updated in the same commit:

1. `.claude-plugin/marketplace.json` → `plugins[0].skills` array.
2. `README.md` → skill table under the appropriate category section.

Language-specific skills go under `skills/languages/<Language>/<skill-name>/` (current examples: `skills/languages/Rust/cargo-mutants`, `skills/languages/Rust/rust-ffi-rule`). The marketplace.json `skills` entries use the relative path including the `languages/<Language>/` prefix.

## Commit workflow

For every commit:

1. Make the code / skill / doc changes.
2. Update `.claude-plugin/marketplace.json` as applicable:
   - Bump `metadata.version` — **only on `feat` / `fix` commits**; skip on `docs` / `chore`.
   - Update `plugins[0].skills` (only if adding or removing a skill).
3. Update `README.md` skill table (only if adding or removing a skill).
4. Stage and commit with a conventional-commit message per the rules above.
5. **On `feat` / `fix` commits only**: `git tag <new-version>` on the commit just created. `docs` and `chore` commits are not tagged.
6. Push:
   - `feat` / `fix`: `git push && git push origin <new-version>` (commit then tag explicitly).
   - `docs` / `chore`: `git push`.

   Tags in this repo are **lightweight** (`git tag <name>`, no `-a`). `git push --follow-tags` only pushes annotated tags, so it will silently skip lightweight tags — always push lightweight tags by name. If a `feat` / `fix` commit lands on the remote without its corresponding tag, that is a broken state — push the tag immediately.
