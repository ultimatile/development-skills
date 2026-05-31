---
name: rust-ffi-rule
description: Rules for implementing a Rust safe wrapper around an external (C / Fortran / FFI) call. Read before writing unsafe FFI blocks, extern "C" declarations, or bindgen-based wrappers.
---
# Rust FFI Rule

## Procedure

1. **Triage the bare API.** Enumerate every input parameter and every output channel of the underlying call:

   - Inputs: every formal parameter (including in-out)
   - Outputs: the C return value, every `*mut` / in-out parameter the callee writes back, every status / info / error code

2. **Classify each** with the rubrics below.

3. **Present the non-default decisions to the user for approval before writing any Rust code.** Defaults (`expose` for inputs, `keep` for outputs) are silent — they preserve information and the caller's ability to vary inputs. Anything else (`derive`, `hardcode`, `fold`, `drop`) hides or fixes a value and requires explicit user approval with a stated reason. This is the gate that prevents implicit silent dropping / hardcoding.

   Format:

   ```
   FFI triage: <function name>

   Inputs (defaults expose):
   | Parameter | Proposal | Reason |
   |-----------|----------|--------|
   | iparam[3] | hardcode 1 | ARPACK only supports NB = 1; other values rejected |
   | nev       | hardcode 1 | scope: smallest-eigenpair entry point only |
   | lworkl    | derive    | = ncv * (ncv + 8) per ARPACK contract |

   Outputs (defaults keep):
   | Channel    | Proposal | Reason |
   |------------|----------|--------|
   | info < 0   | fold to AupdFailed(i32) | misuse / numerical failure |
   | info == 1  | fold to MaxIterReached  | distinct retryable case |
   | iparam[8]  | drop                    | <reason> |
   ```

   Items that follow the default need not be listed.

4. **Wait for user approval.** Do not implement the wrapper until the non-default decisions are confirmed.

5. **After approval, implement** with the agreed handling. Document each non-default decision inline at the assignment / extraction site so the rationale survives in code.

## Inputs rubric

- **expose** (default) → take as a parameter on the safe wrapper or a field of a tunable struct. Any value the caller might reasonably want to vary belongs here.
- **derive** → compute from other inputs (workspace lengths, etc.). Document the formula at the assignment site.
- **hardcode** → fix to a constant. Valid only when the value is a protocol invariant (the API rejects all other values) **or** a deliberately scoped feature subset (e.g. fixing `nev = 1` to ship a smallest-eigenpair-only entry point).

## Outputs rubric

- **keep** (default) → expose in the safe return type (struct field or tuple element).
- **fold** → map into a typed `Error` variant. One-to-one folds (each distinct status code gets its own variant) preserve information. Collapsing multiple distinct codes into one variant loses information and counts as a non-default for triage purposes.
- **drop** → silently discard. Valid only when the value is provably useless (constant, redundant with another exposed field, internal scratch).

## Unsafe boundary

Required at every FFI call site, independent of the input/output classification:

- **`SAFETY:` comment** at each `unsafe` block listing what makes the call sound — pointer validity, slice / buffer length, initialization state, aliasing, lifetime relative to the call.
- **Isolate raw extern declarations** in a private `sys` submodule. The public safe API must not expose raw pointers, `*mut T`, or bindgen-generated types directly.
- **Integer width conversions** use `try_into()` (mapped to `Error::InvalidParam` or similar), never `as`. Fortran `INTEGER` width depends on the LP64 vs ILP64 build of BLAS/LAPACK, and `usize → c_int` can overflow on 64-bit targets — `as` truncates silently.
- **Output buffer initialization.** Do not pass a `Vec::with_capacity` to the FFI as if it were initialized. Use `MaybeUninit<T>` (or a zero-initialized `Vec` if zeros are valid for `T`), call the FFI to populate it, verify the actual write count from the API's output channel, then `set_len` to that count. Partial-write and error paths must define what state the buffer is in.
- **Panic / unwind across the boundary.** Rust panics must not unwind into C — that is UB. Wrap any `extern "C"` callback the wrapper exposes in `std::panic::catch_unwind` and translate caught panics to an error code or sentinel before returning to C.

## Cross-cutting

6. **Stage-spanning semantics.** When the FFI is multi-stage (iterate-then-extract patterns where one call's status code determines whether a later call is even valid), the wrapper must read the upstream status before invoking the downstream stage and map it to the right error variant or early return. Never call the downstream stage on an upstream status the downstream cannot honor.

7. **Surface as a struct, not a tuple**, when more than two values are kept on either side. Tuples freeze the API; adding a later field becomes breaking.

## Common traps

08. **Thread safety.** First read the upstream's reentrancy / thread-safety contract. Many BLAS/LAPACK builds and handle-local C APIs are thread-safe and a process-wide lock would over-serialize them (performance loss, nested-call deadlock risk). Serialize through a single process-wide `Mutex` only when the contract says non-reentrant, the library has Fortran `SAVE` variables, or the contract is unclear. Hold the lock across the entire call sequence (not just one FFI call), and recover from poisoning via `unwrap_or_else(|p| p.into_inner())`. The failure mode for misclassified non-reentrant libraries shows up under `cargo test`'s parallel runner: tests pass solo, fail in parallel.

09. **In/out buffer aliasing.** When the API hands the wrapper offsets into a single buffer for both the read and the write side (reverse-communication, scratch-pool APIs), do not assume the offsets are disjoint. The upstream contract typically does not promise it, and aliased `&` / `&mut` through Rust's borrow rules is UB. Copy the read region into a scratch buffer first, then write through a separate, non-overlapping borrow.

10. **`repr(C)` layout-compat pointer cast.** When the bindgen-generated type and the canonical Rust crate type satisfy **all** of: (a) both `#[repr(C)]`, (b) identical fields in identical order with identical types, (c) crate-side documents stable layout (e.g. `num_complex` does for `Complex<T>`), (d) no invalid bit pattern constraints differ — own the storage as the canonical Rust type and cast the pointer at the FFI call site. Do not element-wise copy every call. Guard the assumption with `static_assertions::assert_eq_size!` / `assert_eq_align!` (or `const _:` size/align asserts) so a future upstream layout change breaks the build, not the runtime.

11. **Ownership and allocator boundary.** Memory crosses Rust ↔ C only through paired alloc/free: never free a C-allocated pointer with Rust's allocator (or the reverse), pair every foreign constructor with its foreign destructor, do not let C retain a Rust-owned buffer past the call (the caller's `Drop` invalidates it), and pin `user_data` lifetimes for callbacks (a pointer the C side stores must outlive every invocation it might drive).
