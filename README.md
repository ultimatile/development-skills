# development-skills

End-to-end development workflow skills for Claude Code — from a GitHub issue to a merged PR.

## Skills

### Issue → Plan → Code

| Skill | Description |
|---|---|
| `research` | Hypothesis-driven investigation of an issue; parallel subagent verification; produces a concrete implementation plan |
| `codex-plan-review` | Review the implementation plan with Codex against the actual codebase before coding |
| `implement` | Execute an approved plan, enforce implementation guards, run baseline/fixture checks |
| `research-and-implement` | Thin wrapper that runs `research` then `implement` |

### Code → Review → Ship

| Skill | Description |
|---|---|
| `stage-commit-push` | Stage, generate conventional commit message, commit, and push |
| `codex-review` | Run OpenAI Codex review with triage before PR creation |
| `copilot-review` | Create PR with GitHub Copilot review, poll for results, triage |
| `review-pipeline` | Orchestrator — runs the full flow from local changes to reviewed PR |

### Post-Ship Hygiene

| Skill | Description |
|---|---|
| `bug-to-contract` | Promote review findings and bug fixes into contract tests |
| `driftreaper` | Audit docstrings for drift against actual code behavior |

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
