# development-skills

End-to-end development workflow skills for Claude Code — from a GitHub issue to a merged PR.

## Skills

### Issue → Plan → Code

| Skill | Description |
|---|---|
| `research` | Hypothesis-driven investigation under the four-state decision discipline (confirmed / rejected / inconclusive / deferred). Classifies hypotheses as empirical (subagent-verified) vs derivational (deduced in main context); posts the resulting plan to the issue body (umbrella-spawned sub-issue) or comment (single-scope issue). Depends on [haru0416-dev/agent-skills](https://github.com/haru0416-dev/agent-skills) (`evidence-gated-review`) |
| `codex-plan-review` | Review the implementation plan with Codex against the actual codebase before coding |
| `implement` | Execute a plan via the execution-loop discipline (Read → Plan → Execute → Review → Fix → Verify) with drift surfacing and done-check before completion. Reads the plan from the sub-issue body (umbrella-spawned) or comments (single-scope). Depends on [haru0416-dev/agent-skills](https://github.com/haru0416-dev/agent-skills) (`execution-loop`) |
| `research-and-implement` | End-to-end wrapper that runs `research` (Phase 1) then `implement` (Phase 2), with a branch baseline gate up front. Depends on [haru0416-dev/agent-skills](https://github.com/haru0416-dev/agent-skills) (`evidence-gated-review` + `execution-loop`) |
| `reimre` | Full end-to-end wrapper — runs `research-and-implement` then `review-pipeline` back to back, with an automatic seam rule that skips the duplicate `done-check` at the boundary. Stops at the user-controlled merge gate inherited from `review-pipeline`. |

### Issue & PR drafting

| Skill | Description |
|---|---|
| `file-issue` | Draft and file a GitHub issue following formatting conventions (semantic line breaks, LaTeX math, no local references). Includes an umbrella sub-issue variant (Parent: linkage, Goal/Scope/Out of scope/Acceptance shape) used by `research` when spawning sub-issues from an umbrella |

### Code → Review → Ship

| Skill | Description |
|---|---|
| `stage-commit-push` | Stage, generate conventional commit message, commit, and push |
| `codex-review` | Run OpenAI Codex review with triage before PR creation |
| `copilot-review` | Create PR with GitHub Copilot review, poll for results, triage |
| `review-pipeline` | Orchestrator — runs the full flow from local changes to reviewed PR |

### Quality Gates

| Skill | Description |
|---|---|
| `quality-list` | Single source of truth for universal code-quality items, referenced by `done-check` and `todo-check` |
| `todo-check` | Preflight sweep of quality items before/during implementation |
| `done-check` | Post-hoc audit of quality items before declaring a task complete or requesting external review |

### Post-Ship Hygiene

| Skill | Description |
|---|---|
| `bug-to-contract` | Promote review findings and bug fixes into runtime contract tests |
| `finding-to-audit` | Promote review findings into pre-commit audit rules that catch issues at diff-inspection time |
| `codex-contract-test-review` | Narrow Codex pass to verify a newly added contract test actually expresses the claimed contract |
| `driftreaper` | Audit docstrings for drift against actual code behavior |
| `breachreaper` | Audit existing code for stock-detectable API-contract breaches (defensive-transformation replication, parallel-impl surface asymmetry, architectural-boundary violations, sibling-method guard asymmetry) |

### Language-specific

| Skill | Description |
|---|---|
| `languages/Rust/cargo-mutants` | Configure and run cargo-mutants for Rust mutation testing |
| `languages/Rust/rust-ffi-rule` | Rules for implementing a Rust safe wrapper around an external (C / Fortran / FFI) call |

## End-to-end flow

```
/research <issue>        → plan posted to issue
     ↓
/codex-plan-review       → plan validated against codebase
     ↓
/implement <issue>       → code written, tests green
     ↓
/review-pipeline         → codex review loop → PR with Copilot review → fix loop
     ↓
/bug-to-contract         → contract tests added for findings
     ↓
/driftreaper             → periodic docstring audit
```

`/reimre <issue>` collapses the first four steps (research → plan review → implement → review-pipeline) into one invocation with the seam handled automatically.

## Install

```bash
claude plugin marketplace add ultimatile/development-skills
claude plugin install development-skills
```

## Credits

The XML-block prompt structure used in `codex-plan-review` is inspired by the `gpt-5-4-prompting` skill from [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc).
