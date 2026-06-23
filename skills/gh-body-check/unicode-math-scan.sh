#!/usr/bin/env bash
# unicode-math-scan.sh — flag Unicode math glyphs and GitHub-unsupported math
# macros in a GitHub body draft.
#
# Mechanical half of gh-body-check. A single rg pass flags two classes that
# gh-body-conventions § Math forbids:
#   1. Unicode glyphs — any character in the Greek block, the two Mathematical
#      Operators blocks, the Superscripts-and-Subscripts block, the Latin-1 math
#      signs (plus-minus, multiplication, division) and superscripts (two /
#      three / one), or the dagger / double-dagger pair (use $`\alpha`$ etc.
#      instead of bare `α`).
#   2. GitHub-unsupported macro — the literal \operatorname / \operatorname*.
#      GitHub's math renderer does not render it regardless of delimiter form,
#      even though it works in standard MathJax (github/markup#1688); use
#      \mathrm instead.
# Code-block / code-span / prose-about-the-macro hits are out of scope here; the
# SKILL.md procedure judges those in main context.
#
# Exit codes: 0 = no hits (clean), 1 = hits found, 2 = usage or environment
# error. (rg's native convention is the opposite — match=0, no-match=1 — so this
# script flips it so callers can use the more natural "non-zero = problem"
# convention.)

set -uo pipefail

usage() {
  cat <<'EOF'
Usage: unicode-math-scan.sh <body-file>

Scans <body-file> for two classes of math that gh-body-conventions forbids:
  - Unicode math characters (Greek, Math Operators, Supplemental Math
    Operators, Superscripts/Subscripts, the Latin-1 signs ± × ÷ and
    superscripts ¹ ² ³, †, ‡).
  - The GitHub-unsupported macro \operatorname (broken on GitHub regardless
    of delimiter form; use \mathrm instead).

Prints rg output (line:match — rg emits no path prefix for a single file)
and exits 1 if any hit is found.
EOF
}

case "${1:-}" in
  ''|-h|--help) usage; [ -z "${1:-}" ] && exit 2 || exit 0 ;;
esac

BODY_FILE=$1
[ -f "$BODY_FILE" ] || { echo "error: file not found: $BODY_FILE" >&2; exit 2; }
command -v rg >/dev/null 2>&1 || { echo "error: ripgrep (rg) is required" >&2; exit 2; }

# Ranges:
#   U+00B1, U+00D7, U+00F7         plus-minus, multiplication, division
#   U+00B2, U+00B3, U+00B9         superscript two, three, one — listed
#                                  individually, NOT as a U+00B2–U+00B9 range,
#                                  which would also catch acute / micro /
#                                  pilcrow / middle-dot / cedilla (prose).
#   U+0370–U+03FF                  Greek and Coptic
#   U+2070–U+209F                  Superscripts and Subscripts (super/subscript
#                                  minus, plus, digits, etc.)
#   U+2200–U+22FF                  Mathematical Operators
#   U+2A00–U+2AFF                  Supplemental Mathematical Operators
#   U+2020, U+2021                 dagger, double dagger
# The character class catches the Unicode glyphs above; the trailing alternative
# catches the GitHub-unsupported macro \operatorname / \operatorname* (broken on
# GitHub regardless of delimiter form — github/markup#1688; use \mathrm instead).
# The (?![A-Za-z]) guard keeps \operatorname from partial-matching a longer
# command name such as \operatornamewithlimits, so only the in-scope forms match.
rg -nP '[\x{00B1}\x{00B2}\x{00B3}\x{00B9}\x{00D7}\x{00F7}\x{0370}-\x{03FF}\x{2070}-\x{209F}\x{2200}-\x{22FF}\x{2A00}-\x{2AFF}\x{2020}\x{2021}]|\\operatorname\*?(?![A-Za-z])' "$BODY_FILE"
rc=$?
# rg: 0 match, 1 no match, 2+ real error.
case "$rc" in
  0) exit 1 ;;   # hits found → problem
  1) exit 0 ;;   # no hits → clean
  *) exit 2 ;;   # rg failed (bad regex, IO error)
esac
