#!/usr/bin/env bash
# Contract test for the output of list-pr-threads.sh, of
# pr-with-copilot-review.sh's poll, and of the replies reply-threads.sh posts.
#
# Requires jq, and gh-post on PATH: reply-threads.sh is run through the real
# gh-post, with gh stubbed beneath it.
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
# A reply POST appends {url, body} to $RECORD, read from its --input file.
[[ -n "${STUB_FAIL:-}" && "$*" == *"$STUB_FAIL"* ]] && exit 1
filter=""
url=""
input=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  [[ "${args[i]}" == "--jq" ]] && filter="${args[i + 1]}"
  [[ "${args[i]}" == "--input" ]] && input="${args[i + 1]}"
  [[ "${args[i]}" == repos/* ]] && url="${args[i]}"
done
if [[ "$url" == */replies ]]; then
  jq -c --arg url "$url" '{url: $url, body}' "$input" >>"$RECORD"
  exit 0
fi
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

# A pull request whose Copilot threads carry the given replies: one JSON
# object per thread, {"head": <id>, "replies": [<body>]}, read from stdin into
# fixture directory $1.
make_pr() {
  local dir="$1" spec
  spec="$(jq -sc .)"
  mkdir -p "$dir"
  cp "$tmpdir/reviews.json" "$dir/"
  jq -n --argjson spec "$spec" '
    [$spec[] | {id: .head, user: {login: "Copilot"}, pull_request_review_id: 20, in_reply_to_id: null, path: "m.md", line: 1, body: "head"}]
    + [$spec[] | .head as $h | .replies | to_entries[] | {id: ($h * 100 + .key), user: {login: "someone"}, pull_request_review_id: 31, in_reply_to_id: $h, path: "m.md", line: 1, body: .value}]
  ' >"$dir/comments.json"
  jq -n --argjson spec "$spec" '
    {data: {repository: {pullRequest: {reviewThreads: {nodes: [$spec[] | {isResolved: false, isOutdated: false, comments: {totalCount: (1 + (.replies | length)), nodes: [{databaseId: .head, author: {login: "copilot-pull-request-reviewer"}, path: "m.md", line: 1, body: "head"}]}}]}}}}}
  ' >"$dir/threads.json"
}

# Each case: head id, its replies, the disposition the listing must report.
marker_cases='
[301, [], null, "no reply"]
[302, ["`defer` — later.\n\n<!-- disposition: defer -->"], "defer", "a marked reply"]
[303, ["`defer` — later.\n\n<!-- disposition: defer -->", "is this not a `false-positive`?"], "defer", "a later hand-written slug mention"]
[304, ["`defer` — later.\n\n<!-- disposition: defer -->", "`wontfix` — no.\n\n<!-- disposition: wontfix -->"], "wontfix", "the latest of two marked replies"]
[305, ["> quoted\n> <!-- disposition: defer -->"], null, "a quoted marker"]
[306, ["x\n\n<!-- disposition: defer --> and more"], null, "a marker with trailing text"]
[307, ["<!-- disposition: defer -->\n\nthen text"], null, "a marker not on the last line"]
[308, ["x\n\n<!-- disposition: invariant-premise-check -->\n\n\n"], "invariant-premise-check", "a marker followed by blank lines"]
[309, ["x\r\n\r\n<!-- disposition: defer -->\r\n"], "defer", "a marker in a CRLF body"]
[310, ["x\n\n<!-- disposition: Defer -->"], null, "a malformed slug"]
[311, ["x\n\n<!-- disposition: de--fer -->"], null, "a slug with a doubled hyphen"]
'
jq -c '{head: .[0], replies: .[1]}' <<<"$marker_cases" | make_pr "$tmpdir/marked"
out="$(FIXTURES="$tmpdir/marked" "$LIST" owner/repo 1)"
while IFS= read -r case; do
  head="$(jq -r '.[0]' <<<"$case")"
  check "list: disposition, $(jq -r '.[3]' <<<"$case")" "$(jq -c '.[2]' <<<"$case")" "$(jq -c "select(.head_id == $head) | .disposition" <<<"$out")"
done < <(jq -c . <<<"$marker_cases")

