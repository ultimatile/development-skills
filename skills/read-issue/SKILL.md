---
name: read-issue
description: Read a GitHub issue's title, body and every comment as one CommonMark document, each in a fenced code block under its own heading.
---

# Read Issue

## Invocation

```bash
${CLAUDE_SKILL_DIR}/scripts/read-issue.sh <number> [--repo OWNER/REPO]
```

A skill in a sibling directory calls it as `${CLAUDE_SKILL_DIR}/../read-issue/scripts/read-issue.sh`.

## Output

A CommonMark document whose headings hold only fixed text, logins and timestamps. Everything written in the issue sits in a fenced code block:

- `# issue`.
- `## title`, then the title in a fenced code block with the info string `text`.
- `## body`, then the body in a fenced code block with the info string `markdown`.
- For each comment, `## comment by <login> at <timestamp>`, then the comment in a fenced code block with the info string `markdown`.

Each fence is a run of backticks whose length is the larger of three and one more than the longest run of backticks in its content, so no line of the content closes it. The content inside a fence is printed unchanged.

## Failure

When the script cannot read its filter file or `gh` cannot read the issue, the script exits with the failing command's nonzero status, prints that command's message on stderr, and prints nothing on stdout.
