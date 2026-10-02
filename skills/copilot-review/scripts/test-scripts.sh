#!/usr/bin/env bash
# Contract test for the output of list-pr-threads.sh and of
# pr-with-copilot-review.sh's poll.
#
# Requires jq.
#
# Run:
#   bash test-scripts.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIST="$SCRIPT_DIR/list-pr-threads.sh"
POLL="$SCRIPT_DIR/pr-with-copilot-review.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
mkdir "$tmpdir/bin"

cat >"$tmpdir/bin/gh" <<'STUB'
#!/usr/bin/env bash
# Stub gh: pick a fixture by endpoint, apply the --jq filter with jq.
filter=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  [[ "${args[i]}" == "--jq" ]] && filter="${args[i + 1]}"
done
case "$*" in
  "api graphql"*) fixture="$FIXTURES/threads.json" ;;
  *"/reviews"*)   fixture="$FIXTURES/reviews.json" ;;
  *"/comments"*)  fixture="$FIXTURES/comments.json" ;;
  *) echo "stub gh: unexpected call: $*" >&2; exit 97 ;;
esac
jq -r "$filter" "$fixture"
STUB
chmod +x "$tmpdir/bin/gh"

export FIXTURES="$tmpdir"
export PATH="$tmpdir/bin:$PATH"

# Six threads: Copilot-headed with 0, 1 and 2 replies, a resolved Copilot-headed
# one, one headed by someone else, and a Copilot-headed one whose reply is
# empty. The 2-reply thread's latest body carries a tab, a newline and a quote.
cat >"$tmpdir/threads.json" <<'JSON'
{"data": {"repository": {"pullRequest": {"reviewThreads": {"nodes": [
  {"isResolved": false, "isOutdated": false,
   "head": {"totalCount": 1, "nodes": [{"databaseId": 101, "author": {"login": "copilot-pull-request-reviewer"}, "path": "a.md", "line": 3, "body": "head one"}]},
   "tail": {"nodes": [{"body": "head one"}]}},
  {"isResolved": false, "isOutdated": true,
   "head": {"totalCount": 2, "nodes": [{"databaseId": 102, "author": {"login": "copilot-pull-request-reviewer"}, "path": "a.md", "line": null, "body": "head two"}]},
   "tail": {"nodes": [{"body": "only reply"}]}},
  {"isResolved": false, "isOutdated": false,
   "head": {"totalCount": 3, "nodes": [{"databaseId": 103, "author": {"login": "copilot-pull-request-reviewer"}, "path": "b.md", "line": 7, "body": "head three"}]},
   "tail": {"nodes": [{"body": "second\treply\nwith \"quote\""}]}},
  {"isResolved": true, "isOutdated": true,
   "head": {"totalCount": 2, "nodes": [{"databaseId": 104, "author": {"login": "copilot-pull-request-reviewer"}, "path": "c.md", "line": null, "body": "head four"}]},
   "tail": {"nodes": [{"body": "reply on resolved"}]}},
  {"isResolved": false, "isOutdated": false,
   "head": {"totalCount": 1, "nodes": [{"databaseId": 105, "author": {"login": "someone"}, "path": "d.md", "line": 1, "body": "human head"}]},
   "tail": {"nodes": [{"body": "human head"}]}},
  {"isResolved": false, "isOutdated": false,
   "head": {"totalCount": 2, "nodes": [{"databaseId": 106, "author": {"login": "copilot-pull-request-reviewer"}, "path": "e.md", "line": 2, "body": "head six"}]},
   "tail": {"nodes": [{"body": ""}]}}
]}}}}}
JSON

# Two Copilot reviews and a human one; the poll reports the later Copilot review.
cat >"$tmpdir/reviews.json" <<'JSON'
[
  {"id": 10, "user": {"login": "copilot-pull-request-reviewer[bot]"}, "body": "older summary"},
  {"id": 15, "user": {"login": "someone"}, "body": "human review"},
  {"id": 20, "user": {"login": "copilot-pull-request-reviewer[bot]"}, "body": "latest summary"}
]
JSON

# Comments of the older review, of the latest one, and a human reply filed
# under the latest review's id. The latest review's first body has two lines
# and its second carries a tab.
cat >"$tmpdir/comments.json" <<'JSON'
[
  {"id": 111, "user": {"login": "Copilot"}, "pull_request_review_id": 10, "path": "a.md", "line": 3, "body": "older finding"},
  {"id": 222, "user": {"login": "Copilot"}, "pull_request_review_id": 20, "path": "a.md", "line": 5, "body": "latest finding\nsecond line"},
  {"id": 333, "user": {"login": "Copilot"}, "pull_request_review_id": 20, "path": "b.md", "line": null, "body": "outdated\tfinding"},
  {"id": 444, "user": {"login": "someone"}, "pull_request_review_id": 20, "path": "a.md", "line": 5, "body": "human reply"}
]
JSON

fails=0
check() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    printf 'ok   %s\n' "$label"
  else
    printf 'FAIL %s\n       expected: %s\n       actual:   %s\n' "$label" "$expected" "$actual"
    fails=$((fails + 1))
  fi
}

# --- list-pr-threads.sh -----------------------------------------------------
threads="$("$LIST" owner/repo 1)"
field() { jq -c "select(.head_id == $1) | $2" <<<"$threads"; }

check "list: one line per Copilot-headed thread" "5" "$(wc -l <<<"$threads" | tr -d ' ')"
check "list: head ids, other-headed thread dropped" "101 102 103 104 106" "$(jq -r .head_id <<<"$threads" | paste -sd' ' -)"
check "list: no reply -> reply_count 0" "0" "$(field 101 .reply_count)"
check "list: no reply -> last_reply_body null" "null" "$(field 101 .last_reply_body)"
check "list: one reply -> its body" '"only reply"' "$(field 102 .last_reply_body)"
check "list: two replies -> reply_count 2" "2" "$(field 103 .reply_count)"
check "list: two replies -> the latest body" '"second\treply\nwith \"quote\""' "$(field 103 .last_reply_body)"
check "list: resolved thread is listed" "true" "$(field 104 .resolved)"
check "list: resolved thread carries its reply" '"reply on resolved"' "$(field 104 .last_reply_body)"
check "list: empty reply -> empty string, not null" '""' "$(field 106 .last_reply_body)"

"$LIST" owner/repo 1 --unresolved >/dev/null 2>&1
check "list: an unknown flag is rejected" "2" "$?"

# --- pr-with-copilot-review.sh --poll ---------------------------------------
poll="$(COPILOT_POLL_INITIAL=0 "$POLL" --poll https://github.com/owner/repo/pull/1 2>/dev/null)"
inline="$(awk 'found { print } /^=== Inline Comments ===$/ { found = 1 }' <<<"$poll")"

check "poll: latest Copilot review's summary" "latest summary" "$(awk '/^=== Review Summary ===$/ { getline; print; exit }' <<<"$poll")"
check "poll: one id-led line per Copilot comment of the latest review" "222 333" "$(awk -F'\t' '/^[0-9]+\t/ { print $1 }' <<<"$inline" | paste -sd' ' -)"
check "poll: a comment starts with id, path:line, body" $'222\ta.md:5\tlatest finding' "$(awk 'NR == 1' <<<"$inline")"
check "poll: a body's later lines follow as printed" "second line" "$(awk 'NR == 2' <<<"$inline")"
check "poll: null line is printed as null" $'333\tb.md:null\toutdated\tfinding' "$(awk 'NR == 3' <<<"$inline")"

echo
if ((fails == 0)); then
  echo "All checks passed."
else
  echo "$fails check(s) failed."
  exit 1
fi
