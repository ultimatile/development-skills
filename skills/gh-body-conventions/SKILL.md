---
name: gh-body-conventions
description: >
  Single source of truth for the formatting and content conventions that
  apply to GitHub issue bodies and pull request bodies / descriptions.
  Defines semantic line-break rules, LaTeX-safe math syntax, reference /
  exclusion policies, and language defaults. This is a definition file;
  skills drafting body content reference these rules rather than
  duplicating them.
---

# GitHub Body Conventions (SSOT)

This skill is **a definition file, not a runnable procedure**. Skills that draft GitHub issue / PR body content apply these conventions by reference. When a rule changes here, referencing skills pick up the change automatically; do not copy these rules into them — point at them by name.

## Formatting

- **Semantic line breaks, not column wrapping.** Do NOT hard-wrap to 72/80 columns the way commit message bodies do. Break lines at sentence boundaries, clause boundaries, or paragraph boundaries — wherever the structure of the prose suggests. The reader uses a wide viewport with its own wrapping; column-wrapped bodies render as random ragged text.
  - One sentence per line, OR
  - One clause per line for long sentences, OR
  - Plain paragraphs with blank-line separation.
- Pick whichever of the three above is most readable for the content; do not mix styles within one section.

## Authoring via shell heredoc

GitHub bodies passed via `gh pr create --body "$(cat <<'EOF' ... EOF)"` / `gh issue create --body-file ...` / `gh pr edit --body "$(cat <<'EOF' ... EOF)"` must arrive at the GitHub API with **literal** Markdown content, no shell escaping artifacts. The most common corruption shape is reflexive backtick escaping inside a single-quoted heredoc.

- **Default to single-quoted delimiters: `<<'EOF'`.** Inside `<<'EOF'`, no expansion or escape interpretation runs at all — variable references (`$foo`), command substitution (`` `cmd` ``), and backslash escapes pass through literally. Write the body exactly as it should appear on GitHub.
- **Do NOT escape backticks, `$`, or `\` inside `<<'EOF'`.** Reflex-escaping `` ` `` → `` \` `` produces a literal `` \` `` in the output, which Markdown renders as `` \` `` (backslash then backtick) — breaking code spans (`` `foo` `` becomes `` \`foo\` ``).
- **Only use unquoted `<<EOF` when expansion is intentionally needed.** Unquoted heredocs run command substitution and variable expansion; that is the only scenario where backtick escaping makes sense. PR / issue bodies almost never need expansion, so this should be rare.
- **Verify after large bodies.** When a body contains many code spans, after the `gh pr create` / `gh pr edit`, fetch it back with `gh pr view <N> --json body -q .body` (or `gh issue view`) and grep for `\\\`` — any hit is a corruption that needs `gh pr edit` to repair.

## Math

- Use LaTeX notation for mathematical expressions, rendered with GitHub's `` $`...`$ `` syntax for inline math and `$$...$$` syntax for display math.
- Prefer `` $`...`$ `` over `$...$` for inline math; it avoids common Markdown parsing conflicts.
- Plain text inside backticks is fine when the symbol must match a code identifier verbatim (e.g., `` `alpha_t` `` referring to a variable named `alpha_t` in the code).
- Do NOT write raw Unicode math characters (α, β, ⊗, ∑, ∇, †, etc.) in prose. Use `` $`\alpha`$ ``, `` $`\otimes`$ ``, `` $`\sum`$ ``, `` $`\nabla`$ ``, `` $`\dagger`$ `` instead. Unicode-math-in-prose is the user's strongest formatting dislike.
- Avoid `\_` in GitHub/LaTeX math. Use `` $`\mathrm{\textunderscore}`$ `` when an underscore glyph is required in math mode.
- Do NOT use `\textunderscore` inside `\text{...}` or `\texttt{...}`; GitHub's LaTeX-style math rendering does not accept it there. Restructure the expression, or put the literal identifier in Markdown backticks outside math when exact code spelling matters.
- When two inline math spans are separated by punctuation, put a space before the second math opener so GitHub recognizes it. Write `` $`K_1`$/ $`K_2`$ ``, not `` $`K_1`$/$`K_2`$ ``.

## References

- Do NOT cite local file paths, local notes, HPC cluster paths, or anything an external reader cannot open.
- If the substance of a local reference matters, inline its content (quote, paraphrase, or reproduce the relevant snippet) so the body is self-contained.
- External references (arXiv, DOI, public repo URLs, public docs, other issues / PRs in the same or public repos) are fine.
- Cross-repo references to *private* repos are also off-limits — same reason.

### Line numbers

Line-number citations are governed by whether the surrounding artifact anchors them to a stable commit:

- **Issue body — forbidden.** Issue bodies refer to the default branch's `HEAD` implicitly, which moves; cited line numbers go stale within hours of the next merge. If a specific location matters, inline a code snippet instead.
- **PR body — permitted within this PR's own diff.** A PR is anchored to explicit ours/theirs commits, so a line number cited against a file in this PR's diff does not rot. Even so, when the comment is about a single specific line, prefer an inline review comment over a body reference; the inline comment is rendered next to the code.

## Language

- Default to English for the title and body.
- Use Japanese only when the user explicitly asks for it, or when the surrounding repo's existing issues / PRs are predominantly Japanese.
- Inline Japanese clauses inside an otherwise-English body are leakage from the private surface (chat is mixed JP/EN; the public surface picks one). Re-cast in the chosen language even when the Japanese clause technically conveys information.

## Length

- Be concise but do not omit explanation. Say what is needed and stop.
- Skip narrative scaffolding ("As we discussed...", "Following up on..."), restated context the reader can see from the repo, and exhaustive option enumeration when one option is clearly preferred.
- Every paragraph should be earning its place.

Artifact-specific length expectations live in the referencing skills (`file-issue`, `file-pullreq`).

## Exclusions

This list is the mechanical-detection half of the private-to-public laundering protocol (see CLAUDE.md "Two-surface boundary and laundering before publishing"). The cold re-read across the five axes is the substantive half; the patterns below are the leak shapes most often caught.

The body must NOT contain:

- Local filesystem paths (`/Users/...`, `~/...`, absolute paths).
- HPC cluster names, hostnames, queue names, or scheduler-specific context that is irrelevant to the upstream reader.
- References to the user's private repos, skills, or workflow internals (e.g., `/file-pullreq`, `research-and-implement-egel`, `done-check`). These are author-side tools, not reader-facing artifacts; the public body must justify itself from the repo's own state.
- Phase / step numbers from the working session ("Phase 2 of the umbrella", "Step 3 of the plan") unless the artifact is *itself* an umbrella sub-issue / sub-PR where that structure is public.
- "As we discussed" / "following up from chat" / other chat-tone scaffolding that resolves only via the private context.
- Inline Japanese clauses in an otherwise-English body (see Language).

Before filing, perform the cold re-read across References / Tone / Language / Structure / Trigger-flag (CLAUDE.md axes). The list above covers the patterns the cold re-read most often catches; novel leak shapes still require the cold re-read.
