#!/usr/bin/env bash
# Post replies to PR inline review threads, each marked with its disposition.
#
# Usage:
#   ./reply-threads.sh OWNER/REPO PR < replies.jsonl
#
# Input (one JSON object per line; blank lines are skipped):
#   {"id": <head_id>, "disposition": <slug>, "body": <str>}
#     disposition  lowercase words joined by single hyphens
#     body         one non-blank line, without `<!--`
#
# Each reply is built as
#
#   `<slug>` — <body>
#
#   <!-- disposition: <slug> -->
#
# and passed to `gh-post reply-inline`, which keeps the marker as the last
# line, where list-pr-threads.sh reads the slug back. A line whose disposition
# or body breaks these terms exits 2 before anything is sent.

set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: reply-threads.sh OWNER/REPO PR < replies.jsonl" >&2
  exit 2
fi

replies=$(mktemp)
trap 'rm -f "$replies"' EXIT

n=0
while IFS= read -r line || [[ -n "$line" ]]; do
  n=$((n + 1))
  [[ -z "${line//[[:space:]]/}" ]] && continue
  if ! jq -ce '
      select(
        (.disposition | type == "string" and test("\\A[a-z]+(-[a-z]+)*\\z"))
        and (.body | type == "string" and test("\\S") and (test("[\r\n]") | not) and (contains("<!--") | not))
      )
      | {id, body: "`\(.disposition)` — \(.body)\n\n<!-- disposition: \(.disposition) -->"}
    ' <<<"$line" >>"$replies" 2>/dev/null; then
    echo "error: line $n: expected a disposition slug and a one-line body without <!--" >&2
    exit 2
  fi
done

gh-post reply-inline "$1" "$2" <"$replies"
