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

STUB_EXIT=1 STUB_RESULT='{"verdict":"approve","findings":[]}' run prompt "p"
expect "nonzero exit -> failed" "$(field status)" "failed"
expect "nonzero exit -> script exit 1" "$code" "1"

STUB_RESULT=absent run prompt "p"
expect "no result -> missing-result" "$(field status)" "missing-result"
expect "missing-result -> script exit 1" "$code" "1"

STUB_RESULT=empty run prompt --schema "$tmpdir/schema.json" "p"
expect "empty result with schema -> missing-result" "$(field status)" "missing-result"

STUB_RESULT='not json' run prompt --schema "$tmpdir/schema.json" "p"
expect "non-JSON result -> invalid-result" "$(field status)" "invalid-result"
expect "invalid-result -> script exit 1" "$code" "1"

STUB_RESULT='{"verdict":"approve"}' run prompt --schema "$tmpdir/schema.json" "p"
expect "missing required key -> invalid-result" "$(field status)" "invalid-result"

STUB_RESULT='["verdict","findings"]' run prompt --schema "$tmpdir/schema.json" "p"
expect "non-object JSON -> invalid-result" "$(field status)" "invalid-result"

STUB_RESULT='{"verdict":"approve","findings":[]}' run prompt --schema "$tmpdir/schema.json" "p"
expect "conforming result -> completed" "$(field status)" "completed"
expect "completed -> script exit 0" "$code" "0"
expect "schema passed to codex" "$(rg -c -x -- '--output-schema' "$RECORD/argv")" "1"
expect "schema path follows the flag" \
  "$(rg -A1 -x -- '--output-schema' "$RECORD/argv" | tail -1)" "$tmpdir/schema.json"

STUB_RESULT='prose review' run prompt "p"
expect "prose result without schema -> completed" "$(field status)" "completed"
expect "no schema flag without --schema" "$(rg -c -x -- '--output-schema' "$RECORD/argv" || true)" ""

STUB_RESULT=x STUB_PAYLOADS="$completed"$'\n'"$completed" run prompt "p"
expect "completed payloads naming m1 -> model m1" "$(field model)" "m1"

STUB_RESULT=x run prompt "p"
expect "no payload -> model unknown" "$(field model)" "unknown"

STUB_RESULT=x STUB_PAYLOADS='{"model":"m1","hook_event_name":"PostModelRequest","status":"failed"}' run prompt "p"
expect "only a non-completed payload -> model unknown" "$(field model)" "unknown"

STUB_RESULT=x STUB_PAYLOADS="$completed"$'\n''{"model":"m2","hook_event_name":"PostModelRequest","status":"completed"}' run prompt "p"
expect "two models -> model unknown" "$(field model)" "unknown"

STUB_RESULT=x run prompt "-m reply ok"
expect "prompt follows --" "$(tail -2 "$RECORD/argv" | tr '\n' '|')" "--|-m reply ok|"

STUB_RESULT=x run review --base X
result_path="$(field result)"
dir="$(dirname "$result_path")"
hook="hooks.PostModelRequest=[{hooks=[{type=\"command\",command=\"cat >> '$dir/requests.jsonl'\"}]}]"
expect "review argv" "$(tr '\n' '|' <"$RECORD/argv")" \
  "exec|review|--ephemeral|-o|$dir/result|-c|$hook|--base|X|"
expect "log holds stdout and stderr" "$(tr '\n' '|' <"$(field log)")" "stub stdout|stub stderr|"
expect "stdout is the four lines" "$(printf '%s\n' "$out" | cut -d: -f1 | tr '\n' '|')" "status|model|result|log|"

STUB_RESULT=x run prompt "p" <<<"piped data"
expect "codex reads nothing on stdin" "$(wc -c <"$RECORD/stdin" | tr -d ' ')" "0"

run bogus "p"
expect "unknown mode -> exit 2" "$code" "2"
expect "unknown mode -> codex not run" "$([[ -e "$RECORD/argv" ]] && echo ran || echo not-run)" "not-run"

run review --schema "$tmpdir/schema.json" --base X
expect "review --schema -> exit 2" "$code" "2"
expect "review --schema -> codex not run" "$([[ -e "$RECORD/argv" ]] && echo ran || echo not-run)" "not-run"

STUB_RESULT=x run prompt "p"
first="$(field result)"
STUB_RESULT=x run prompt "p"
expect "two runs use different result paths" "$([[ "$first" != "$(field result)" ]] && echo distinct || echo same)" "distinct"

exit "$fail"
