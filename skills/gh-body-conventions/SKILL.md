---
name: gh-body-conventions
description: Single source of truth for GitHub issue / PR body conventions — semantic line breaks, LaTeX-safe math, reference / exclusion policies, language defaults. Drafting and audit skills apply these conventions by reference.
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

Write the body to a file (typically under `/tmp/`) and pass it to the `gh-post` wrapper via `--body-file`. Never pass the body inline to `gh` (`gh (issue|pr) (create|edit|comment) --body*`); route it through `gh-post`. Writing the body file itself with a heredoc (`cat > /tmp/body.md <<'EOF' ... EOF`) is fine.

## Math

- Use LaTeX notation rendered with GitHub's `` $`...`$ `` syntax for inline math, and a fenced code block whose info string is `math` for display math. Do NOT write display math as `$$...$$`.
- Prefer `` $`...`$ `` over `$...$` for inline math. Do NOT put backslash macros inside plain `$...$`.
- Do NOT wrap the inline-math construct `` $`...`$ `` in an enclosing code span. GitHub then renders the literal math syntax as inline code, not math — the failure mode when the *display* form of the construct (the literal syntax this section shows) is copied straight into a body.
- Plain text inside backticks is fine when the symbol must match a code identifier verbatim (e.g., `` `alpha_t` ``).
- Do NOT write raw Unicode math characters (α, β, ⊗, ∑, ∇, †, etc.) in text GitHub renders as neither code nor math. Use `` $`\alpha`$ ``, `` $`\otimes`$ ``, `` $`\sum`$ ``, `` $`\nabla`$ ``, `` $`\dagger`$ `` instead.
- Do NOT use `\operatorname` (or `\operatorname*`) in text GitHub renders as math. GitHub's math renderer does not render it. Use `\mathrm{...}` instead, or `\mathop{\mathrm{...}}` when operator spacing matters.
- Avoid `\_` in GitHub/LaTeX math. Use `` $`\mathrm{\textunderscore}`$ `` when an underscore glyph is required in math mode.
- Do NOT use `\textunderscore` inside `\text{...}` or `\texttt{...}`. Restructure the expression, or put the literal identifier in Markdown backticks outside math when exact code spelling matters.
- When two inline math spans are separated by punctuation, put a space before the second math opener. Write `` $`K_1`$/ $`K_2`$ ``, not `` $`K_1`$/$`K_2`$ ``.
- Keep the `` $`...`$ `` code-span delimiters balanced.

### After `gh-post`: suspect the source first

Broken math on GitHub after `gh-post` is author-side by default: check the source against the list above, and attribute it to `gh-post` only after reproducing the corruption on well-formed, balanced input.

## References

A citation is any token that designates text elsewhere — a link, a path, a path with a position in it, for instance.
Pin a citation to a fixed revision — a commit in a file URL or a version in a document URL, for instance — where what the sentence relies on can change under it: the text the citation designates, or its position within the artifact.
A reference to a whole artifact — an issue, a pull request, a comment, a review, a file, for instance — whose sentence relies only on the artifact's identity needs no pin.
Where the target admits no fixed revision, carry what the sentence relies on in the body, in whichever of § Exclusions' two forms the claim selects.

A citation of one or more lines of a file in the repository the body is filed in takes one form: a bare permalink — no link label, the full commit SHA in the URL — standing alone on its own line outside any sentence.
GitHub renders such a permalink as a snippet of the cited lines; those lines do not count as the body carrying a claim's substance, which the body carries in whichever of § Exclusions' two forms the claim selects.

For a single line inside a pull request's own diff, prefer an inline review comment on that line to a reference in the body.

## Language

- Default to English for the title and body.
- Use Japanese only when the user explicitly asks for it, or when the surrounding repo's existing issues / PRs are predominantly Japanese.
- Do NOT inline Japanese clauses in an otherwise-English body. Re-cast in the chosen language.

## Length

- Be concise but do not omit explanation. Say what is needed and stop.
- Skip narrative scaffolding ("As we discussed...", "Following up on...") and exhaustive option enumeration when one option is clearly preferred.

