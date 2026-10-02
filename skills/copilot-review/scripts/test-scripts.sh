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
# A call whose arguments contain $STUB_FAIL exits 1.
# A read of the review comments without --paginate gets the first 8.
[[ -n "${STUB_FAIL:-}" && "$*" == *"$STUB_FAIL"* ]] && exit 1
filter=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  [[ "${args[i]}" == "--jq" ]] && filter="${args[i + 1]}"
done
page=""
case "$*" in
  "api graphql"*) fixture="$FIXTURES/threads.json" ;;
  *"/reviews"*)   fixture="$FIXTURES/reviews.json" ;;
  *"/comments"*)
    fixture="$FIXTURES/comments.json"
    [[ " $* " == *" --paginate "* ]] || page=".[0:8] | "
    ;;
  *) echo "stub gh: unexpected call: $*" >&2; exit 97 ;;
esac
jq -r "$page$filter" "$fixture"
STUB
chmod +x "$tmpdir/bin/gh"

export FIXTURES="$tmpdir"
export PATH="$tmpdir/bin:$PATH"

# One pull request, as each API returns it. Copilot reviewed it twice (reviews
# 10 and 20) and someone else once (15). Its threads are headed by comments
# 101-106: five by Copilot, with 0, 1, 2, 1 and 1 replies, and 105 by someone
# else. Thread 104 is resolved.
cat >"$tmpdir/reviews.json" <<'JSON'
[
  {"id": 10, "user": {"login": "copilot-pull-request-reviewer[bot]"}, "body": "older summary"},
  {"id": 15, "user": {"login": "someone"}, "body": "human review"},
  {"id": 20, "user": {"login": "copilot-pull-request-reviewer[bot]"}, "body": "latest summary"}
]
JSON

cat >"$tmpdir/threads.json" <<'JSON'
{"data": {"repository": {"pullRequest": {"reviewThreads": {"nodes": [
  {"isResolved": false, "isOutdated": false, "comments": {"totalCount": 1, "nodes": [
    {"databaseId": 101, "author": {"login": "copilot-pull-request-reviewer"}, "path": "a.md", "line": 3, "body": "head one"}]}},
  {"isResolved": false, "isOutdated": true, "comments": {"totalCount": 2, "nodes": [
    {"databaseId": 102, "author": {"login": "copilot-pull-request-reviewer"}, "path": "a.md", "line": null, "body": "head two"}]}},
  {"isResolved": false, "isOutdated": false, "comments": {"totalCount": 3, "nodes": [
    {"databaseId": 103, "author": {"login": "copilot-pull-request-reviewer"}, "path": "b.md", "line": 7, "body": "head three\nsecond line"}]}},
  {"isResolved": true, "isOutdated": true, "comments": {"totalCount": 2, "nodes": [
    {"databaseId": 104, "author": {"login": "copilot-pull-request-reviewer"}, "path": "c.md", "line": null, "body": "head\tfour"}]}},
  {"isResolved": false, "isOutdated": false, "comments": {"totalCount": 1, "nodes": [
    {"databaseId": 105, "author": {"login": "someone"}, "path": "d.md", "line": 1, "body": "human head"}]}},
  {"isResolved": false, "isOutdated": false, "comments": {"totalCount": 2, "nodes": [
    {"databaseId": 106, "author": {"login": "copilot-pull-request-reviewer"}, "path": "e.md", "line": 2, "body": "head six"}]}}
]}}}}}
JSON

