---
name: read-issue
description: Read a GitHub issue's title, body and every comment as multi-line text, each section opened by a marker line.
---

# Read Issue

## Invocation

```bash
${CLAUDE_SKILL_DIR}/scripts/read-issue.sh <number> [--repo OWNER/REPO]
```

A skill in a sibling directory calls it as `${CLAUDE_SKILL_DIR}/../read-issue/scripts/read-issue.sh`.

## Output

- The first line is `# ` followed by the issue's title.
- The line `----- body -----` opens the body.
- Each comment opens with the line `----- comment by <login> at <timestamp> -----`.
- A body or comment line that begins with `-----` is printed with a leading `\`. Every line that begins with `-----` is therefore one of the two markers above.

## Failure

When `gh` cannot read the issue, the script exits with `gh`'s nonzero status, prints `gh`'s message on stderr, and prints nothing on stdout.
