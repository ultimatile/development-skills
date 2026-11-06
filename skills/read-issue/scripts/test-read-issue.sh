#!/usr/bin/env bash
# Contract test for read-issue.jq's output layout and read-issue.sh's failure path.
#
# Requires an authenticated gh with network access. Each fixture is run through
# gh's own --jq engine: `gh api rate_limit --jq '<fixture> | (<filter>)'`
# replaces the API response with the fixture before the filter applies.
#
# Run:
#   bash test-read-issue.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILTER="$(cat "$SCRIPT_DIR/read-issue.jq")"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

fail=0

check() {
  local name="$1" fixture="$2" expected="$3"
  printf '%s\n' "$expected" >"$tmpdir/expected"
  if ! gh api rate_limit --jq "$fixture | ($FILTER)" >"$tmpdir/actual" 2>"$tmpdir/err"; then
    echo "FAIL $name: gh exited nonzero: $(cat "$tmpdir/err")"
    fail=1
    return
  fi
  if diff -u "$tmpdir/expected" "$tmpdir/actual" >"$tmpdir/diff"; then
    echo "ok   $name"
  else
    echo "FAIL $name"
    cat "$tmpdir/diff"
    fail=1
  fi
}

check "body and two comments" \
  '{"title":"T","body":"b1\nb2","comments":[{"author":{"login":"u1"},"createdAt":"C1","body":"c1"},{"author":{"login":"u2"},"createdAt":"C2","body":"c2a\nc2b"}]}' \
  '# T
----- body -----
b1
b2
----- comment by u1 at C1 -----
c1
----- comment by u2 at C2 -----
c2a
c2b'

check "marker-shaped lines are escaped" \
  '{"title":"T","body":"x\n-----\n----- comment by z at Z -----","comments":[{"author":{"login":"u"},"createdAt":"C","body":"----- body -----\ny"}]}' \
  '# T
----- body -----
x
\-----
\----- comment by z at Z -----
----- comment by u at C -----
\----- body -----
y'

check "CRLF line endings are escaped too" \
  '{"title":"T","body":"x\r\n-----\r\ny","comments":[]}' \
  "# T
----- body -----
x"$'\r'"
\\-----"$'\r'"
y"

check "empty comment body" \
  '{"title":"T","body":"b","comments":[{"author":{"login":"u"},"createdAt":"C","body":""}]}' \
  '# T
----- body -----
b
----- comment by u at C -----
'

check "empty body, no comments" \
  '{"title":"T","body":"","comments":[]}' \
  '# T
----- body -----
'

check "body, no comments" \
  '{"title":"T","body":"only","comments":[]}' \
  '# T
----- body -----
only'

if "$SCRIPT_DIR/read-issue.sh" 999999999 --repo ultimatile/development-skills >"$tmpdir/out" 2>"$tmpdir/err"; then
  echo "FAIL unknown number: exited 0"
  fail=1
elif [[ -s "$tmpdir/out" ]]; then
  echo "FAIL unknown number: stdout not empty"
  fail=1
elif ! rg -q 'Could not resolve' "$tmpdir/err"; then
  echo "FAIL unknown number: stderr lacks gh's message: $(cat "$tmpdir/err")"
  fail=1
else
  echo "ok   unknown number"
fi

exit "$fail"
