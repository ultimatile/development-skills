# Language addenda for C++

This file extends `SKILL.md` with C++-specific triggers, mitigation idioms, and mechanical detection patterns. The audit (`done-check`) and preflight (`todo-check`) skills auto-load this file when the project declares `Language: cpp` in its `CLAUDE.md`, or when the diff touches `.cpp` / `.cc` / `.cxx` / `.h` / `.hpp` / `.hh` files.

This file does **not** introduce new audit items. Items live in `items/<slug>.md` and are language-neutral. Each section below corresponds to an existing item slug and provides the C++ realization: what to grep for, what conversion semantics apply, what idioms remediate the concern. When auditing, treat the language addendum as the concrete answer to "how does this generic item manifest in C++ specifically?"

---

## `signature-change-regression`

### Triggers (C++)

Implicit conversions in C++ are abundant and the failure mode of this item manifests in several distinct patterns:

- **Parameter type substitution where `T → U` is implicit.** Watch for these conversion edges:
  - Constructor-based conversions: `optional<X>(T)` accepts any `T` for which `X(T)` is constructible. The most common silent narrowing seen in practice: `optional<size_t>(double)` (because `size_t(double)` is allowed as a narrowing conversion, `1e-12` becomes `0`).
  - User-defined `operator U()` on `T`.
  - Standard arithmetic promotions / narrowings: `int ↔ bool`, `int ↔ enum`, `float ↔ double ↔ integer`, `T*` ↔ `bool`.
  - Pointer / array decay: `int[N]` → `int*`, function-to-pointer.
  - Aggregate / brace-init paths when the new parameter is an aggregate.
- **Parameter removal that compresses the positional list.** If `f(T, U)` becomes `f(U)` and `T` is implicitly convertible to `U`, old callers `f(t, u)` will not compile (arity mismatch) — *but* old callers `f(t)` (a different overload) might silently bind to the new `f(U)` with `T → U` conversion. The hazard is sharper when the removed parameter was at the end and had a default argument: `f(T, U = u_default)` → `f(U)` lets `f(t)` rebind silently.
- **Parameter reorder where adjacent parameters are mutually convertible.** `f(T, U)` → `f(U, T)` where both directions of `T ↔ U` are implicit. Old callers compile but with arguments swapped.
- **Default-argument repositioning.** When a parameter loses its default or is moved across other defaulted parameters, the *positional slot* shifts. Old callers using the previous slot may now bind to a different parameter with a compatible type.

### Mitigation idioms

- **`= delete;` overload with the old signature shape:**
  ```cpp
  // New API
  inline void f(Bar b);
  // Sentinel — fails to compile on any old call form with leading `Foo`
  void f(Foo /* removed parameter */, Bar) = delete;
  ```
  Use when the migration window is short and you want hard failure at every stale call site.

- **`[[deprecated]]` overload forwarding to the new form** during a phased migration window:
  ```cpp
  [[deprecated("Pass Bar directly; Foo argument removed")]]
  inline void f(Foo /* old */, Bar b) { f(b); }
  ```
  Use when downstream callers need a grace period (out-of-tree consumers, public library API).

- **Strong typedef / phantom-tagged newtype** over the affected parameters. Eliminates the implicit-conversion edge at the type system level — the audit becomes vacuous because `T → U` is no longer a valid conversion:
  ```cpp
  // Instead of: void f(double cutoff, double tolerance);
  struct Cutoff    { double v; explicit Cutoff(double x) : v(x) {} };
  struct Tolerance { double v; explicit Tolerance(double x) : v(x) {} };
  void f(Cutoff, Tolerance);
  // Old call `f(0.1, 0.2)` now fails to compile; caller must write
  // `f(Cutoff{0.1}, Tolerance{0.2})`, making the meaning explicit.
  ```
  Use when the parameter family is a domain concept that recurs throughout the project (SSOT candidates, units, ID classes).

- **Avoid default arguments on SSOT-required parameters.** Default arguments are the most common source of silent positional drift: when the slot moves or its type changes, the caller's defaulted-away argument silently rebinds. Requiring callers to write the argument explicitly (no default) makes the positional slot visible at every call site.

### Mechanical detection

Step-by-step:

1. **Detect signature changes in the diff.** Grep for changed function declarations:
   ```sh
   git diff <base>..HEAD -- '*.h' '*.hpp' '*.cpp' | rg '^[+-].*\binline\b|^[+-].*\)\s*[{;]' | rg -B1 -A1 '^[+-]'
   ```
   Or more reliably, eyeball each header-file hunk for parameter-list changes.

2. **For each changed signature**, capture old types `T₁, T₂, …` and new types `U₁, U₂, …`.

3. **For each removed / substituted parameter type `T_old` at position `k`**, ask: does there exist any `U_j` (in the new signature) reachable from the same syntactic position at the call site, such that `T_old → U_j` is implicit?
   - Construction edges: is `U_j` constructible from `T_old`? (`std::optional<X>(double)`, `std::string(const char*)`, etc.)
   - Conversion operators on `T_old`.
   - Standard arithmetic / pointer conversions.

4. **Compile-time validation (most reliable):** stash a copy of the old call form in a temporary `.cpp`, include the new header, and try to compile. If it compiles, the hazard is real. Tools like `clang -fsyntax-only -Wno-error=deprecated-declarations -Wconversion -Wnarrowing` flag many but not all such cases — manual review still required.

5. **Caller sweep:** `rg <function-name>\(` across the entire repository (including tests). For each match, mentally apply the new signature. Flag any call site that compiles under both old and new signatures with different semantics.

### Test surface (companion to mitigation)

When the project ships a *runtime* contract beyond the compile-time guard (e.g., the SSOT cutoff is supposed to propagate end-to-end), pair the mitigation with a runtime contract test under `behavior-coverage` — a fixture that varies the SSOT-controlled value at the upstream entry and asserts the downstream observable behavior changes accordingly. A compile-time sentinel catches one class (silent positional rebinding); a runtime contract test catches the orthogonal class (hard-coded constant downstream that ignores the propagated value).

### N/A elaboration

The base item's N/A clause requires either no public signature change OR exhaustive call-site re-verification. In C++ specifically, "exhaustive" is harder than it looks:

- Header-only libraries: all instantiations across the project are call sites, including tests.
- Templated callers: macro-expanded call sites that grep alone may miss; require an actual full-project rebuild as the verification.
- Conditional compilation (`#ifdef`): every preprocessor branch must be exercised. Grepping past `#if 0` blocks or platform-gated regions can hide stale call sites.

If any of these conditions hold and the call-site sweep was not exhaustive in *both* the lexical and the build-configuration dimensions, the item is **not** N/A; demand a sentinel overload or a strong type.
