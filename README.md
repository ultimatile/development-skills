# development-skills

End-to-end development workflow skills for Claude Code — from a GitHub issue to a merged PR.

## Skills

### Issue → Plan → Code

| Skill | Description |
|---|---|
| `research` | Hypothesis-driven investigation of an issue; parallel subagent verification; produces a concrete implementation plan |
| `research-eg` | Evidence-gated variant of `research` — classifies hypotheses as empirical vs derivational with mandatory disconfirming probes and four-state decisions (confirmed / rejected / inconclusive / deferred). Depends on [haru0416-dev/agent-skills](https://github.com/haru0416-dev/agent-skills) (`evidence-gated-review`) |
| `codex-plan-review` | Review the implementation plan with Codex against the actual codebase before coding |
| `implement` | Execute an approved plan, enforce implementation guards, run baseline/fixture checks |
| `implement-el` | Execute a plan via the execution-loop discipline (Read → Plan → Execute → Review → Fix → Verify) with drift surfacing and done-check before completion. Depends on [haru0416-dev/agent-skills](https://github.com/haru0416-dev/agent-skills) (`execution-loop`) |
| `research-and-implement` | Thin wrapper that runs `research` then `implement` |
| `research-and-implement-egel` | Evidence-gated end-to-end wrapper that runs `research-eg` then `implement-el`. Depends on [haru0416-dev/agent-skills](https://github.com/haru0416-dev/agent-skills) (`evidence-gated-review` + `execution-loop`) |

### Umbrella Tracking

| Skill | Description |
|---|---|
| `plan-and-spawn` | Decompose an umbrella tracking issue into one next sub-issue with a plan-confirmed, frozen contract body |
| `spawn-subissue` | Clerical spawn of the next sub-issue from an umbrella by extracting verbatim sections (no plan-confirm gate) |
| `file-issue` | Draft and file a GitHub issue following formatting conventions (semantic line breaks, LaTeX math, no local references) |

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

## Install

```bash
claude plugin marketplace add ultimatile/development-skills
claude plugin install development-skills
```

## Credits

The XML-block prompt structure used in `codex-plan-review` is inspired by the `gpt-5-4-prompting` skill from [openai/codex-plugin-cc](https://github.com/openai/codex-plugin-cc).
