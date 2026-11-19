#!/usr/bin/env bash
# Contract test for run-codex.sh, with a stub codex on PATH.
#
# The stub records its argv and stdin, writes the -o result as STUB_RESULT
# directs, feeds each line of STUB_PAYLOADS to the hook command it was given,
# and exits STUB_EXIT.
#
# Requires jq and rg.
#
# Run:
#   bash test-run-codex.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RUN="$SCRIPT_DIR/run-codex.sh"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT
mkdir "$tmpdir/bin"

cat >"$tmpdir/bin/codex" <<'STUB'
#!/usr/bin/env bash
# STUB_RESULT: "absent" writes no result, "empty" an empty one, anything else is the content.
printf '%s\n' "$@" >"$RECORD/argv"
cat >"$RECORD/stdin"
out=""
cmd=""
args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do
  [[ "${args[i]}" == "-o" ]] && out="${args[i + 1]}"
  if [[ "${args[i]}" == "-c" && "${args[i + 1]}" =~ command=\"(.*)\"\}\]\}\]$ ]]; then
    cmd="${BASH_REMATCH[1]}"
  fi
done
if [[ -n "${STUB_PAYLOADS:-}" ]]; then
  while IFS= read -r payload; do
    printf '%s' "$payload" | sh -c "$cmd"
  done <<<"$STUB_PAYLOADS"
fi
case "${STUB_RESULT:-absent}" in
absent) ;;
empty) : >"$out" ;;
*) printf '%s' "$STUB_RESULT" >"$out" ;;
esac
echo "stub stdout"
echo "stub stderr" >&2
exit "${STUB_EXIT:-0}"
STUB
chmod +x "$tmpdir/bin/codex"

cat >"$tmpdir/schema.json" <<'EOF'
{"type":"object","required":["verdict","findings"],"properties":{"verdict":{"type":"string"},"findings":{"type":"array"}}}
EOF

P="$tmpdir/prompt"
printf 'p' >"$P"

export PATH="$tmpdir/bin:$PATH"
export RECORD="$tmpdir/record"
export TMPDIR="$tmpdir/runs"
mkdir "$TMPDIR"

fail=0
out=""
code=0

# run <args...>: run run-codex.sh with a fresh record directory; sets $out and $code.
run() {
  rm -rf "$RECORD"
  mkdir "$RECORD"
  out="$("$RUN" "$@" 2>"$tmpdir/stderr")"
  code=$?
}

field() {
  printf '%s\n' "$out" | rg -o --replace '$1' "^$1: (.*)$"
}

expect() {
  local name="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    echo "ok   $name"
  else
    echo "FAIL $name: got [$got], want [$want]"
    fail=1
  fi
}

completed='{"model":"m1","hook_event_name":"PostModelRequest","status":"completed"}'

STUB_EXIT=1 STUB_RESULT='{"verdict":"approve","findings":[]}' run prompt "$P"
expect "nonzero exit -> failed" "$(field status)" "failed"
expect "nonzero exit -> script exit 1" "$code" "1"

STUB_EXIT=1 STUB_RESULT=absent run prompt "$P"
expect "nonzero exit without result -> failed" "$(field status)" "failed"

STUB_EXIT=1 STUB_RESULT='not json' run prompt --schema "$tmpdir/schema.json" "$P"
expect "nonzero exit with invalid result -> failed" "$(field status)" "failed"

STUB_RESULT=absent run prompt "$P"
expect "no result -> missing-result" "$(field status)" "missing-result"
expect "missing-result -> script exit 1" "$code" "1"

STUB_RESULT=empty run prompt --schema "$tmpdir/schema.json" "$P"
expect "empty result with schema -> missing-result" "$(field status)" "missing-result"

STUB_RESULT='not json' run prompt --schema "$tmpdir/schema.json" "$P"
expect "non-JSON result -> invalid-result" "$(field status)" "invalid-result"
expect "invalid-result -> script exit 1" "$code" "1"

STUB_RESULT='{"verdict":"approve"}' run prompt --schema "$tmpdir/schema.json" "$P"
expect "missing required key -> invalid-result" "$(field status)" "invalid-result"

STUB_RESULT='["verdict","findings"]' run prompt --schema "$tmpdir/schema.json" "$P"
expect "non-object JSON -> invalid-result" "$(field status)" "invalid-result"

STUB_RESULT='"x" {"verdict":"approve","findings":[]}' run prompt --schema "$tmpdir/schema.json" "$P"
expect "two JSON values -> invalid-result" "$(field status)" "invalid-result"

STUB_RESULT='{"verdict":"approve","findings":[]}' run prompt --schema "$tmpdir/schema.json" "$P"
expect "conforming result -> completed" "$(field status)" "completed"
expect "completed -> script exit 0" "$code" "0"
dir="$(dirname "$(field result)")"
hook="hooks.PostModelRequest=[{hooks=[{type=\"command\",command=\"cat >> '$dir/requests.jsonl'\"}]}]"
expect "prompt argv" "$(tr '\n' '|' <"$RECORD/argv")" \
  "exec|--ephemeral|-o|$dir/result|-c|$hook|--output-schema|$tmpdir/schema.json|-|"
expect "run directory is under TMPDIR" "$(dirname "$dir")" "$TMPDIR"

STUB_RESULT='prose review' run prompt "$P"
expect "prose result without schema -> completed" "$(field status)" "completed"
expect "no schema flag without --schema" "$(rg -c -x -- '--output-schema' "$RECORD/argv" || true)" ""

