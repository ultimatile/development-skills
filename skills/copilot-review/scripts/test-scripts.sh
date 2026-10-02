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
# A list read without --paginate gets the first 4 entries.
[[ -n "${STUB_FAIL:-}" && "$*" == *"$STUB_FAIL"* ]] && exit 1
filter=""
url=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  [[ "${args[i]}" == "--jq" ]] && filter="${args[i + 1]}"
  [[ "${args[i]}" == repos/* ]] && url="${args[i]}"
done
page=""
[[ " $* " == *" --paginate "* ]] || page=".[0:4] | "
case "$*" in
  "api graphql"*) fixture="$FIXTURES/threads.json"; page="" ;;
  *"/reviews/"[0-9]*) fixture="$FIXTURES/reviews.json"; page=".[] | select(.id == ${url##*/}) | " ;;
  *"/reviews"*)   fixture="$FIXTURES/reviews.json" ;;
  *"/comments"*)  fixture="$FIXTURES/comments.json" ;;
  *) echo "stub gh: unexpected call: $*" >&2; exit 97 ;;
esac
jq -r "$page$filter" "$fixture"
STUB
chmod +x "$tmpdir/bin/gh"

export FIXTURES="$tmpdir"
export PATH="$tmpdir/bin:$PATH"

# One pull request, as each API returns it, oldest first. Copilot reviewed it
# twice (reviews 10 and 20) and someone else once (15); the other reviews are
# the ones GitHub records for replies. Only the first 4 reviews and the first 4
# comments are on the first page.
cat >"$tmpdir/reviews.json" <<'JSON'
[
  {"id": 10, "user": {"login": "copilot-pull-request-reviewer[bot]"}, "body": "older summary"},
  {"id": 15, "user": {"login": "someone"}, "body": "human review"},
  {"id": 16, "user": {"login": "someone"}, "body": ""},
  {"id": 17, "user": {"login": "someone"}, "body": ""},
  {"id": 18, "user": {"login": "someone"}, "body": ""},
  {"id": 20, "user": {"login": "copilot-pull-request-reviewer[bot]"}, "body": "latest summary"},
  {"id": 31, "user": {"login": "someone"}, "body": ""},
  {"id": 32, "user": {"login": "someone"}, "body": ""}
]
JSON

# Review 10 left threads 101-104, review 15 thread 105, review 20 threads 106
# and 107. The rest are replies.
cat >"$tmpdir/comments.json" <<'JSON'
[
  {"id": 101, "user": {"login": "Copilot"}, "pull_request_review_id": 10, "in_reply_to_id": null, "path": "a.md", "line": 3, "body": "head one"},
  {"id": 102, "user": {"login": "Copilot"}, "pull_request_review_id": 10, "in_reply_to_id": null, "path": "a.md", "line": null, "body": "head two"},
  {"id": 103, "user": {"login": "Copilot"}, "pull_request_review_id": 10, "in_reply_to_id": null, "path": "c.md", "line": 4, "body": "head three"},
  {"id": 104, "user": {"login": "Copilot"}, "pull_request_review_id": 10, "in_reply_to_id": null, "path": "e.md", "line": 2, "body": "head four"},
  {"id": 105, "user": {"login": "someone"}, "pull_request_review_id": 15, "in_reply_to_id": null, "path": "d.md", "line": 1, "body": "human head"},
  {"id": 201, "user": {"login": "someone"}, "pull_request_review_id": 16, "in_reply_to_id": 102, "path": "a.md", "line": null, "body": "first reply"},
  {"id": 202, "user": {"login": "someone"}, "pull_request_review_id": 17, "in_reply_to_id": 103, "path": "c.md", "line": 4, "body": "reply on resolved"},
  {"id": 203, "user": {"login": "someone"}, "pull_request_review_id": 18, "in_reply_to_id": 104, "path": "e.md", "line": 2, "body": ""},
  {"id": 106, "user": {"login": "Copilot"}, "pull_request_review_id": 20, "in_reply_to_id": null, "path": "b.md", "line": 7, "body": "head six\nsecond line"},
  {"id": 107, "user": {"login": "Copilot"}, "pull_request_review_id": 20, "in_reply_to_id": null, "path": "c.md", "line": null, "body": "head\tseven"},
  {"id": 204, "user": {"login": "someone"}, "pull_request_review_id": 31, "in_reply_to_id": 102, "path": "a.md", "line": null, "body": "second\treply\nwith \"quote\""},
  {"id": 205, "user": {"login": "someone"}, "pull_request_review_id": 32, "in_reply_to_id": 106, "path": "b.md", "line": 7, "body": "only reply"}
]
JSON

