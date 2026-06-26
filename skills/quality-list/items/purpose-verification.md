# Purpose verification

The change must accomplish its stated purpose, not just compile and pass existing tests. Exercise the new behavior end-to-end against an input that exposes the purpose.

**Executable configuration artifacts.** Task-runner targets (cargo-make / make / just), package scripts, CI step commands, and wrapper shell scripts are behavior, not inert text. A diff that touches only such artifacts — with no source-code change — is therefore in scope for this item; a "config / docs-only" label does not make it N/A. When the artifact carries an adjacent comment or doc claiming a specific effect ("scopes mutation to the fallback path", "lints only the library", "runs the integration suite"), exercise the command's actual effect and compare it against that claim. Validating that the command's flags parse is not the same check — a well-formed command can still produce an effect its comment misdescribes. When a full run is expensive, a read-only / dry-run / list mode is the cheap exercise (`cargo mutants --list`, `make -n`, and the like).

**N/A:** strictly mechanical changes (rename, file move, formatting).
