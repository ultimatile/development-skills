---
name: gh-body-conventions
description: Single source of truth for GitHub issue / PR body conventions — semantic line breaks, LaTeX-safe math, reference / exclusion policies, language defaults. Definition file, not a procedure.
---

# GitHub Body Conventions (SSOT)

This skill is **a definition file, not a runnable procedure**. Skills that draft GitHub issue / PR body content apply these conventions by reference. Do not copy these rules into them — point at them by name.

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

Write the body to a file (typically under `/tmp/`) and pass it to the `gh-post` wrapper via `--body-file`. Never pass the body inline to `gh` (`gh (issue|pr) (create|edit|comment) --body*`); route it through `gh-post`. Writing the body file itself with a heredoc (`cat > /tmp/body.md <<'EOF' ... EOF`) is fine.

## Math

- Use LaTeX notation rendered with GitHub's `` $`...`$ `` syntax for inline math and `$$...$$` for display math.
- Prefer `` $`...`$ `` over `$...$` for inline math.
- Do NOT wrap the inline-math construct `` $`...`$ `` in an enclosing code span. GitHub then renders the literal math syntax as inline code, not math — the failure mode when the *display* form of the construct (the literal syntax this section shows) is copied straight into a body.
- Plain text inside backticks is fine when the symbol must match a code identifier verbatim (e.g., `` `alpha_t` ``).
- Do NOT write raw Unicode math characters (α, β, ⊗, ∑, ∇, †, etc.) in prose. Use `` $`\alpha`$ ``, `` $`\otimes`$ ``, `` $`\sum`$ ``, `` $`\nabla`$ ``, `` $`\dagger`$ `` instead.
- Do NOT use `\operatorname` (or `\operatorname*`). GitHub's math renderer does not render it, regardless of inline/display or `` $`...`$ `` vs `$...$` delimiter form — a GitHub-specific limitation, not a MathJax one (github/markup#1688). Use `\mathrm{...}` instead, or `\mathop{\mathrm{...}}` when operator spacing matters.
- Avoid `\_` in GitHub/LaTeX math. Use `` $`\mathrm{\textunderscore}`$ `` when an underscore glyph is required in math mode.
- Do NOT use `\textunderscore` inside `\text{...}` or `\texttt{...}`. Restructure the expression, or put the literal identifier in Markdown backticks outside math when exact code spelling matters.
- When two inline math spans are separated by punctuation, put a space before the second math opener. Write `` $`K_1`$/ $`K_2`$ ``, not `` $`K_1`$/$`K_2`$ ``.
- Keep the `` $`...`$ `` code-span delimiters balanced — an unbalanced backtick makes `gh-post`'s auto-format (mdformat) escape the surrounding text as literal prose (doubling backslashes, escaping `*`), which corrupts the rendered output.

### After `gh-post`: suspect the source first

Broken math on GitHub after `gh-post` is author-side by default — attribute it to `gh-post` only after reproducing the corruption on well-formed, balanced input.
Two distinct failure surfaces:

- mdformat mangles the *source* — an unbalanced `` $`...`$ `` delimiter, or plain `$...$` with backslash macros.
- GitHub won't render otherwise-intact source — `\operatorname` (GitHub renders nothing), raw Unicode glyphs (shown as literal text, not math); mdformat leaves these untouched.

## References

Citations must point to something an external reader can open.

- Do NOT cite local file paths, local notes, HPC cluster paths, or private-repo paths.
- If the substance of a local reference matters, inline its content (quote, paraphrase, or reproduce the relevant snippet) so the body is self-contained.
- External references (arXiv, DOI, public repo URLs, public docs, other issues / PRs in the same or public repos) are fine.

### Line numbers

Line-number citations are governed by whether the surrounding artifact anchors them to a stable commit:

- **Issue body — forbidden.** Inline a code snippet instead if a specific location matters.
- **PR body — permitted within this PR's own diff.** For a single specific line, prefer an inline review comment.

## Language

- Default to English for the title and body.
- Use Japanese only when the user explicitly asks for it, or when the surrounding repo's existing issues / PRs are predominantly Japanese.
- Do NOT inline Japanese clauses in an otherwise-English body. Re-cast in the chosen language.

## Length

- Be concise but do not omit explanation. Say what is needed and stop.
- Skip narrative scaffolding ("As we discussed...", "Following up on..."), restated context the reader can see from the repo, and exhaustive option enumeration when one option is clearly preferred.

Artifact-specific length expectations live in the referencing skills (`file-issue`, `file-pullreq`).

## Exclusions

The body must not contain any token whose referent cannot be resolved from the target repo's public state (README, public issues / PRs, public code, well-known external standards). `gh-body-check` enforces this via a cold-reader subagent with no access to chat history, private notes, or workflow internals — whatever the cold reader cannot resolve is, by definition, leakage.

Common leak shapes — each fails the cold-reader test:

- Local paths (`/Users/...`, `~/...`, absolute paths).
- HPC infra (cluster / host / queue / scheduler names).
- Private repos, skills, or workflow internals (e.g. `/file-pullreq`, `research-and-implement`, `done-check`).
- Working-session phase / step numbers ("Phase 2 of the umbrella", "Step 3 of the plan") — unless the artifact is itself a public umbrella sub-issue / sub-PR.
- Chat-tone scaffolding ("As we discussed", "Following up from chat", etc.).
- Inline Japanese clauses in an otherwise-English body.

## Evidence claims

A statement that verification was performed — a command run, a suite executed, a measurement taken, a probe or agent run carried out — is admissible only if a record of that execution is available to the author at drafting time.
This is a relation between the text and the drafting session rather than a property of the text, so a cold reader cannot see it and it is discharged in main context by whoever drafts the text.

A record is available when the author observed the execution's result and can still point at it: a command's output, an agent's return, or something durable that holds the result itself — a committed fixture, a linked run.
Work done in another session, or in a stretch of this one since summarized, leaves no such record unless something durable holds it; a summary or a handoff note describing that work is not a record of it.

- A command-backed claim names the command and its observed result in the body.
  An agent-backed claim maps to exactly one return; the author checks that mapping, and the body need not name the run.
  A statement asserting several runs is that many claims, one per run.
  Matching totals are not sufficient: a fabricated entry and an omitted one cancel, so the mapping is checked entry by entry rather than by count.
  Within an enumeration of runs, no two entries map to the same record; describing one run in two places is not double-counting — claiming it as two entries is.
- A claim that cannot be stated without naming something § Exclusions forbids is dropped, or restated against something nameable.
- An enumeration need not be complete — work performed but not written up states nothing false.
  An enumeration that claims completeness ("all runs performed", "the only cases exercised") does require every record within the scope it claims to appear; work that verifies the body itself is outside any such scope.
  Later work can falsify a completeness claim without its own text changing, so it is re-checked whenever the body is discharged again.
- A claim with no available record is re-run or dropped.
  It is not softened into a hedge.
- Text edited after its claims were discharged is discharged again before it is shown or filed.
  Revise-and-re-run loops are the usual source: a revision made to clear another check can introduce a claim that check does not read.

A statement is an evidence claim if it asserts an execution or reports an observation, or if the property it states could only be known by running something — a suite passing, a coverage figure, a timing — however phrased.
A statement of an artifact's existence, or of a property establishable by reading the code (a test file added, a tolerance value, an identifier, which cases a test covers), is not one; it is checked against the code, not against a record, even where something was also run to confirm it. Reporting that run is a separate statement, and that one is an evidence claim.
