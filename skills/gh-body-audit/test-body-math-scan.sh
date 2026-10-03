#!/usr/bin/env bash
# Contract test for body-math-scan.sh's exit-code + detection contract.
#
# Zero-dependency harness: bash + rg only (the repo has no bash test framework,
# and this adds only enough to drive this one script). It runs the scan against
# crafted body fixtures and asserts the exit-code contract:
#   0 = clean, 1 = a scanned Unicode math glyph, \operatorname,
#   code-span-neutralized inline-math construct, or $$ delimiter found,
#   2 = usage / env error.
#
# Three frozen regex reconstructions are checked alongside the real assertions,
# so the suite proves it guards the real regressions rather than just restating
# current behavior (see the "non-tautology guard" differentials): the
# Unicode-only PREFIX_REGEX shows a \operatorname body passes without class 2,
# the classes-1+2 PRE_CODESPAN_REGEX shows a code-span-neutralized inline-math
# body passes without class 3, and the classes-1+2+3 PRE_DOUBLE_DOLLAR_REGEX
# shows a $$ display block passes without class 4.
#
# Run:
#   bash test-body-math-scan.sh
#
# shellcheck disable=SC2016  # single-quoted fixture bodies hold literal LaTeX
#                            # (e.g. \operatorname); non-expansion is intentional.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN="$SCRIPT_DIR/body-math-scan.sh"

# The scanner's regex without class 2: the Unicode-codepoint class only, with
# no \operatorname alternative. FROZEN: do not extend it. It exists solely so
# the differential below can show a \operatorname-only body passes it.
PREFIX_REGEX='[\x{00B1}\x{00B2}\x{00B3}\x{00B9}\x{00D7}\x{00F7}\x{0370}-\x{03FF}\x{2070}-\x{209F}\x{2200}-\x{22FF}\x{2A00}-\x{2AFF}\x{2020}\x{2021}]'

# The scanner's regex without class 3 (code-span-neutralized inline math):
# classes 1 + 2 only (Unicode glyphs + \operatorname), built on PREFIX_REGEX.
# FROZEN: do not extend it. It exists solely so the class-3 differential below
# can show a body with inline math neutralized by a code span passes it.
PRE_CODESPAN_REGEX="$PREFIX_REGEX"'|\\operatorname\*?(?![A-Za-z])'

# The scanner's regex without class 4 (the $$ delimiter): classes 1 + 2 + 3,
# built on PRE_CODESPAN_REGEX. FROZEN: do not extend it. It exists solely so
# the class-4 differential below can show a $$ display block passes it.
PRE_DOUBLE_DOLLAR_REGEX="$PRE_CODESPAN_REGEX"'|(?<!`)(`{2,})(?!`)(?:(?!(?<!`)\1(?!`)).)*?\$`[^`]*`\$(?:(?!(?<!`)\1(?!`)).)*?(?<!`)\1(?!`)'

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

# Write a body string to a temp file and echo its path.
mkfix() { local f; f="$(mktemp "$tmpdir/fx-XXXXXX")"; printf '%s\n' "$1" >"$f"; echo "$f"; }

# Exit code of the real scan on a body string.
scan_rc() { "$SCAN" "$(mkfix "$1")" >/dev/null 2>&1; echo "$?"; }

# Standard output of the real scan on a body string.
scan_out() { "$SCAN" "$(mkfix "$1")" 2>/dev/null; }

# Exit code of a frozen regex ($1) on a body string ($2), under the same
# 0=hit / 1=clean / 2=error flip the script applies to rg's status.
frozen_rc() {
  local f rc
  f="$(mkfix "$2")"
  rg -nP "$1" "$f" >/dev/null 2>&1
  rc=$?
  case "$rc" in 0) echo 1 ;; 1) echo 0 ;; *) echo 2 ;; esac
}

fails=0
assert() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    printf 'ok   %-46s %s\n' "$label" "${got//$'\n'/ | }"
  else
    printf 'FAIL %-46s want %s got %s\n' "$label" "${want//$'\n'/ | }" "${got//$'\n'/ | }"
    fails=$((fails + 1))
  fi
}

# --- Contract cases -------------------------------------------------------
assert "operatorname in math -> hit"         "$(scan_rc 'Define $`\operatorname{Tr}(A)`$.')"        1
assert "operatorname* in math -> hit"        "$(scan_rc 'See $`\operatorname*{argmin}_x`$.')"       1
assert "operatornamewithlimits -> clean"     "$(scan_rc 'Use $`\operatornamewithlimits{lim}`$.')"   0
assert "unicode glyph -> hit"                "$(scan_rc 'The angle is α here.')"                     1
assert "mathrm substitute -> clean"          "$(scan_rc 'Use `\mathrm{Tr}` for the trace.')"        0