# The same pull request's review comments, oldest first: the six heads, then
# the five replies. The last three replies fall past the first 8.
cat >"$tmpdir/comments.json" <<'JSON'
[
  {"id": 101, "user": {"login": "Copilot"}, "pull_request_review_id": 10, "in_reply_to_id": null, "path": "a.md", "line": 3, "body": "head one"},
  {"id": 102, "user": {"login": "Copilot"}, "pull_request_review_id": 10, "in_reply_to_id": null, "path": "a.md", "line": null, "body": "head two"},
  {"id": 103, "user": {"login": "Copilot"}, "pull_request_review_id": 20, "in_reply_to_id": null, "path": "b.md", "line": 7, "body": "head three\nsecond line"},
  {"id": 104, "user": {"login": "Copilot"}, "pull_request_review_id": 20, "in_reply_to_id": null, "path": "c.md", "line": null, "body": "head\tfour"},
  {"id": 105, "user": {"login": "someone"}, "pull_request_review_id": 15, "in_reply_to_id": null, "path": "d.md", "line": 1, "body": "human head"},
  {"id": 106, "user": {"login": "Copilot"}, "pull_request_review_id": 20, "in_reply_to_id": null, "path": "e.md", "line": 2, "body": "head six"},
  {"id": 201, "user": {"login": "someone"}, "pull_request_review_id": 20, "in_reply_to_id": 102, "path": "a.md", "line": null, "body": "only reply"},
  {"id": 202, "user": {"login": "someone"}, "pull_request_review_id": 31, "in_reply_to_id": 103, "path": "b.md", "line": 7, "body": "first reply"},
  {"id": 203, "user": {"login": "someone"}, "pull_request_review_id": 32, "in_reply_to_id": 104, "path": "c.md", "line": null, "body": "reply on resolved"},
  {"id": 204, "user": {"login": "someone"}, "pull_request_review_id": 33, "in_reply_to_id": 106, "path": "e.md", "line": 2, "body": ""},
  {"id": 205, "user": {"login": "someone"}, "pull_request_review_id": 34, "in_reply_to_id": 103, "path": "b.md", "line": 7, "body": "second\treply\nwith \"quote\""}
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
check "list: no reply -> no bodies" "[]" "$(field 101 .reply_bodies)"
check "list: one reply -> its body" '["only reply"]' "$(field 102 .reply_bodies)"
check "list: two replies -> reply_count 2" "2" "$(field 103 .reply_count)"
check "list: two replies -> both bodies, oldest first" '["first reply","second\treply\nwith \"quote\""]' "$(field 103 .reply_bodies)"
check "list: resolved thread is listed" "true" "$(field 104 .resolved)"
check "list: a reply past the first 8 comments is read" '["reply on resolved"]' "$(field 104 .reply_bodies)"
check "list: empty reply -> an empty string" '[""]' "$(field 106 .reply_bodies)"

"$LIST" owner/repo 1 --unresolved >/dev/null 2>&1
check "list: an unknown flag is rejected" "2" "$?"

for call in /comments graphql; do
  out="$(STUB_FAIL="$call" "$LIST" owner/repo 1 2>/dev/null)"
  check "list: a failed $call read exits 1" "1" "$?"
  check "list: a failed $call read prints no thread" "" "$out"
done

# --- pr-with-copilot-review.sh --poll ---------------------------------------
poll="$(COPILOT_POLL_INITIAL=0 "$POLL" --poll https://github.com/owner/repo/pull/1 2>/dev/null)"
inline="$(awk 'found { print } /^=== Inline Comments ===$/ { found = 1 }' <<<"$poll")"
ids="$(awk -F'\t' '/^[0-9]+\t/ { print $1 }' <<<"$inline")"

check "poll: latest Copilot review's summary" "latest summary" "$(awk '/^=== Review Summary ===$/ { getline; print; exit }' <<<"$poll")"
check "poll: one id-led line per Copilot comment of the latest review" "103 104 106" "$(paste -sd' ' - <<<"$ids")"
check "poll: a comment starts with id, path:line, body" $'103\tb.md:7\thead three' "$(awk 'NR == 1' <<<"$inline")"
check "poll: a body's later lines follow as printed" "second line" "$(awk 'NR == 2' <<<"$inline")"
check "poll: null line is printed as null" $'104\tc.md:null\thead\tfour' "$(awk 'NR == 3' <<<"$inline")"
check "poll: each printed id is a head_id of the listing" "103 104 106" "$(jq -r .head_id <<<"$threads" | grep -Fxf <(printf '%s\n' "$ids") | paste -sd' ' -)"

echo
if ((fails == 0)); then
  echo "All checks passed."
else
  echo "$fails check(s) failed."
  exit 1
fi
