---
name: read-issue
description: Read a GitHub issue's title, body and every comment as one CommonMark document, the body and each comment in a fenced code block under its own heading.
---

# Read Issue

## Invocation

```bash
${CLAUDE_SKILL_DIR}/scripts/read-issue.sh <number> [--repo OWNER/REPO]
```

A skill in a sibling directory calls it as `${CLAUDE_SKILL_DIR}/../read-issue/scripts/read-issue.sh`.

## Output

A CommonMark document:

- `# ` followed by the issue's title, with each line ending in the title (LF, CR, or CR LF) replaced by a space.
- A `## body` heading, then the body in a fenced code block.
- For each comment, a `## comment by <login> at <timestamp>` heading, then the comment in a fenced code block.

Each fence is a run of backticks one longer than the longest run of backticks in its content, and at least three long, so no line of the content closes it. The opening fence carries the info string `markdown`. The content inside a fence is the body or the comment unchanged.

## Failure

When the script cannot read its filter file or `gh` cannot read the issue, the script exits with the failing command's nonzero status, prints that command's message on stderr, and prints nothing on stdout.
