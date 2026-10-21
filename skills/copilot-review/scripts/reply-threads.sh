#!/usr/bin/env bash
# Post replies to PR inline review threads, each marked with its disposition.
#
# Usage:
#   ./reply-threads.sh OWNER/REPO PR < replies.jsonl
#
# Input (one JSON object per line; blank lines are skipped):
#   {"id": <int>, "disposition": <slug>, "body": <str>}
#     id           head_id of the thread, as list-pr-threads.sh prints it
#     disposition  lowercase words joined by single hyphens
#     body         one line, without `<!--`
#
# Each reply is posted as
#
#   `<slug>` — <body>
#
#   <!-- disposition: <slug> -->
#
# through `gh-post reply-inline`, and list-pr-threads.sh reads the slug back
# from that last line. Every line is validated before anything is sent; an
# invalid line exits 2 with nothing sent. Otherwise the exit status is
# gh-post's.

set -euo pipefail

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
  exit "${1:-0}"
}

positional=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --) shift; while [[ $# -gt 0 ]]; do positional+=("$1"); shift; done ;;
    -*) echo "error: unknown flag: $1" >&2; usage 2 ;;
    *)  positional+=("$1"); shift ;;
  esac
done

if [[ ${#positional[@]} -ne 2 ]]; then
  echo "error: expected OWNER/REPO and PR number" >&2
  usage 2
fi

repo="${positional[0]}"
pr="${positional[1]}"

if [[ "$repo" != */* || "$repo" == */*/* || "$repo" == /* || "$repo" == */ ]]; then
  echo "error: invalid OWNER/REPO: $repo" >&2
  exit 2
fi

input=$(mktemp)
replies=$(mktemp)
trap 'rm -f "$input" "$replies"' EXIT
cat >"$input"

n=0
while IFS= read -r line || [[ -n "$line" ]]; do
  n=$((n + 1))
  [[ -z "${line//[[:space:]]/}" ]] && continue
  if ! jq -ces '
      select(length == 1) | .[0]
      | select(
        type == "object"
        and (.id | type == "number" and (tojson | test("^[1-9][0-9]*$")))
        and (.disposition | type == "string" and test("^[a-z]+(-[a-z]+)*$"))
        and (.body | type == "string" and test("\\S") and (test("[\r\n]") | not) and (contains("<!--") | not))
      )
      | {id, body: "`\(.disposition)` — \(.body | sub("\\s+$"; ""))\n\n<!-- disposition: \(.disposition) -->"}
    ' <<<"$line" >>"$replies" 2>/dev/null; then
    echo "error: line $n: expected {\"id\": <positive int>, \"disposition\": <slug>, \"body\": <one line without <!-->}" >&2
    exit 2
  fi
done <"$input"

gh-post reply-inline "$repo" "$pr" <"$replies"
