#!/usr/bin/env bash
# Contract test for body-math-scan.sh's exit-code + detection contract.
#
# Zero-dependency harness: bash + rg only (the repo has no bash test framework,
# and this adds only enough to drive this one script). It runs the scan against
# crafted body fixtures and asserts the exit-code contract:
#   0 = clean, 1 = a forbidden Unicode glyph or macro found, 2 = usage / env error.
#
# A frozen reconstruction of the pre-fix Unicode-only regex is checked alongside
# the real assertions so the suite proves it guards the real regression — a body
# using \operatorname slipping through the gate — rather than just restating
# current behavior (see "non-tautology guard").
#
# Run:
#   bash test-body-math-scan.sh
#
# shellcheck disable=SC2016  # single-quoted fixture bodies hold literal LaTeX
#                            # (e.g. \operatorname); non-expansion is intentional.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN="$SCRIPT_DIR/body-math-scan.sh"

# Frozen reconstruction of the scanner's regex BEFORE \operatorname detection was
# added: the Unicode-codepoint class only, with no \operatorname alternative.
# FROZEN HISTORICAL ARTIFACT: do not extend it. It exists solely so the
# differential below can show a \operatorname-only body slipped through pre-fix.
PREFIX_REGEX='[\x{00B1}\x{00B2}\x{00B3}\x{00B9}\x{00D7}\x{00F7}\x{0370}-\x{03FF}\x{2070}-\x{209F}\x{2200}-\x{22FF}\x{2A00}-\x{2AFF}\x{2020}\x{2021}]'

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Write a body string to a temp file and echo its path.
mkfix() { local f; f="$(mktemp "$tmpdir/fx-XXXXXX")"; printf '%s\n' "$1" >"$f"; echo "$f"; }

# Exit code of the real scan on a body string.
scan_rc() { "$SCAN" "$(mkfix "$1")" >/dev/null 2>&1; echo "$?"; }

# Exit code of the frozen pre-fix Unicode-only regex on a body string, under the
# same 0=hit / 1=clean / 2=error flip the script applies to rg's status.
prefix_rc() {
  local f rc
  f="$(mkfix "$1")"
  rg -nP "$PREFIX_REGEX" "$f" >/dev/null 2>&1
  rc=$?
  case "$rc" in 0) echo 1 ;; 1) echo 0 ;; *) echo 2 ;; esac
}

fails=0
assert() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    printf 'ok   %-46s rc=%s\n' "$label" "$got"
  else
    printf 'FAIL %-46s want rc=%s got rc=%s\n' "$label" "$want" "$got"
    fails=$((fails + 1))
  fi
}

# --- Contract cases -------------------------------------------------------
assert "operatorname in math -> hit"         "$(scan_rc 'Define $`\operatorname{Tr}(A)`$.')"        1
assert "operatorname* in math -> hit"        "$(scan_rc 'See $`\operatorname*{argmin}_x`$.')"       1
assert "operatornamewithlimits -> clean"     "$(scan_rc 'Use $`\operatornamewithlimits{lim}`$.')"   0
assert "unicode glyph -> hit"                "$(scan_rc 'The angle is α here.')"                     1
assert "mathrm substitute -> clean"          "$(scan_rc 'Use `\mathrm{Tr}` for the trace.')"        0

# Environment error, source 1: a path that does not exist -> caught by the -f
# guard -> exit 2.
"$SCAN" "$tmpdir/does-not-exist.md" >/dev/null 2>&1
assert "missing file -> usage/env error"     "$?"                                                   2

# Environment error, source 2: a file that exists (passes the -f guard) but rg
# cannot read -> the rg-error branch maps to exit 2, a distinct exit-2 source.
# Skipped under root, where permission bits do not block reads.
if [[ "$(id -u)" -ne 0 ]]; then
  unreadable="$(mkfix 'unreadable body')"
  chmod 000 "$unreadable"
  "$SCAN" "$unreadable" >/dev/null 2>&1
  assert "unreadable file -> usage/env error" "$?"                                                  2
  chmod 644 "$unreadable" # restore so trap cleanup is unimpeded
else
  printf 'skip unreadable file -> usage/env error           (running as root)\n'
fi

# --- Non-tautology guard --------------------------------------------------
# A \operatorname-only body (no Unicode glyph) is where the pre-fix Unicode-only
# scanner and the fixed scanner diverge: pre-fix reports clean (the miss this
# change fixes), the fixed scanner reports a hit. Asserting both directions
# proves the operatorname case is a genuine regression guard, not a restatement
# of current behavior.
OPNAME_BODY='Define $`\operatorname{Tr}(A)`$.'
assert "operatorname: pre-fix regex -> clean (miss)" "$(prefix_rc "$OPNAME_BODY")" 0
assert "operatorname: fixed scan    -> hit"          "$(scan_rc "$OPNAME_BODY")"   1

# --- Summary --------------------------------------------------------------
echo
if [[ "$fails" -eq 0 ]]; then
  echo "All checks passed."
  exit 0
fi
echo "$fails check(s) failed."
exit 1
