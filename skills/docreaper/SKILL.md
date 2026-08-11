---
name: docreaper
description: Audit code comments and docstrings for prose the code they annotate already carries, taking a delete-or-keep verdict per comment block and applying only what the user approves. Optional scope argument (file path, directory, or module); without arguments, audits every tracked source file of the workspace.
---

# docreaper

Audit comments and docstrings for prose their own referent already carries.
Report every verdict, including every block kept.

## Step 1 — Determine scope

- **With argument**: audit only the specified file, directory, or module.
- **Without argument**: audit every tracked source file of the workspace.

The pass covers the extent the bullet above selected, whichever of the two fired.
A file in a language whose comment syntax you cannot read is part of that extent and is one the pass does not reach.
Whether to run again on any part of that extent Step 5 reports as unreached is the user's call.

## Step 2 — Read the blocks and name each block's referent

A **comment block** is one docstring, one run of adjacent comment lines with no code line between its members, or one comment trailing a code line.
One docstring is one block however many blank or empty lines it holds.
For a run of comment lines, a line of code ends the block, and so does a wholly empty line, being neither comment nor code.
The block is the unit the delete-or-keep verdict is taken on, so no sentence or clause boundary decides whether text is removed.
The classes still name things inside a block — the propositions it asserts, an expression whose antecedent is missing — and a report entry quotes the span it names.

A file's leading interpreter or encoding line — `#!/usr/bin/env bash`, a coding pragma — is not a comment line for this purpose and is no member of any block.

A **proposition** is anything the block states that can be true or false.

The referent is the code the block's reader has in front of them.
Take the first row that matches:

| the block | referent |
| -- | -- |
| sits at the top of a file, above every construct in it, and is not in a doc form the language binds to a following item | the file's code |
| documents a named construct — either a doc-form comment, or a block with no blank or empty line between it and the declaration below | that construct's declaration as written. A block documenting a construct is read by whoever reads the declaration, whether or not anything calls it yet, so the construct's body is not part of the referent |
| sits inside a body, including between two constructs or trailing on a code line | the innermost enclosing body's code |

A **body** is the code a construct's braces, indentation block, or file scope encloses, and a language construct that opens its own scope — an `unsafe` block, an `if` branch, a `with` or `try` block, a closure — is one too.
Where several enclose the block, the innermost governs.
A file's top level is a body, so a block among a script's top-level statements takes the third row, and every block that is neither a file header nor a construct's documentation lands there.

A doc form the language binds to one particular construct rather than to the file — Rust `///` binding to what follows, a Python docstring binding to the `def` it opens, a Doxygen or JSDoc block — takes the second row even at the top of a file; the first row is for the form that documents the file itself, such as Rust `//!` or a bare leading comment run.
The referent Step 5 records is what makes the first-row choice checkable.
The second row binds by adjacency, not by topic: a block that reaches it takes that declaration even when its prose is about code further down, and the referent Step 5 records is what the row named rather than what the block is about.

A construct's **declaration** is everything the language writes for it before its body opens, across however many lines that spans.
That takes in its name, its parameters and their types, and whatever else sits there: attributes, decorators, specifiers, qualifiers, exception clauses, constraints.
Where declaration and body share a line, the declaration is the part before the body opens.
Where the construct opens no body at all — a field, a constant, a variable, a local binding, a type alias — the declaration runs to its own terminator, and its type and its initializer are part of it.
A construct for which the language writes nothing before a body has no declaration, so a block above it documents no declaration and takes its referent from whichever later row its position matches.

A **named construct** is whatever the language names and another line can refer to.
Functions, methods, types, fields, constants, macros, aliases, local bindings and modules are instances of that predicate rather than a closed list, so a construct the list omits is still a named construct when another line can refer to it by name.
The rows do not turn on visibility, so no reading of "exported" changes the referent.

**Referent text** is the code the row named, minus every comment block that code holds — a docstring as much as a comment line, and one Step 2 placed out of scope as much as one it judges.
Everything else the row named counts, string and character literals included: an attribute's message, an assertion's label, a help string.
No block therefore carries another block for class A's purposes; what two blocks share is class B's concern.
A declaration in a language that writes only a name — a shell function's `name()` — carries almost nothing, so class A rarely fires on such a referent, and that is the language's property rather than a gap to compensate for.

Not in scope.
An exclusion takes the whole file when it names a file, the whole block when it names the whole block, and otherwise takes the span it names; the rest of the block stays in scope and is judged on what remains.

- A block that is only a banner separator, a `shellcheck` / `noqa` / `clippy` directive, or a license header: carries no claim about the referent. Where such a line sits inside a longer block, it is the named span and the block's prose stays in scope.
- Commented-out code, a code example inside a comment, and the data columns of an aligned table inside a comment: code or data, not prose. Each is a named span.
  An exclusion never takes prose that asserts a proposition: where a table row or a directive line carries a gloss beside its data, the gloss stays in scope and only the data is excluded.
- A file a generator writes: regenerated rather than edited.
- A file whose own prose is what an agent executes: there is no code beside it for a referent row to name. A script's comments describe the code beside them and stay in scope.
- `README.md`, other top-level `*.md`, `docs/**`: written for a repository's visitors rather than for a reader of the code beside it.
- An article, a paper manuscript, prose whose subject is not an artifact in the repository: the referent is outside the repository.

