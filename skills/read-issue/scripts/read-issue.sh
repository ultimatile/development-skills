#!/bin/sh
# Print a GitHub issue's title, body and every comment as multi-line text.
# Arguments are passed to `gh issue view`: <number> [--repo OWNER/REPO].
exec gh issue view "$@" --json title,body,comments --jq "$(cat "$(dirname "$0")/read-issue.jq")"
