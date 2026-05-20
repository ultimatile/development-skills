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
- **Do NOT break below the clause level.** A line break must land on a sentence boundary, an independent clause boundary, or a coordinated-clause boundary (`and` / `or` / `but` that joins full clauses, not phrases). Never break inside a clause. Specifically forbidden break positions:
  - Between subject and verb (`parse_pr_url in foo.sh \n assumes single-line input.`).
  - After a preposition or a preposition + object fragment (`emitted via ... \n followed by ...`, `the summary block with \n Title: / State: / ...`).
  - Inside a noun phrase or after a determiner / adjective stranding its head noun.
  - After a comma that separates list items, appositives, or modifiers *within* one clause (as opposed to a comma between independent clauses, which is a valid break).
  - Before a coordinating conjunction (`and` / `or` / `but`) when it joins phrases rather than clauses.
- The failure shape this rule blocks: "many short fragments, several of them clearly sub-clause" — i.e. clause-per-line over-applied until lines end on `with`, `by`, `of`, the subject NP, or a list comma. The visual rhythm of such a paragraph is harder to read than column-wrapped prose, not easier; it is a failure mode, not a style. When in doubt, prefer flat prose (the third option above) over over-fragmented "clauses".

## Authoring via file

Write the body to a file (typically under `/tmp/`) and pass it to the `gh-post` wrapper via `--body-file`. The wrapper validates the body and forwards to `gh` with `--body-file`, eliminating shell-escape concerns entirely. Direct `gh (issue|pr) (create|edit|comment) --body*` is blocked by the companion `PreToolUse` hook, so no heredoc-direct-to-API path exists; heredocs are still fine for writing the body file itself (`cat > /tmp/body.md <<'EOF' ... EOF`), since the file-write step is not a GitHub API boundary.

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
- References to the user's private repos, skills, or workflow internals (e.g., `/file-pullreq`, `research-and-implement`, `done-check`). These are author-side tools, not reader-facing artifacts; the public body must justify itself from the repo's own state.
- Phase / step numbers from the working session ("Phase 2 of the umbrella", "Step 3 of the plan") unless the artifact is *itself* an umbrella sub-issue / sub-PR where that structure is public.
- "As we discussed" / "following up from chat" / other chat-tone scaffolding that resolves only via the private context.
- Inline Japanese clauses in an otherwise-English body (see Language).

Before filing, perform the cold re-read across References / Tone / Language / Structure / Trigger-flag (CLAUDE.md axes). The list above covers the patterns the cold re-read most often catches; novel leak shapes still require the cold re-read.
