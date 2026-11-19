#!/usr/bin/env bash
# Run codex exec non-interactively with its output in a fresh directory, then print four status lines:
# status, model, result, log. Exit 0 when the status is `completed`, 1 for any other status,
# 2 without status lines when codex is not run.
#
#   run-codex.sh prompt [--schema <schema-file>] <prompt-file>
#   run-codex.sh review <review-target-arguments>...

set -uo pipefail

usage() {
  echo "usage: run-codex.sh prompt [--schema <schema-file>] <prompt-file>" >&2
  echo "       run-codex.sh review <review-target-arguments>..." >&2
  exit 2
}

mode="${1:-}"
[[ $# -gt 0 ]] && shift
schema=""
case "$mode" in
prompt)
  if [[ "${1:-}" == "--schema" ]]; then
    [[ $# -ge 2 ]] || usage
    schema="$2"
    shift 2
  fi
  [[ $# -eq 1 ]] || usage
  prompt="$(cat -- "$1")" || exit 2
  ;;
review)
  [[ $# -ge 1 ]] || usage
  for arg in "$@"; do
    [[ "$arg" == "--schema" ]] && usage
  done
  ;;
*)
  usage
  ;;
esac

for tool in codex jq; do
  command -v "$tool" >/dev/null || {
    echo "run-codex.sh: $tool is required" >&2
    exit 2
  }
done

dir="$(mktemp -d "${TMPDIR:-/tmp}/run-codex.XXXXXX")" || exit 2
result="$dir/result"
log="$dir/log"
requests="$dir/requests.jsonl"

# When Codex runs this hook, it pipes in a JSON payload naming the model of each model request.
hook="hooks.PostModelRequest=[{hooks=[{type=\"command\",command=\"cat >> '$requests'\"}]}]"

if [[ "$mode" == prompt ]]; then
  args=(exec --ephemeral -o "$result" -c "$hook")
  [[ -n "$schema" ]] && args+=(--output-schema "$schema")
  args+=(-- "$prompt")
else
  args=(exec review --ephemeral -o "$result" -c "$hook" "$@")
fi

codex "${args[@]}" </dev/null >"$log" 2>&1
rc=$?

if [[ $rc -ne 0 ]]; then
  status=failed
elif [[ ! -s "$result" ]]; then
  status=missing-result
elif [[ -n "$schema" ]] &&
  ! jq -se --slurpfile s "$schema" \
    'length == 1 and (.[0] | type == "object" and (. as $r | all($s[0].required[]?; . as $k | $r | has($k))))' \
    "$result" >/dev/null 2>&1; then
  status=invalid-result
else
  status=completed
fi

model="$(jq -rs '
  [.[] | select(.hook_event_name == "PostModelRequest" and .status == "completed") | .model | strings]
  | unique | if length == 1 then .[0] else "unknown" end' "$requests" 2>/dev/null)"
[[ -n "$model" ]] || model=unknown

printf 'status: %s\nmodel: %s\nresult: %s\nlog: %s\n' "$status" "$model" "$result" "$log"
[[ "$status" == completed ]]
