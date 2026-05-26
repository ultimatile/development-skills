---
name: gh-body-conventions
description: Single source of truth for GitHub issue / PR body conventions — semantic line breaks, LaTeX-safe math, reference / exclusion policies, language defaults. Definition file, not a procedure.
---

# GitHub Body Conventions (SSOT)

Skills that draft GitHub issue / PR body content apply these conventions by reference. Do not copy these rules into them — point at them by name.

## Formatting

- **Semantic line breaks, not column wrapping.** Do NOT hard-wrap to 72/80 columns. Break lines at sentence, clause, or paragraph boundaries.
  - One sentence per line, OR
  - One clause per line for long sentences, OR
  - Plain paragraphs with blank-line separation.
- Pick whichever of the three is most readable; do not mix styles within one section.
- **Do NOT break below the clause level.** A line break must land on a sentence boundary, an independent clause boundary, or a coordinated-clause boundary (`and` / `or` / `but` joining full clauses, not phrases). Forbidden break positions:
  - Between subject and verb.
  - After a preposition or a preposition + object fragment.
  - Inside a noun phrase or after a determiner / adjective stranding its head noun.
  - After a comma that separates list items, appositives, or modifiers within one clause.
  - Before a coordinating conjunction (`and` / `or` / `but`) joining phrases rather than clauses.
- When in doubt, prefer flat prose over fragmented clauses.

## Titles

- Do NOT put issue numbers in PR titles — no trailing `(#123)` suffix (e.g. `fix: blah-blah (#123)`) and no bare `#123`. Issue linkage goes in the body via `Closes #N`.

## Authoring via file

Write the body to a file (typically under `/tmp/`) and pass it to the `gh-post` wrapper via `--body-file`. Direct `gh (issue|pr) (create|edit|comment) --body*` is blocked by a `PreToolUse` hook. Heredocs are fine for writing the body file itself (`cat > /tmp/body.md <<'EOF' ... EOF`).

## Math

- Use LaTeX notation rendered with GitHub's `` $`...`$ `` syntax for inline math and `$$...$$` for display math.
- Prefer `` $`...`$ `` over `$...$` for inline math.
- Plain text inside backticks is fine when the symbol must match a code identifier verbatim (e.g., `` `alpha_t` ``).
- Do NOT write raw Unicode math characters (α, β, ⊗, ∑, ∇, †, etc.) in prose. Use `` $`\alpha`$ ``, `` $`\otimes`$ ``, `` $`\sum`$ ``, `` $`\nabla`$ ``, `` $`\dagger`$ `` instead.
- Avoid `\_` in GitHub/LaTeX math. Use `` $`\mathrm{\textunderscore}`$ `` when an underscore glyph is required in math mode.
- Do NOT use `\textunderscore` inside `\text{...}` or `\texttt{...}`. Restructure the expression, or put the literal identifier in Markdown backticks outside math.
- When two inline math spans are separated by punctuation, put a space before the second math opener. Write `` $`K_1`$/ $`K_2`$ ``, not `` $`K_1`$/$`K_2`$ ``.

## References

- Do NOT cite local file paths, local notes, HPC cluster paths, or anything an external reader cannot open.
- If the substance of a local reference matters, inline its content (quote, paraphrase, or reproduce the relevant snippet).
- External references (arXiv, DOI, public repo URLs, public docs, other issues / PRs in the same or public repos) are fine.
- Cross-repo references to *private* repos are off-limits.

### Line numbers

- **Issue body — forbidden.** Inline a code snippet instead if a specific location matters.
- **PR body — permitted within this PR's own diff.** For a single specific line, prefer an inline review comment.

## Language

- Default to English for the title and body.
- Use Japanese only when the user explicitly asks for it, or when the surrounding repo's existing issues / PRs are predominantly Japanese.
- Do NOT inline Japanese clauses in an otherwise-English body. Re-cast in the chosen language.

## Length

- Be concise but do not omit explanation. Say what is needed and stop.
- Skip narrative scaffolding ("As we discussed...", "Following up on..."), restated context the reader can see from the repo, and exhaustive option enumeration when one option is clearly preferred.
- Every paragraph should be earning its place.

## Exclusions

The body must not contain any token whose referent cannot be resolved from the target repo's public state (README, public issues / PRs, public code, well-known external standards). `gh-body-check` enforces this.

Common leak shapes:

- Local filesystem paths (`/Users/...`, `~/...`, absolute paths).
- HPC cluster names, hostnames, queue names, or scheduler-specific context.
- References to the user's private repos, skills, or workflow internals (e.g., `/file-pullreq`, `research-and-implement`, `done-check`).
- Phase / step numbers from the working session ("Phase 2 of the umbrella", "Step 3 of the plan") unless the artifact is itself an umbrella sub-issue / sub-PR.
- "As we discussed" / "following up from chat" / other chat-tone scaffolding.
- Inline Japanese clauses in an otherwise-English body.