## Step 3 — Run each class

Class A takes the delete-or-keep verdict Step 2 named the unit of.
Classes B and C are observations the block's own report row carries, so a block in class A is still reported as a class B site or a class C description when it qualifies.

### Class A — the referent's own text carries the whole block

Two conditions, both required:

1. The block asserts **at least one** proposition.
2. Every proposition it asserts is one the referent's own text asserts.

A block asserting nothing is not in this class. Delete nothing on the strength of an empty condition — a banner, a stray fragment, or a block whose prose the exclusions above took away has nothing to compare and stays as it is.

The predicate is about text on both sides: what the block asserts, against what the referent asserts.
A **condition**, a **consequence**, a **reason**, a **distinction** and a **property** are what a referent's text usually leaves to the block; they illustrate where condition 2 tends to fail rather than decide it, so a block asserting something none of the five names can still fail condition 2, and a block asserting one of the five is in this class when the referent's text states that one too.
One proposition the referent's text does not assert, anywhere in the block, keeps the whole block, because the block is the unit.

The test is the kind of content, not the strength of an entailment.
Whether a reader could formally deduce the block from the referent is not asked, so no standard of derivation is imported.
A block in the imperative mood asserts what the construct does — `// Write a body string to a temp file and echo its path.` asserts the write and the echo — so mood is not what decides condition 1.

A block the referent **contradicts** is kept, with the argument that the referent does not carry it; correcting it is not this sweep's business.
Under the second row the construct's body is not the referent, so a contradiction visible only in the body is not this sweep's finding either.

The delete-or-keep verdict covers the block's in-scope text only, so a directive or an example the exclusions took away survives a deleted block.

Deletable shapes: `// Increment the counter by one.` inside a body whose only statement is `COUNTER.fetch_add(1, Ordering::Relaxed)`; a docstring restating a `#[deprecated]` attribute's own message; a field comment restating the field's own type.

Kept shapes, one per illustrated kind: `/// # Panics if center >= chain.len()` asserts a condition and its consequence; `// SAFETY: the pointer is valid because the caller holds the borrow.` asserts a reason; `// The wrapped construct renders as literal code, so the math silently fails.` asserts a consequence the referent does not show; `// p is a patch counter, not the day.` asserts a distinction; `/// The sort is stable.` asserts a property.

### Class B — another block in the same file states the same proposition

Two or more in-scope blocks in one file state one proposition.
Spans Step 2 placed out of scope are not compared, so a license header or a directive cannot put an in-scope block in this class.

This class looks inside one file only.

Choose no survivor: which copy a reader needs is the user's call, and the sweep is not given who will read what.

### Class C — an antecedent neither the block nor its referent supplies

A history-dependent expression — a definite description, or a modifier such as `pre-fix` — whose antecedent is a change, a review round, or a prior state of the code, and which a reader cannot recover from the block or from the block's referent.
Describing the prior state counts as recovering it: `the regex before the wildcard case was added, which matched literals only` says what that state was, so it is not in this class, while a bare `pre-fix` is.
The file's own history is not a recovery source: under squash merge a phrase such as "this change" has no antecedent there, so recovery has to come from the block or the referent.
An ordinary expression naming something in the domain — "the buffer", "the day" — is not in this class however its antecedent resolves; what puts an expression here is that recovering it needs the project's change history.

The two repairs available are naming the antecedent and cutting the phrase; which one applies is the user's call.

## Step 4 — Confirm before entering a class

Treat every candidate as unconfirmed until read: read the block and its whole referent before entering it in any class.
These shapes look like a class and are not:

- A negation blocking a default inference — "`p` is a patch counter, not the day", "a definition file, not a procedure".
  The negation is what stops the reader's default reading.
- A silent failure mode.
  Nothing in the referent shows what does not happen.
- A `SAFETY`, `Panics`, or invariant claim the referent does not encode.
- A label naming what a token closes — `#endif // GUARD_NAME`, `} // namespace slate`.
  The block asserts which construct this token closes, and the line that opens the construct names the construct rather than its closer.
- Two blocks sharing a template but not a proposition.
  Class B needs the same proposition, not the same phrasing.
- A description that looks like the construct's name spelled out but asserts something beyond the referent.
  `/// Returns the number of items, or zero when the buffer was drained.` asserts a condition, so it is kept though its opening clause reads as a restatement.

## Step 5 — Report

Report every in-scope block the pass reached, with:

- its `file:line`, the Step 2 row taken and the code that row named;
- its delete-or-keep verdict, and when that is delete, the part of the referent that carries it;
- when that is keep, the argument for it: which proposition the referent does not carry, or that the block asserts none;
- every class B set the block has a site in, with every site in the set;
- every class C expression in the block, with its two repairs.

Report alongside those rows, not inside them:

- every file, block and span Step 2 placed out of scope — the file by path, the block and the span quoted — with the exclusion that applies to it;
- any block the referent contradicts, with what contradicts it, so a kept block that is false is distinguishable in the report from a kept block that is true;
- the extent covered, and any extent the pass did not reach.

Apply nothing without the user's approval, taken per block.