# --- reply-threads.sh -------------------------------------------------------
REPLY="$SCRIPT_DIR/reply-threads.sh"
export RECORD="$tmpdir/record.jsonl"
post() { : >"$RECORD"; "$REPLY" owner/repo 1 2>/dev/null; }
posted() { jq -r "select(.url | endswith(\"/comments/$1/replies\")) | .body" "$RECORD"; }

printf '%s\n' \
  '{"id": 401, "disposition": "defer", "body": "tracked as a follow-up.  "}' \
  '' \
  '{"id": 402, "disposition": "false-positive", "body": "see note[^1] [^1]: not a definition, a `#` and a > mid-line"}' \
  '{"id": 403, "disposition": "wontfix", "body": "``` not a fence, [ref]: https://example.org"}' \
  | post
check "reply: a valid batch exits 0" "0" "$?"
check "reply: one post per line, blank lines skipped" "3" "$(wc -l <"$RECORD" | tr -d ' ')"
check "reply: slug in front, marker last" $'`defer` — tracked as a follow-up.\n\n<!-- disposition: defer -->' "$(posted 401)"
for id in 402 403; do
  check "reply: the formatted body $id still ends in its marker" \
    "$(jq -r "select(.id == $id) | \"<!-- disposition: \(.disposition) -->\"" <<<'{"id":402,"disposition":"false-positive"} {"id":403,"disposition":"wontfix"}')" \
    "$(posted $id | tail -n 1)"
done

# Round trip: what was posted lists with the disposition it was sent with.
jq -c '{head: (.url | capture("/comments/(?<h>[0-9]+)/").h | tonumber), replies: [.body]}' "$RECORD" | make_pr "$tmpdir/posted"
check "reply: posted replies list with their dispositions" "401 defer 402 false-positive 403 wontfix" \
  "$(FIXTURES="$tmpdir/posted" "$LIST" owner/repo 1 | jq -r '"\(.head_id) \(.disposition)"' | paste -sd' ' -)"

while IFS= read -r line; do
  printf '%s\n' '{"id": 401, "disposition": "defer", "body": "fine"}' "$line" | post
  check "reply: invalid line $line exits 2" "2" "$?"
  check "reply: invalid line $line sends nothing" "0" "$(wc -l <"$RECORD" | tr -d ' ')"
done <<'LINES'
not json
{"id": 1, "body": "an old-shape line"}
{"id": 0, "disposition": "defer", "body": "x"}
{"id": -1, "disposition": "defer", "body": "x"}
{"id": 1.0, "disposition": "defer", "body": "x"}
{"id": "1", "disposition": "defer", "body": "x"}
{"id": true, "disposition": "defer", "body": "x"}
{"id": 1, "disposition": "Defer", "body": "x"}
{"id": 1, "disposition": "defer-", "body": "x"}
{"id": 1, "disposition": "defer", "body": ""}
{"id": 1, "disposition": "defer", "body": "   "}
{"id": 1, "disposition": "defer", "body": 7}
{"id": 1, "disposition": "defer", "body": "two\nlines"}
{"id": 1, "disposition": "defer", "body": "two\rlines"}
{"id": 1, "disposition": "defer", "body": "two\r\nlines"}
{"id": 1, "disposition": "defer", "body": "hidden <!-- text"}
{"id": 1, "disposition": "defer", "body": "x"} {"id": 2, "disposition": "defer", "body": "y"}
LINES

: | post
check "reply: empty input exits 0" "0" "$?"

printf '%s\n' \
  '{"id": 401, "disposition": "defer", "body": "one."}' \
  '{"id": 402, "disposition": "defer", "body": "two."}' \
  '{"id": 403, "disposition": "defer", "body": "three."}' \
  | STUB_FAIL=/comments/402/replies post
check "reply: a failed send propagates gh's status" "1" "$?"
jq -nc '{head: 401}, {head: 402}, {head: 403}' \
  | jq -c --slurpfile rec "$RECORD" '.head as $h | {head: $h, replies: [$rec[] | select(.url | endswith("/comments/\($h)/replies")) | .body]}' \
  | make_pr "$tmpdir/partial"
check "reply: after a failed send, the sent thread is settled and the rest stay due" "401 defer 402 null 403 null" \
  "$(FIXTURES="$tmpdir/partial" "$LIST" owner/repo 1 | jq -r '"\(.head_id) \(.disposition)"' | paste -sd' ' -)"

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