STUB_RESULT=x STUB_PAYLOADS="$completed"$'\n'"$completed" run prompt "$P"
expect "completed payloads naming m1 -> model m1" "$(field model)" "m1"

STUB_RESULT=x run prompt "$P"
expect "no payload -> model unknown" "$(field model)" "unknown"

STUB_RESULT=x STUB_PAYLOADS='{"model":"m1","hook_event_name":"PostModelRequest","status":"failed"}' run prompt "$P"
expect "only a non-completed payload -> model unknown" "$(field model)" "unknown"

STUB_RESULT=x STUB_PAYLOADS="$completed"$'\n''{"model":"m2","hook_event_name":"PostModelRequest","status":"completed"}' run prompt "$P"
expect "two models -> model unknown" "$(field model)" "unknown"

STUB_RESULT=x STUB_PAYLOADS='{"model":"m2","hook_event_name":"PreModelRequest","status":"completed"}'$'\n'"$completed" run prompt "$P"
expect "other hook events ignored" "$(field model)" "m1"

STUB_RESULT=x STUB_PAYLOADS='{"model":null,"hook_event_name":"PostModelRequest","status":"completed"}'$'\n'"$completed" run prompt "$P"
expect "non-string model ignored" "$(field model)" "m1"

printf '{"type":"object"}' >"$tmpdir/norequired.json"
STUB_RESULT='{}' run prompt --schema "$tmpdir/norequired.json" "$P"
expect "schema without required -> completed" "$(field status)" "completed"

printf '%s' '-m reply `ok` "$HOME"' >"$tmpdir/dash-prompt"
STUB_RESULT=x run prompt "$tmpdir/dash-prompt" <<<"piped data"
expect "prompt file reaches codex stdin verbatim" "$(cat "$RECORD/stdin")" '-m reply `ok` "$HOME"'
expect "prompt stays out of argv" "$(tail -1 "$RECORD/argv")" "-"

STUB_RESULT=x run review --base X
result_path="$(field result)"
dir="$(dirname "$result_path")"
hook="hooks.PostModelRequest=[{hooks=[{type=\"command\",command=\"cat >> '$dir/requests.jsonl'\"}]}]"
expect "review argv" "$(tr '\n' '|' <"$RECORD/argv")" \
  "exec|review|--ephemeral|-o|$dir/result|-c|$hook|--base|X|"
expect "log holds stdout and stderr" "$(tr '\n' '|' <"$(field log)")" "stub stdout|stub stderr|"
expect "stdout is the four lines" "$(printf '%s\n' "$out" | cut -d: -f1 | tr '\n' '|')" "status|model|result|log|"

STUB_RESULT=x run review --base X <<<"piped data"
expect "review: codex reads nothing on stdin" "$(wc -c <"$RECORD/stdin" | tr -d ' ')" "0"

# expect_not_run <name>: the last run did not run codex, exited 2, printed no
# status lines, and gave a reason on stderr.
expect_not_run() {
  expect "$1 -> exit 2" "$code" "2"
  expect "$1 -> codex not run" "$([[ -e "$RECORD/argv" ]] && echo ran || echo not-run)" "not-run"
  expect "$1 -> no status lines" "$out" ""
  expect "$1 -> reason on stderr" "$([[ -s "$tmpdir/stderr" ]] && echo reason || echo silent)" "reason"
}

for usage_case in "bogus p" "" "prompt" "prompt p q" "prompt --schema" "review" "review --schema F --base X"; do
  run $usage_case # unquoted: each case splits into its arguments
  expect_not_run "usage [$usage_case]"
done

mkdir "$tmpdir/nojq"
for tool in bash cat mktemp; do ln -s "$(command -v "$tool")" "$tmpdir/nojq/$tool"; done
ln -s "$tmpdir/bin/codex" "$tmpdir/nojq/codex"
rm -rf "$RECORD"
mkdir "$RECORD"
out="$(STUB_RESULT=x PATH="$tmpdir/nojq" "$RUN" prompt "$P" 2>"$tmpdir/stderr")"
code=$?
expect_not_run "no jq"
expect "no jq -> stderr names jq" "$(cat "$tmpdir/stderr")" "run-codex.sh: jq is required"

mkdir "$tmpdir/nocodex"
for tool in bash cat mktemp; do ln -s "$(command -v "$tool")" "$tmpdir/nocodex/$tool"; done
ln -s "$(command -v jq)" "$tmpdir/nocodex/jq"
rm -rf "$RECORD"
mkdir "$RECORD"
out="$(PATH="$tmpdir/nocodex" "$RUN" prompt "$P" 2>"$tmpdir/stderr")"
code=$?
expect_not_run "no codex"
expect "no codex -> stderr names codex" "$(cat "$tmpdir/stderr")" "run-codex.sh: codex is required"

TMPDIR="$tmpdir/missing" run prompt "$P"
expect_not_run "no run directory"

run prompt "$tmpdir/no-such-prompt"
expect_not_run "unreadable prompt file"

printf 'not json' >"$tmpdir/broken-schema.json"
run prompt --schema "$tmpdir/broken-schema.json" "$P"
expect_not_run "unreadable schema"

printf '[]' >"$tmpdir/array-schema.json"
run prompt --schema "$tmpdir/array-schema.json" "$P"
expect_not_run "non-object schema"

STUB_RESULT=x run prompt "$P"
first="$(field result)"
STUB_RESULT=x run prompt "$P"
expect "two runs use different result paths" "$([[ "$first" != "$(field result)" ]] && echo distinct || echo same)" "distinct"

exit "$fail"
