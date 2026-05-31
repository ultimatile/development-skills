# development-skills

End-to-end development workflow skills for Claude Code — from a GitHub issue to a merged PR.

## Skills

### Issue → Plan → Code

| Skill | Description |
| -- | -- |
| `research` | Hypothesis-driven investigation under the four-state decision discipline (confirmed / rejected / inconclusive / deferred). Classifies hypotheses as empirical (subagent-verified) vs derivational (deduced in main context); posts the resulting plan to the issue body (umbrella-spawned sub-issue) or comment (single-scope issue). Depends on [haru0416-dev/agent-skills](https://github.com/haru0416-dev/agent-skills) (`evidence-gated-review`) |
| `research-quaere` | Quaere-based variant of `research`. Same workflow with the internal subagent contract delegated to `quaere-evidence`. Depends on [haru0416-dev/quaere](https://github.com/haru0416-dev/quaere) (`quaere-evidence`, `quaere-semantic`) |
| `codex-plan-review` | Review the implementation plan with Codex against the actual codebase before coding |
| `implement` | Execute a plan via the execution-loop discipline (Read → Plan → Execute → Review → Fix → Verify) with drift surfacing and done-check before completion. Reads the plan from the sub-issue body (umbrella-spawned) or comments (single-scope). Depends on [haru0416-dev/agent-skills](https://github.com/haru0416-dev/agent-skills) (`execution-loop`) |
| `implement-quaere` | Quaere-based variant of `implement`. Same workflow with the inner loop delegated to `quaere-execution` (Plan → Do → Study → Act). Depends on [haru0416-dev/quaere](https://github.com/haru0416-dev/quaere) (`quaere-execution`) |
| `research-and-implement` | End-to-end wrapper that runs `research` (Phase 1) then `implement` (Phase 2), with a branch baseline gate up front. Depends on [haru0416-dev/agent-skills](https://github.com/haru0416-dev/agent-skills) (`evidence-gated-review` + `execution-loop`) |
| `research-and-implement-quaere` | Quaere-based variant of `research-and-implement`. Sequences `research-quaere` then `implement-quaere`. Depends on [haru0416-dev/quaere](https://github.com/haru0416-dev/quaere) (`quaere-evidence` + `quaere-execution`) |

### Issue & PR drafting

| Skill | Description |
| -- | -- |
| `file-issue` | Draft and file a GitHub issue following formatting conventions (semantic line breaks, LaTeX math, no local references). Includes an umbrella sub-issue variant (Parent: linkage, Goal/Scope/Out of scope/Acceptance shape) used by `research` when spawning sub-issues from an umbrella |
| `file-adr` | Draft an Architecture Decision Record (a timeless decision, distinct from an implementation schedule) and write the file under the project's ADR directory. Enforces classification against `file-issue` and a frozen-after-Acceptance discipline |
| `file-pullreq` | Draft and file a GitHub PR following the PR body skeleton, routed through the `gh-post` wrapper. Supports a gate mode that stops at user approval before posting |
| `gh-body-conventions` | Single source of truth for GitHub issue / PR body conventions — semantic line breaks, LaTeX-safe math, reference / exclusion policies, language defaults. Definition file referenced by the drafting and check skills, not a procedure |
| `gh-body-check` | Audit a drafted or filed GitHub issue / PR body against `gh-body-conventions` via a fresh-context subagent; any unresolved ⚠ blocks the caller |

### Documentation

| Skill | Description |
| -- | -- |
| `file-pubdoc` | Draft `README.md` or visitor-facing markdown (top-level `*.md`, `docs/**/*.md`) from the canonical skeleton, complementing the public-doc-durability audit |

### Code → Review → Ship

| Skill | Description |
| -- | -- |
| `stage-commit-push` | Stage, generate conventional commit message, commit, and push |
| `codex-review` | Run OpenAI Codex review with triage before PR creation |
| `copilot-review` | Create PR with GitHub Copilot review, poll for results, triage |
| `review-pipeline` | Orchestrator — runs the full flow from local changes to reviewed PR |

### End-to-end composite

| Skill | Description |
| -- | -- |
| `reimre` | Full end-to-end wrapper — runs `research-and-implement` then `review-pipeline` back to back, with an automatic seam rule that skips the duplicate `done-check` at the boundary. Stops at the user-controlled merge gate inherited from `review-pipeline`. |
| `reimre-quaere` | Quaere-based variant of `reimre`. Runs `research-and-implement-quaere` then `review-pipeline` with the same seam rule and merge gate. |

### Quality Gates

| Skill | Description |
| -- | -- |
| `quality-list` | Single source of truth for universal code-quality items, referenced by `done-check` and `todo-check` |
| `todo-check` | Preflight sweep of quality items before/during implementation |
| `done-check` | Post-hoc audit of quality items before declaring a task complete or requesting external review |

### Post-Ship Hygiene

| Skill | Description |
| -- | -- |
| `bug-to-contract` | Promote review findings and bug fixes into runtime contract tests |
| `finding-to-audit` | Promote review findings into pre-commit audit rules that catch issues at diff-inspection time |
| `gate-miss-to-issue` | Promote a late-caught defect — one an earlier gate should have caught — into a development-skills issue proposing a fix to that gate's procedure |
| `codex-contract-test-review` | Narrow Codex pass to verify a newly added contract test actually expresses the claimed contract |
| `driftreaper` | Audit docstrings for drift against actual code behavior |
| `breachreaper` | Audit existing code for stock-detectable API-contract breaches |

### Language-specific

| Skill | Description |
| -- | -- |
| `languages/Rust/cargo-mutants` | Configure and run cargo-mutants for Rust mutation testing |
| `languages/Rust/rust-ffi-rule` | Rules for implementing a Rust safe wrapper around an external (C / Fortran / FFI) call |
| `languages/Cpp/stdlib-audit` | Audit C++ source for known-bad standard library defaults via a TSV-driven, extensible rule table |

## Install

### development-skills

```bash
claude plugin marketplace add ultimatile/development-skills
claude plugin install development-skills
```

### gh-post

The skills that draft or post GitHub issue / PR bodies (`file-issue`, `file-pullreq`, `copilot-review`, `review-pipeline`, `research`, `implement`, and their wrappers / `-quaere` variants) route every body through the [`gh-post`](https://github.com/ultimatile/gh-post) wrapper — a `gh` front-end that accepts bodies only via `--body-file` / `--body-stdin` and re-runs a hard-wrap validator before forwarding to `gh`. Install it and make sure `gh-post` is on `PATH`.

### Quaere skills

The `*-quaere` variants (`research-quaere`, `implement-quaere`, `research-and-implement-quaere`, `reimre-quaere`) require the upstream Quaere skills (`quaere-evidence`, `quaere-execution`, `quaere-semantic`) installed under `~/.claude/skills/`:

```bash
npx quaere-cli install --target claude
```

The original variants (without the `-quaere` suffix) instead depend on the archived [haru0416-dev/agent-skills](https://github.com/haru0416-dev/agent-skills) (`evidence-gated-review`, `execution-loop`).

## Credits

The XML-block prompt structure used in `codex-plan-review` is inspired by the `gpt-5-4-prompting` skill from [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc).
