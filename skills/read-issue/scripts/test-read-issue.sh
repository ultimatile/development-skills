#!/usr/bin/env bash
# Contract test for read-issue.jq's output layout, and for read-issue.sh on a
# real issue and on its two failure paths.
#
# Requires rg, and an authenticated gh with network access. Each fixture is run through
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

check "title, body and two comments" \
  '{"title":"T","body":"b1\nb2","comments":[{"author":{"login":"u1"},"createdAt":"C1","body":"c1"},{"author":{"login":"u2"},"createdAt":"C2","body":"c2a\nc2b"}]}' \
  $'# issue\n\n## title\n\n```text\nT\n```\n\n## body\n\n```markdown\nb1\nb2\n```\n\n## comment by u1 at C1\n\n```markdown\nc1\n```\n\n## comment by u2 at C2\n\n```markdown\nc2a\nc2b\n```'

check "structure-shaped content comes out unchanged" \
  '{"title":"Support issue #","body":"x\n-----\n## comment by z at Z\n# heading","comments":[{"author":{"login":"u"},"createdAt":"C","body":"## body\n\\-----"}]}' \
  $'# issue\n\n## title\n\n```text\nSupport issue #\n```\n\n## body\n\n```markdown\nx\n-----\n## comment by z at Z\n# heading\n```\n\n## comment by u at C\n\n```markdown\n## body\n\\-----\n```'

check "a fence grows past the longest backtick run in its content" \
  '{"title":"T `x` ````","body":"```sh\necho hi\n```\n````\n`x`","comments":[{"author":{"login":"u"},"createdAt":"C","body":"``````"}]}' \
  $'# issue\n\n## title\n\n`````text\nT `x` ````\n`````\n\n## body\n\n`````markdown\n```sh\necho hi\n```\n````\n`x`\n`````\n\n## comment by u at C\n\n```````markdown\n``````\n```````'

check "short backtick runs, a tilde fence and blank lines keep the three-backtick fence" \
  '{"title":"T","body":"  \n~~~\n``","comments":[{"author":{"login":"u"},"createdAt":"C","body":"`a`"}]}' \
  $'# issue\n\n## title\n\n```text\nT\n```\n\n## body\n\n```markdown\n  \n~~~\n``\n```\n\n## comment by u at C\n\n```markdown\n`a`\n```'

check "line endings in the title and body come out unchanged" \
  '{"title":"T1\r\nT2\rT3","body":"x\r\n-----\r\ny","comments":[]}' \
  $'# issue\n\n## title\n\n```text\nT1\r\nT2\rT3\n```\n\n## body\n\n```markdown\nx\r\n-----\r\ny\n```'

check "empty body, empty comment" \
  '{"title":"T","body":"","comments":[{"author":{"login":"u"},"createdAt":"C","body":""}]}' \
  $'# issue\n\n## title\n\n```text\nT\n```\n\n## body\n\n```markdown\n\n```\n\n## comment by u at C\n\n```markdown\n\n```'

# A closed issue of this repository with comments: the script and the filter together.
if ! "$SCRIPT_DIR/read-issue.sh" 266 --repo ultimatile/development-skills >"$tmpdir/out" 2>"$tmpdir/err"; then
  echo "FAIL real issue: exited nonzero: $(cat "$tmpdir/err")"
  fail=1
elif [[ "$(head -1 "$tmpdir/out")" != "# issue" ]]; then
  echo "FAIL real issue: first line is not the document heading"
  fail=1
elif ! rg -q '^## title$' "$tmpdir/out" || ! rg -q '^## body$' "$tmpdir/out"; then
  echo "FAIL real issue: no title or body heading"
  fail=1
elif ! rg -q '^## comment by \S+ at \S+$' "$tmpdir/out"; then
  echo "FAIL real issue: no comment heading"
  fail=1
else
  echo "ok   real issue"
fi

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

mkdir "$tmpdir/nofilter"
cp "$SCRIPT_DIR/read-issue.sh" "$tmpdir/nofilter/"
if "$tmpdir/nofilter/read-issue.sh" 296 --repo ultimatile/development-skills >"$tmpdir/out" 2>"$tmpdir/err"; then
  echo "FAIL missing filter file: exited 0"
  fail=1
elif [[ -s "$tmpdir/out" ]]; then
  echo "FAIL missing filter file: stdout not empty"
  fail=1
elif ! rg -q 'read-issue\.jq' "$tmpdir/err"; then
  echo "FAIL missing filter file: stderr does not name the filter file: $(cat "$tmpdir/err")"
  fail=1
else
  echo "ok   missing filter file"
fi

exit "$fail"
