#!/bin/sh
# Print a GitHub issue's title, body and every comment as one CommonMark document.
# Arguments are passed to `gh issue view`: <number> [--repo OWNER/REPO].
filter=$(cat "$(dirname "$0")/read-issue.jq") || exit
exec gh issue view "$@" --json title,body,comments --jq "$filter"
