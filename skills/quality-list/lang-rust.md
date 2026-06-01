# Language addenda for Rust

This file extends `SKILL.md` with Rust-specific triggers, mitigation idioms, and mechanical detection patterns. The audit (`done-check`) and preflight (`todo-check`) skills auto-load this file when the project declares `Language: rust` in its `CLAUDE.md`, or when the diff touches `.rs` files.

This file does **not** introduce new audit items. Items live in `items/<slug>.md` and are language-neutral. Each section below corresponds to an existing item slug and provides the Rust realization: what to grep for, what semantics apply, what idioms remediate the concern. When auditing, treat the language addendum as the concrete answer to "how does this generic item manifest in Rust specifically?"

______________________________________________________________________

## `paired-artifact-drift`

### Triggers (Rust)

A doc comment has a *rendered* surface (rustdoc / docs.rs) distinct from its source text, and a token that is meaningful in code position can be inert in doc-text position. The recurring Rust instance:

- **Macro metavariable leaked into doc-comment text.** A `///` or `//!` line containing a `$name` token (`$ty`, `$float`, `$T`, `$fn`, …). A doc comment desugars to `#[doc = "…"]` — a string literal — and `macro_rules!` transcription does not interpolate into string literals. So `$name` in doc text renders **literally** in rustdoc, whether the comment sits inside a macro body or on a standalone item near one. The author, thinking in the macro's mental model, reads "the type parameter"; the docs.rs reader sees `$ty`.

  Verified empirically: `/// Returns a value of type $ty` inside a `macro_rules!` renders `$ty` literally in the generated HTML, even though the same `$ty` in the adjacent return-type position substitutes to the concrete type. The substitution boundary is "token position vs string-literal position", not "inside vs outside the macro".

  Most common origin: writing helper-fn or wrapper docs that *describe* a sibling macro's parameterization in the macro's own vocabulary instead of in concrete terms.

### Mitigation idiom

Describe the concrete behavior, not the metavariable. For a tol-narrowing helper, write "the f64 path is the identity, the f32 path does the real `as f32` narrowing" rather than "narrows `options.tol as $ty`". If a generated item genuinely needs a per-instantiation doc value, use `#[doc = concat!(…)]` or the `paste` / `doc-comment` crates — never rely on `$name` interpolating inside `///`.

### Mechanical detection

```sh
git diff <base>..HEAD -- '*.rs' | rg '^\+\s*//[/!].*\$[A-Za-z_]'
```

Or sweep the working tree:

```sh
rg -n '^\s*//[/!].*\$[A-Za-z_]' -g '*.rs'
```

### False-positive review

One legitimate case: a doc comment that *documents macro syntax* — it mentions `$name` as the name of a parameter the caller supplies (typically the `macro_rules!`'s own doc, e.g. "pass `$ty` as the element type"). There the literal `$name` is intentional prose about the token → ⊘ dismiss. Every other hit, where `$name` stands in for a concrete value or type the doc is trying to *describe*, renders literally and reads as a defect → ⚠ reword to the concrete term.

Advisory only — do **not** hard-fail at commit time. The legitimate macro-syntax-doc case means each hit needs human triage, not a blocking gate.

### N/A elaboration

N/A when the diff adds no `///` / `//!` lines, or when every doc-comment `$name` hit is a deliberate description of macro syntax (the dismiss case above).
