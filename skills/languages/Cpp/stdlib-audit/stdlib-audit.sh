#!/usr/bin/env bash
# stdlib-audit.sh — audit C++ source for known-bad standard library usage.
#
# Reads a TSV rule table and reports per-rule match counts and samples under
# the given search paths. Rule format: id<TAB>severity<TAB>regex<TAB>note.
# Add new checks by appending lines to the TSV — no code change needed.
#
# Exit 1 if any rule whose severity is in --fail-on has matches (for CI).
# Severity scale: crit > high > mid > low.

set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
RULES="$SCRIPT_DIR/stdlib-rules.tsv"
EXCLUDE_GLOB='**/external/**'
SAMPLES=5
FAIL_ON='crit,high'
RG_TYPE='cpp'

usage() {
  cat <<'EOF'
Usage: stdlib-audit.sh [OPTIONS] [PATH...]

Options:
  -r FILE   TSV rules file (default: stdlib-rules.tsv next to this script)
  -e GLOB   ripgrep exclude glob (default: **/external/**)
  -n N      detail samples per rule (default: 5)
  -f LIST   comma-separated severities that cause exit 1 (default: crit,high)
            use 'none' to never fail
  -t TYPE   ripgrep --type filter (default: cpp). Pass 'all' to disable.
  -h        show this help

Search paths default to '.' if none given.

Add a new rule by appending one TAB-separated line to the TSV:
  id<TAB>severity<TAB>rg-regex<TAB>one-line-note
EOF
}

while getopts ":r:e:n:f:t:h" opt; do
  case "$opt" in
    r) RULES=$OPTARG ;;
    e) EXCLUDE_GLOB=$OPTARG ;;
    n) SAMPLES=$OPTARG ;;
    f) FAIL_ON=$OPTARG ;;
    t) RG_TYPE=$OPTARG ;;
    h) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
shift $((OPTIND - 1))
[ "$#" -eq 0 ] && set -- .

case "$SAMPLES" in
  ''|*[!0-9]*) echo "error: -n requires a non-negative integer (got: $SAMPLES)" >&2; exit 2 ;;
esac

[ -f "$RULES" ] || { echo "rules file not found: $RULES" >&2; exit 2; }
command -v rg >/dev/null 2>&1 || { echo "ripgrep (rg) is required" >&2; exit 2; }

# Validate search paths upfront so a typo produces one error, not N per-rule
# rg warnings later that look like a TSV problem.
for _p in "$@"; do
  [ -e "$_p" ] || { echo "error: search path not found: $_p" >&2; exit 2; }
done
unset _p

if [ -t 1 ]; then
  C_CRIT=$'\033[1;31m'; C_HIGH=$'\033[31m'; C_MID=$'\033[33m'
  C_LOW=$'\033[2m';     C_BOLD=$'\033[1m';  C_RST=$'\033[0m'
else
  C_CRIT= C_HIGH= C_MID= C_LOW= C_BOLD= C_RST=
fi

sev_color() {
  case "$1" in
    crit) printf '%s' "$C_CRIT" ;;
    high) printf '%s' "$C_HIGH" ;;
    mid)  printf '%s' "$C_MID" ;;
    low)  printf '%s' "$C_LOW" ;;
    *)    printf '%s' '' ;;
  esac
}

# rg exit codes: 0 = matches, 1 = no matches, 2+ = real error (bad regex,
# IO failure). Treat 0/1 as success; surface 2+ as a per-rule warning so a
# broken appended pattern does not silently report 0 hits.
rule_count() {
  local pat=$1; shift
  local out rc=0
  out=$(rg -c -t "$RG_TYPE" -g "!$EXCLUDE_GLOB" -- "$pat" "$@" 2>/dev/null) || rc=$?
  if [ "$rc" -gt 1 ]; then
    # rg exit 2+ covers regex compile failures AND IO / permission / type
    # errors. Surface the pattern + exit code so the user can disambiguate
    # by re-running rg directly.
    echo "warning: rg exit $rc (invalid regex, bad target path, or IO error) for: $pat" >&2
    printf '__BAD__\n'; return 0
  fi
  printf '%s\n' "$out" | awk -F: '{ s += $NF } END { print s + 0 }'
}

rule_samples() {
  local pat=$1; shift
  local out rc=0
  [ "$SAMPLES" -eq 0 ] && return 0
  # `-H` forces path:line:content even when search target is a single file
  # (rg suppresses the filename in that case otherwise).
  out=$(rg -nH -t "$RG_TYPE" -g "!$EXCLUDE_GLOB" -- "$pat" "$@" 2>/dev/null) || rc=$?
  [ "$rc" -gt 1 ] && return 0
  # `|| true` absorbs SIGPIPE when head closes stdin before printf finishes
  # (pipefail would otherwise return 141 for large match sets).
  printf '%s\n' "$out" | head -n "$SAMPLES" || true
}

fail_set=",$FAIL_ON,"
total_hits=0
fail_hits=0
bad_rules=0
hit_rule_lines=()

printf '%s%-26s %-5s %6s  %s%s\n' "$C_BOLD" "ID" "SEV" "HITS" "NOTE" "$C_RST"
printf -- '------------------------------------------------------------------------------\n'

while IFS=$'\t' read -r id severity pattern note || [ -n "${id:-}" ]; do
  # Trim incidental whitespace from single-token fields. Trailing whitespace
  # in severity would otherwise silently disable the `-f` failure filter.
  # Trimming before the comment / empty check also lets indented comments
  # and whitespace-only lines be skipped silently.
  id="${id//[[:space:]]/}"
  severity="${severity//[[:space:]]/}"
  case "${id:-}" in ''|\#*) continue ;; esac
  # Require all 4 fields non-empty; missing note is treated as malformed
  # because the TSV format documents 4 columns and the note is part of the
  # report contract.
  if [ -z "${severity:-}" ] || [ -z "${pattern:-}" ] || [ -z "${note:-}" ]; then
    echo "warning: skipping malformed rule (need 4 non-empty TAB-separated fields): ${id:-<empty>}" >&2
    bad_rules=$((bad_rules + 1))
    continue
  fi
  case "$severity" in
    crit|high|mid|low) ;;
    *) echo "warning: skipping rule with invalid severity '$severity' (allowed: crit|high|mid|low): $id" >&2
       bad_rules=$((bad_rules + 1))
       continue ;;
  esac
  hits=$(rule_count "$pattern" "$@")
  if [ "$hits" = "__BAD__" ]; then
    bad_rules=$((bad_rules + 1))
    hits=0
  fi
  color=$(sev_color "$severity")
  printf '%s%-26s %-5s %6d%s  %s\n' "$color" "$id" "$severity" "$hits" "$C_RST" "$note"
  total_hits=$((total_hits + hits))
  case "$fail_set" in *",$severity,"*) fail_hits=$((fail_hits + hits)) ;; esac
  [ "$hits" -gt 0 ] && hit_rule_lines+=("$id"$'\t'"$severity"$'\t'"$pattern"$'\t'"$note")
done < "$RULES"

if [ "${#hit_rule_lines[@]}" -gt 0 ] && [ "$SAMPLES" -gt 0 ]; then
  echo
  printf '%s── details (max %d samples per rule) ──%s\n' "$C_BOLD" "$SAMPLES" "$C_RST"
  for line in "${hit_rule_lines[@]}"; do
    IFS=$'\t' read -r d_id d_sev d_pat d_note <<<"$line"
    color=$(sev_color "$d_sev")
    echo
    printf '%s[%s] %s%s\n' "$color" "$d_id" "$d_note" "$C_RST"
    rule_samples "$d_pat" "$@" | sed 's/^/  /'
  done
fi

echo
printf '%sSummary:%s total=%d  failing(%s)=%d  bad-rules=%d\n' \
       "$C_BOLD" "$C_RST" "$total_hits" "$FAIL_ON" "$fail_hits" "$bad_rules"

# Bad rules (regex that rg refused to compile) are always fatal regardless
# of -f, because the audit can no longer claim to have covered them.
if [ "$bad_rules" -gt 0 ]; then
  echo "fatal: $bad_rules rule(s) failed (invalid regex, bad path, or IO error) — see warnings above" >&2
  exit 2
fi
if [ "$FAIL_ON" != 'none' ] && [ "$fail_hits" -gt 0 ]; then
  exit 1
fi
exit 0
