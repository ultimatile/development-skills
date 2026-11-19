---
name: run-codex
description: Run an OpenAI Codex CLI prompt or review non-interactively and report its outcome, the model that served it, and where its result is, as status lines.
---

# Run Codex

Supported CLI baseline: codex-cli 0.170.0.

## Invocation

```bash
"${CLAUDE_SKILL_DIR}/scripts/run-codex.sh" prompt [--schema <schema-file>] <prompt>
"${CLAUDE_SKILL_DIR}/scripts/run-codex.sh" review <review-target-arguments>...
```

- `prompt` runs `codex exec` on `<prompt>`. With `--schema`, Codex's final response follows the JSON Schema in `<schema-file>`.
- `review` runs `codex exec review` with `<review-target-arguments>`: `--base <rev>`, `--uncommitted`, or `--commit <sha>`.

Each run starts a new Codex session that is not saved, and writes into its own new directory.
Set the Bash timeout to 600000 ms.

## Output

Four lines on stdout:

- `status: <status>`, one of:
  - `completed`;
  - `failed` — Codex exited nonzero;
  - `missing-result` — Codex exited 0 and left no final message;
  - `invalid-result` — with `--schema`, the final message is not a JSON object holding every key the schema's top-level `required` lists.
- `model: <model>` — the model Codex itself reports for the run's completed model requests, or `unknown` when it reports none or more than one.
- `result: <path>` — the file holding Codex's final message.
- `log: <path>` — the file holding Codex's stdout and stderr.

The script exits 0 when the status is `completed` and 1 otherwise.
On a usage error it prints its usage on stderr, runs nothing, and exits 2.
