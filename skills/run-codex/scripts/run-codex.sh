#!/usr/bin/env bash
# Run codex exec non-interactively in a fresh directory and print four status lines:
# status, model, result, log. Exit 0 when the status is `completed`, 1 otherwise,
# 2 on a usage error.
#
#   run-codex.sh prompt [--schema <schema-file>] <prompt>
#   run-codex.sh review <review-target-arguments>...

set -uo pipefail

usage() {
  echo "usage: run-codex.sh prompt [--schema <schema-file>] <prompt>" >&2
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
  ;;
review)
  for arg in "$@"; do
    [[ "$arg" == "--schema" ]] && usage
  done
  ;;
*)
  usage
  ;;
esac

dir="$(mktemp -d)" || exit 1
result="$dir/result"
log="$dir/log"
requests="$dir/requests.jsonl"

# Codex pipes a JSON payload naming the model of each model request it makes into this hook.
hook="hooks.PostModelRequest=[{hooks=[{type=\"command\",command=\"cat >> '$requests'\"}]}]"

if [[ "$mode" == prompt ]]; then
  args=(exec --ephemeral -o "$result" -c "$hook")
  [[ -n "$schema" ]] && args+=(--output-schema "$schema")
  args+=(-- "$@")
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
  ! jq -e --slurpfile s "$schema" \
    'type == "object" and (. as $r | all($s[0].required[]?; . as $k | $r | has($k)))' \
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
