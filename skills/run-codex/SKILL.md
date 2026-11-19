---
name: run-codex
description: Run an OpenAI Codex CLI prompt or review non-interactively and report its outcome, the model that served it, and where its result is, as status lines.
---

# Run Codex

Supported CLI baseline: codex-cli 0.170.0.

## Invocation

```bash
"${CLAUDE_SKILL_DIR}/scripts/run-codex.sh" prompt [--schema <schema-file>] <prompt-file>
"${CLAUDE_SKILL_DIR}/scripts/run-codex.sh" review <review-target-arguments>...
```

- `prompt` runs `codex exec` on the content of `<prompt-file>`. With `--schema`, Codex's final response follows the JSON Schema in `<schema-file>`.
- `review` runs `codex exec review` with `<review-target-arguments>`: `--base <rev>`, `--uncommitted`, or `--commit <sha>`.

Each run starts a new Codex session that is not saved, and writes into its own new directory.

## Output

After running Codex, the script prints four lines on stdout:

- `status: <status>`, the first of these that applies, in this order:
  - `failed` — Codex exited nonzero;
  - `missing-result` — Codex left no final message;
  - `invalid-result` — with `--schema`, the final message is not a JSON object holding every key the schema's top-level `required` lists;
  - `completed` — otherwise.
- `model: <model>` — the model Codex itself reports for the run's completed model requests when they name exactly one, `unknown` otherwise.
- `result: <path>` — the file holding Codex's final message.
- `log: <path>` — the file holding Codex's stdout and stderr.

The script exits 0 when the status is `completed` and 1 for any other status.
When it does not run Codex, it prints the reason on stderr and no status lines, and exits 2.
