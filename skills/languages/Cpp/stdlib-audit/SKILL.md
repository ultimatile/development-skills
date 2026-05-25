---
name: stdlib-audit
description: Audit C++ source for known-bad standard library defaults (std::function, std::regex, std::list, std::map, std::unordered_map, std::async, std::vector<bool>, etc.) using a TSV-driven rule table that is extended by appending lines. Wraps a ripgrep-based shell script; reports per-rule hit counts and sample locations, exits non-zero on configurable severity (for CI). Targets C++17+ codebases.
---

# stdlib-audit

Static audit of C++ source for the catalogue of "do not use this, use that instead" standard library entries (the C++26-era walk-back catalogue plus the structurally-frozen container defaults). Rule table is data, not code — add a check by appending one TAB-separated line.

## Layout

```
stdlib-audit/
├── SKILL.md          this file
├── stdlib-audit.sh   executable; reads the TSV, runs ripgrep, formats output
└── stdlib-rules.tsv  extensible rule table (id / severity / regex / note)
```

## Running

```bash
# audit current directory (excludes external/** by default)
./stdlib-audit.sh

# audit a different project, with project-specific exclude
./stdlib-audit.sh -e '**/third_party/**' /path/to/project

# show more samples per rule, never exit non-zero
./stdlib-audit.sh -n 10 -f none .
```