Artifact-specific length expectations live in the referencing skills (`file-issue`, `file-pullreq`).

## Exclusions

A **token** is any name, path, identifier, or reference the body contains.
An **external reader** is one who can open the target repo and nothing private beyond it.

The body must not contain a token whose referent an external reader cannot reach.
A repo-relative path the body itself proposes to create designates nothing yet, and this requirement does not reach it.
The body must also be followable: a reader who does not open the target repo can follow every sentence in it.
A token whose referent an external reader can reach, and whose sentence asserts only its identity or location, carries no substance requirement — an issue number or a repo-relative path, for instance.
A well-known external standard — an RFC or a language spec, for instance — is the one class of text the reader is assumed to hold, and a claim may rest on it as it stands.
A claim resting on what any other text *says* carries that substance itself, in the form that claim's own case selects; a sentence resting on two texts takes one form per claim, not one for the sentence:

- **State the predicate** — where the exact wording is not what is at issue. Say what the pointed-at text establishes; for a rule or a behavior, that is its trigger, its effect, and the outcome in the case at hand.
- **Quote it, frozen** — where the exact wording is what is at issue. Reproduce the wording inline, and cite the source where it is public. The reproduction is what makes the sentence followable; § References governs the citation.

Common shapes whose referents an external reader cannot reach:

- Local paths (`/Users/...`, `~/...`, absolute paths).
- HPC infra (cluster / host / queue / scheduler names).
- Private repos, skills, or workflow internals — private *relative to the target repo*. A body filed into the repo that holds them may name them plainly; a body filed anywhere else reaches them only through a public reference, never through a bare name.
- Working-session phase / step numbers ("Phase 2 of the umbrella", "Step 3 of the plan") — unless the artifact is itself a public umbrella sub-issue / sub-PR.
- Placeholders left where a value belongs (`<TODO>`, `<owner>`).

## Evidence claims

An evidence claim is a statement in the body whose truth rests on something other than the body — what a text says, what the code does, the state of an issue or pull request, what an execution did or produced, for instance.
It is discharged in main context by whoever drafts the body, before the body is shown or filed: for each claim, the author identifies what the claim rests on, its source, and checks the claim against an observation of that source.
A statement of what only running something could show — a suite passing, a coverage figure, a timing — rests on an execution, however phrased.

- An observation of a source is one of these, made by the author in the session performing the discharge and outside any stretch since summarized: reading the source, a command's output, an agent's return, or reading something durable that holds the source itself — a committed fixture, a linked run.
  Nothing seen before its source last changed is an observation of it, and the output of an execution that ran before anything it ran on last changed is not one either.
  Recall, a summary of the session, a handoff note, and the body's own earlier wording are not observations.
- A claim the observed source bears out passes the check: a stated predicate holds of the source, and a quotation reproduces its wording.
- A claim the observed source does not bear out is corrected against the source or dropped.
- A claim whose source the author has not observed is checked after observing it — reading the text, re-running the command. Where the author cannot observe it, the author asks the user for the source itself or drops the claim.
- A claim is not softened into a hedge in place of any of these outcomes.
- A claim observed through an agent's return maps to one result in one return; the author checks that mapping.
  A statement asserting several runs is that many claims, one per run, and a return reporting several results is that many observations, one per result.
  Matching totals are not sufficient: a fabricated entry and an omitted one cancel, so the mapping is checked entry by entry rather than by count.
  Within an enumeration of runs, no two entries map to the same result; describing one run in two places is not double-counting — claiming it as two entries is.
- An enumeration need not be complete — work performed but not written up states nothing false.
  An enumeration that claims completeness ("all runs performed", "the only cases exercised") does require every member of the scope it claims to appear; work that verifies the body itself is outside any such scope.
- A claim that cannot be stated without naming something § Exclusions forbids is dropped, or restated against something nameable.
- Body text edited after its claims were discharged is discharged again before it is shown or filed.
  Each discharge after the body's first, of the whole body or of any part of it, checks every evidence claim anywhere in the body again.
