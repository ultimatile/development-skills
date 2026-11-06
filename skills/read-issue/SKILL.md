---
name: read-issue
description: Read a GitHub issue's title, body and every comment as multi-line text, the body and each comment opened by a marker line.
---

# Read Issue

## Invocation

```bash
${CLAUDE_SKILL_DIR}/scripts/read-issue.sh <number> [--repo OWNER/REPO]
```

A skill in a sibling directory calls it as `${CLAUDE_SKILL_DIR}/../read-issue/scripts/read-issue.sh`.

## Output

Lines are separated by LF.

- The first line is `# ` followed by the issue's title, with each LF in the title, together with a CR just before it, replaced by a space.
- The line `----- body -----` opens the body.
- Each comment opens with the line `----- comment by <login> at <timestamp> -----`.
- A body or comment line that begins with `-----`, or with one or more `\` followed by `-----`, is printed with one more leading `\`. Every line that begins with `-----` is therefore one of the two markers above, and removing one leading `\` from a line that begins with one or more `\` followed by `-----` restores it.

## Failure

When the script cannot read its filter file or `gh` cannot read the issue, the script exits with the failing command's nonzero status, prints that command's message on stderr, and prints nothing on stdout.