| Flag | Meaning | Default |
|---|---|---|
| `-r FILE` | Rule TSV path | `stdlib-rules.tsv` next to script |
| `-e GLOB` | ripgrep exclude glob | `**/external/**` |
| `-n N` | Detail samples per rule | `5` |
| `-f LIST` | Severities that fail with exit 1, comma-separated, or `none` | `crit,high` |
| `-t TYPE` | ripgrep `--type` filter (limits search to one of rg's known types) | `cpp` |

Exit code is `0` (no failing hits), `1` (at least one rule in `-f` severity matched), or `2` (usage / missing dependency error, malformed rule regex, bad search path, or other ripgrep IO failure). Exit `2` always takes precedence over `1` so CI distinguishes "audit ran and found issues" from "audit could not complete".

The default exclude `**/external/**` matches any directory named `external` anywhere in the search tree. If the search root is itself named `external` (e.g. `./stdlib-audit.sh /tmp/external`), pass `-e '!'` (or another non-matching glob) to disable the default.

The default `-t cpp` restricts search to ripgrep's built-in C++ source list. As of this writing (`rg --type-list | grep '^cpp:'`) that covers `*.cpp`, `*.cc`, `*.cxx`, `*.hpp`, `*.hh`, `*.hxx`, `*.inl`, `*.h`, `*.C`, `*.H` (and `.in` variants). It does NOT cover pure-C sources (`*.c`) or CUDA (`*.cu`) — pass `-t all` or a custom rg type if you need them.

## Rule table format

`stdlib-rules.tsv` is TAB-separated, four columns:

```
id<TAB>severity<TAB>regex<TAB>note
```

- `id` — short label printed in the summary table (also used as the section header in details)
- `severity` — one of `crit | high | mid | low`
- `regex` — Rust-regex (ripgrep) pattern; supports `\b`, `\s`, alternation, groups
- `note` — one-line replacement / rationale; printed under the detail samples

Lines starting with `#` and blank lines are ignored. To add a new check, append one line. The script does not need editing.

## Severity scale

| Severity | Meaning | Examples |
|---|---|---|
| `crit` | Removed by current standard; any hit is a real bug | `std::auto_ptr`, `std::random_shuffle`, `gets()`, trigraphs |
| `high` | Active footgun with a documented better replacement | `std::function`, `std::regex`, `std::list`, `std::async` |
| `mid` | Structural smell; needs case-by-case judgement | `std::map`, `std::unordered_map`, `std::vector<bool>` |
| `low` | Acceptable in many cases but worth flagging | `std::deque`, `std::cout` / `std::cerr` / `std::clog` |

The default `-f crit,high` is appropriate for CI gating. Pin `mid` / `low` to advisory.

## Interpreting output

Summary table (one row per rule). Non-zero rules are then expanded into a detail block with up to `-n` sample `path:line:content` entries.

For each hit, decide:

1. **Is this in hot-path code?** If yes, treat `mid`-severity matches as `high`. If no (test, parser, one-shot init), the structural smell often does not need fixing.
2. **Does the project's C++ standard offer the documented replacement?**
   Examples: `std::move_only_function` only exists in C++23+; `std::format` only in C++20+. For C++17 projects, the realistic replacements are external libraries (Abseil / Boost / fmt / CTRE / RE2).
3. **Is the smell at an API boundary?** `std::vector<bool>` as a struct field is local; `std::vector<bool>&` as a function parameter leaks proxy semantics across translation units.

## C++17 replacement quick reference

| Rule | C++17-available replacement |
|---|---|
| `std::function` | template parameter; `tl::function_ref` (header-only, **non-owning** — only for function-parameter use, not for storage); `boost::function2` |
| `std::regex` | CTRE (header-only, compile-time pattern); RE2; Boost.Regex |
| `std::list` | `std::vector` (default); `std::deque`; `boost::intrusive::list` |
| `std::async` | thread pool (custom or `BS::thread_pool`); `std::thread` directly |
| `std::valarray` | Eigen; xtensor; Blaze |
| `std::vector<bool>` | `std::vector<std::uint8_t>`; `boost::dynamic_bitset` |
| `std::map` / `std::set` | `absl::btree_map`; `boost::container::flat_map` |
| `std::unordered_map` / `std::unordered_set` | `absl::flat_hash_map`; `boost::unordered_flat_map` (Boost 1.81+); `ankerl::unordered_dense` |
| `std::aligned_storage` | `alignas(T) std::byte[sizeof(T)]` |
| `std::iterator` base | define the five typedefs (`iterator_category`, `value_type`, `difference_type`, `pointer`, `reference`) directly |
| `std::cout` / `std::cerr` in hot code | `fmt::print`; gate diagnostic output behind a verbose flag |

## Tuning a project's rule set

Two common adjustments:

- **Demote a rule** the project has already triaged. Edit the severity column to `low`; matches remain visible but no longer fail CI under the default `-f`.
- **Restrict a rule's scope**. Replace the regex with a more specific pattern. Example: only flag `std::list` declarations, not the comment `// std::list`:
  ```
  std::list	high	^[^/]*\bstd::list\s*<	Almost always wrong; ...
  ```

To suppress one site without changing the rule, add an inline comment the regex won't match (e.g. wrap the type in a typedef in a separate header). The audit is line-level — it does not parse C++.

## CI integration sketch

```yaml
- name: C++ stdlib audit
  run: |
    ./skills/languages/Cpp/stdlib-audit/stdlib-audit.sh \
      -e '**/external/**' \
      src include
```

The default `-f crit,high` returns `1` on any matching hit, failing the job. Lower the bar by passing `-f crit` (only fail on removed-by-standard hits) or raise it by passing `-f crit,high,mid`.

## What this audit does not catch

- **Misuse of a non-flagged type.** `std::vector` used in a way that triggers reallocation in a hot loop is not in the table.
- **Semantic issues.** `std::map<int,int>` keyed by dense `0..n-1` should be a `std::vector<int>`. The audit flags the type, not the access pattern.
- **Implementation differences.** `std::deque` block size differs across libstdc++ / libc++ / MSVC STL; the audit is source-level only.
- **Generated code.** ripgrep only excludes paths matching the `-e` glob (default `**/external/**`) and whatever the user's `.gitignore` / `.ignore` files mark. A `build/` directory that is not gitignored will be searched. Pass `-e '{**/external/**,**/build/**}'` (or add `build/` to `.gitignore`) to exclude it.
- **Comments and string literals.** The audit is line-level regex; a comment such as `// std::function<void()>` or a string `"std::regex"` will match the same patterns as real code. Review the detail samples before treating a CI failure as authoritative; allowlist by tightening the rule regex or by demoting severity for the affected file class.

For semantic-level analysis, pair this audit with a code review pass focused on the call sites of the flagged types.