# The same threads. Thread 103 is resolved.
cat >"$tmpdir/threads.json" <<'JSON'
{"data": {"repository": {"pullRequest": {"reviewThreads": {"nodes": [
  {"isResolved": false, "isOutdated": false, "comments": {"totalCount": 1, "nodes": [
    {"databaseId": 101, "author": {"login": "copilot-pull-request-reviewer"}, "path": "a.md", "line": 3, "body": "head one"}]}},
  {"isResolved": false, "isOutdated": true, "comments": {"totalCount": 3, "nodes": [
    {"databaseId": 102, "author": {"login": "copilot-pull-request-reviewer"}, "path": "a.md", "line": null, "body": "head two"}]}},
  {"isResolved": true, "isOutdated": false, "comments": {"totalCount": 2, "nodes": [
    {"databaseId": 103, "author": {"login": "copilot-pull-request-reviewer"}, "path": "c.md", "line": 4, "body": "head three"}]}},
  {"isResolved": false, "isOutdated": false, "comments": {"totalCount": 2, "nodes": [
    {"databaseId": 104, "author": {"login": "copilot-pull-request-reviewer"}, "path": "e.md", "line": 2, "body": "head four"}]}},
  {"isResolved": false, "isOutdated": false, "comments": {"totalCount": 1, "nodes": [
    {"databaseId": 105, "author": {"login": "someone"}, "path": "d.md", "line": 1, "body": "human head"}]}},
  {"isResolved": false, "isOutdated": false, "comments": {"totalCount": 2, "nodes": [
    {"databaseId": 106, "author": {"login": "copilot-pull-request-reviewer"}, "path": "b.md", "line": 7, "body": "head six\nsecond line"}]}},
  {"isResolved": false, "isOutdated": true, "comments": {"totalCount": 1, "nodes": [
    {"databaseId": 107, "author": {"login": "copilot-pull-request-reviewer"}, "path": "c.md", "line": null, "body": "head\tseven"}]}}
]}}}}}
JSON

# The same pull request before any reply, and one with no Copilot review.
mkdir "$tmpdir/unreplied" "$tmpdir/unreviewed"
cp "$tmpdir/reviews.json" "$tmpdir/unreplied/"
jq 'map(select(.in_reply_to_id == null))' "$tmpdir/comments.json" >"$tmpdir/unreplied/comments.json"
jq '.data.repository.pullRequest.reviewThreads.nodes |= map(.comments.totalCount = 1)' "$tmpdir/threads.json" >"$tmpdir/unreplied/threads.json"
jq 'map(select(.id == 15))' "$tmpdir/reviews.json" >"$tmpdir/unreviewed/reviews.json"
jq 'map(select(.id == 105))' "$tmpdir/comments.json" >"$tmpdir/unreviewed/comments.json"
jq '.data.repository.pullRequest.reviewThreads.nodes |= map(select(.comments.nodes[0].databaseId == 105))' "$tmpdir/threads.json" >"$tmpdir/unreviewed/threads.json"

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

check "list: head ids, other-headed thread dropped" "101 102 103 104 106 107" "$(jq -r .head_id <<<"$threads" | paste -sd' ' -)"
check "list: no reply -> reply_count 0" "0" "$(field 101 .reply_count)"
check "list: no reply -> no bodies" "[]" "$(field 101 .reply_bodies)"
check "list: two replies -> reply_count 2" "2" "$(field 102 .reply_count)"
check "list: two replies -> both bodies, oldest first" '["first reply","second\treply\nwith \"quote\""]' "$(field 102 .reply_bodies)"
check "list: resolved thread is listed" "true" "$(field 103 .resolved)"
check "list: resolved thread carries its reply" '["reply on resolved"]' "$(field 103 .reply_bodies)"
check "list: empty reply -> an empty string" '[""]' "$(field 104 .reply_bodies)"
check "list: one reply -> its body" '["only reply"]' "$(field 106 .reply_bodies)"

out="$(FIXTURES="$tmpdir/unreplied" "$LIST" owner/repo 1)"
check "list: no reply on the pull request -> exit 0" "0" "$?"
check "list: no reply on the pull request -> every thread, no bodies" "6 []" "$(wc -l <<<"$out" | tr -d ' ') $(jq -c .reply_bodies <<<"$out" | sort -u)"

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
check "poll: one id-led line per Copilot comment of the latest review" "106 107" "$(paste -sd' ' - <<<"$ids")"
check "poll: a comment starts with id, path:line, body" $'106\tb.md:7\thead six' "$(awk 'NR == 1' <<<"$inline")"
check "poll: a body's later lines follow as printed" "second line" "$(awk 'NR == 2' <<<"$inline")"
check "poll: null line is printed as null" $'107\tc.md:null\thead\tseven' "$(awk 'NR == 3' <<<"$inline")"
check "poll: each printed id is a head_id of the listing" "106 107" "$(jq -r .head_id <<<"$threads" | grep -Fxf <(printf '%s\n' "$ids") | paste -sd' ' -)"

out="$(FIXTURES="$tmpdir/unreviewed" COPILOT_POLL_INITIAL=0 COPILOT_POLL_ATTEMPTS=1 "$POLL" --poll https://github.com/owner/repo/pull/1 2>/dev/null)"
check "poll: no Copilot review -> exit 1" "1" "$?"
check "poll: no Copilot review -> prints nothing" "" "$out"

out="$(STUB_FAIL=/reviews COPILOT_POLL_INITIAL=0 COPILOT_POLL_ATTEMPTS=1 "$POLL" --poll https://github.com/owner/repo/pull/1 2>/dev/null)"
check "poll: a failed /reviews read -> exit 1" "1" "$?"
check "poll: a failed /reviews read -> prints nothing" "" "$out"

echo
if ((fails == 0)); then
  echo "All checks passed."
else
  echo "$fails check(s) failed."
  exit 1
fi