# --- Class 3: code-span-neutralized inline math ---------------------------
# The construct $`...`$ wrapped in a >=2-backtick code span renders as literal
# code on GitHub, not math, so it must be flagged.
assert "codespan-wrapped math -> hit"        "$(scan_rc 'Define `` $`\pm i`$ `` clearly.')"         1
assert "codespan-wrapped, no padding -> hit" "$(scan_rc 'Define ``$`\pm i`$`` here.')"               1
# Math co-resident with other text inside the span is still inside the span.
assert "codespan text + math -> hit"         "$(scan_rc '``example: $`a`$`` trailing.')"             1
# GFM lets a code span contain a backtick run LONGER than its own fence (a >fence
# run does not close it). The math after such a run is still neutralized; the
# tempered-token regex must not stop early on the longer internal run.
assert "codespan longer inner run -> hit"    "$(scan_rc 'a `` b ``` c $`x`$ d `` e')"               1
# Over-match guard: a bare valid inline-math construct (no enclosing span) is
# fine and must stay clean.
assert "bare inline math -> clean"           "$(scan_rc 'The value is $`\pm i`$ today.')"            0
# False-positive guard: a code span IMMEDIATELY FOLLOWED by valid math (the math
# is outside the span) must stay clean.
assert "codespan then bare math -> clean"    "$(scan_rc 'Use `` `inline` `` then $`\pm i`$ here.')"  0
# Mismatched fences (open 2, close 3) are not a GFM code span, so the math is not
# neutralized and must stay clean.
assert "mismatched fences -> clean"          "$(scan_rc 'Bad `` $`x`$ ``` mismatch.')"               0

# --- Class 4: the $$ delimiter --------------------------------------------
# Every line holding $$ is reported; telling a math delimiter from any other $$
# is SKILL.md's judgment, so a shell $$ in code and the seam between two
# adjacent inline-math spans are hits here too.
DISPLAY_BODY='Before
$$
x
$$
After'
assert "display block -> hit"                "$(scan_rc "$DISPLAY_BODY")"                           1
assert "display block -> both delimiter lines" "$(scan_out "$DISPLAY_BODY")"                        '2:$$
4:$$'
assert "double dollar in sentence -> hit"    "$(scan_rc 'Inline pair $$x+y$$ in a sentence.')"      1
assert "shell pid in code span -> hit"       "$(scan_rc 'Span `kill $$` here.')"                    1
assert "inline-math seam -> hit"             "$(scan_rc 'Seam $`a`$$`b`$ end.')"                    1
assert "spaced inline math -> clean"         "$(scan_rc 'Two $`a`$ $`b`$ spans.')"                  0
assert "escaped dollars -> clean"            "$(scan_rc 'Escaped \$\$ here.')"                      0

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
# A \operatorname-only body (no Unicode glyph) is where the Unicode-only regex
# and the scanner diverge: the Unicode-only regex reports clean (the miss
# class 2 closes), the scanner reports a hit. Asserting both directions
# proves the operatorname case is a genuine regression guard, not a restatement
# of current behavior.
OPNAME_BODY='Define $`\operatorname{Tr}(A)`$.'
assert "operatorname: pre-class2 regex -> clean (miss)" "$(frozen_rc "$PREFIX_REGEX" "$OPNAME_BODY")" 0
assert "operatorname: scan             -> hit"           "$(scan_rc "$OPNAME_BODY")"   1

# A code-span-neutralized inline-math body (no Unicode glyph, no \operatorname)
# is where the pre-class-3 regex (classes 1 + 2) and the scanner diverge:
# pre-class-3 reports clean (the miss class 3 closes), the scanner reports a
# hit. Asserting both directions proves class 3 is a genuine
# regression guard, not a restatement of current behavior.
CODESPAN_BODY='Define `` $`\pm i`$ `` clearly.'
assert "codespan: pre-class3 regex -> clean (miss)"  "$(frozen_rc "$PRE_CODESPAN_REGEX" "$CODESPAN_BODY")" 0
assert "codespan: scan             -> hit"             "$(scan_rc "$CODESPAN_BODY")"         1

# A $$ display block (no Unicode glyph, no \operatorname, no code-span-wrapped
# inline math) is where the pre-class-4 regex (classes 1 + 2 + 3) and the
# scanner diverge: pre-class-4 reports clean (the miss class 4 closes), the
# scanner reports a hit.
assert "display: pre-class4 regex -> clean (miss)"   "$(frozen_rc "$PRE_DOUBLE_DOLLAR_REGEX" "$DISPLAY_BODY")" 0
assert "display: scan             -> hit"              "$(scan_rc "$DISPLAY_BODY")"                             1

# --- Summary --------------------------------------------------------------
echo
if [[ "$fails" -eq 0 ]]; then
  echo "All checks passed."
  exit 0
fi
echo "$fails check(s) failed."
exit 1
