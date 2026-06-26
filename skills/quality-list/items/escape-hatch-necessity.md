# Escape-hatch necessity

A construct that bypasses the language's static guarantees — Rust `unsafe`, C++ `reinterpret_cast` / `const_cast` / C-style cast, TypeScript `any` / `as` / non-null `!` / `@ts-ignore` — is not self-justifying. Its **necessity** must be derived before it is accepted: show that no safe construct expresses the same thing. A justification comment (Rust `// SAFETY:`, a cast rationale) argues the bypass is *sound*; it does not argue it is *necessary*. Soundness and necessity are separate obligations, and the comment discharges only the first.

The recurring failure is a framing error. A problem solvable by placing behavior where the type system already knows the concrete type (trait / interface dispatch, generics, an enum) gets reframed as a *conversion* problem and solved by reinterpreting one type as another through the escape hatch. The hatch compiles and a sound-looking justification can be written, so it reads as "solved" locally — but the safe construct would have removed the problem setting entirely, justification and all.

Trigger when a diff introduces an escape hatch whose justification is only "bridge a generic / erased type to a concrete one," not an irreducible external boundary. Ask: can a safe construct make the type concrete at the use site instead? If yes, the hatch is unnecessary, not merely sound — and "sound but unnecessary" is the defect.

**Concern conditions:**

- Diff adds an escape hatch to convert between types a safe construct (trait dispatch, generics, enum) could keep concrete at the use site
- The accompanying justification establishes soundness but never establishes that the safe construct cannot express the operation

**N/A:** the bypass sits at an irreducible boundary where no safe construct can express the operation — FFI / `extern` call, raw allocation, hardware MMIO, a layout-compat pointer cast guarded by static size / align assertions. There, necessity is self-evident and only soundness remains to argue.
