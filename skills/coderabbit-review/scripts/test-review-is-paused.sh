#!/usr/bin/env bash
# Contract test for review_is_paused() in pr-with-coderabbit-review.sh.
#
# Zero-dependency harness: bash + jq only (the repo has no bash test framework,
# and this adds only enough to source and assert this one unit). It sources the
# script under test, stubs `gh` to run the real --jq filter over fixture comment
# arrays, and asserts review_is_paused's exit-code contract:
#   0 = pause marker found, 1 = fetched but no marker, 2 = fetch failed.
#
# A frozen reconstruction of the pre-fix broad-grep implementation is checked
# alongside the real assertions so the suite proves it guards the real
# regression, not just restates current behavior (see "non-tautology guard").
#
# Run:
#   bash test-review-is-paused.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source brings in review_is_paused + BOT_LOGIN without running the script's
# mode-selection / PR-creation logic (guarded by its BASH_SOURCE check).
# shellcheck source=/dev/null
source "$SCRIPT_DIR/pr-with-coderabbit-review.sh"

# review_is_paused interpolates these into the gh api URL; the stub ignores the
# URL but they must be set so the call expands cleanly.
repo="owner/repo"
pr_number=1

BOT='coderabbitai[bot]'

# Fixture state read by the gh stub. FIXTURE_JSON is a JSON array of issue
# comments; FIXTURE_FAIL=1 makes the stub fail like a network/jq error.
FIXTURE_JSON='[]'
FIXTURE_FAIL=0

# Stub `gh`: on failure return non-zero (drives review_is_paused's `|| return 2`
# fail-closed path); otherwise extract the --jq filter and run the real jq over
# the fixture. Running the genuine filter exercises the bot-login selection and
# .body extraction the production call relies on, so the non-bot case is a real
# test of `select(.user.login == "$BOT_LOGIN")`, not a hand-waved one.
gh() {
    if [[ "$FIXTURE_FAIL" == "1" ]]; then
        return 1
    fi
    local filter=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --jq) filter="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    printf '%s' "$FIXTURE_JSON" | jq -r "$filter"
}

# Frozen reconstruction of the pre-fix broad-grep review_is_paused, taken from
# PR #21 intermediate commit c1a7beba8 (before the HTML-marker fix). It matches
# bare "reviews paused" prose, which CodeRabbit's own walkthrough emits when
# describing this feature — the false-positive class the fix removed. This is a
# FROZEN HISTORICAL ARTIFACT: do not update it to track the real function. It
# exists solely so the differential assertion below can show the real function
# diverges from it on the prose fixture.
review_is_paused__pre_fix_broad_grep() {
    local bodies
    bodies=$(
        gh api --paginate "repos/$repo/issues/$pr_number/comments?per_page=100" \
            --jq ".[] | select(.user.login == \"$BOT\") | .body" \
            2>/dev/null
    ) || return 2
    if grep -qiE 'review paused by coderabbit\.ai|reviews paused' <<<"$bodies"; then
        return 0
    fi
    return 1
}

# --- Assertion plumbing ---------------------------------------------------
fails=0

# Build a comments fixture from alternating "login body login body ..." args, so
# the comment-object shape the jq filter reads is defined in exactly one place.
comment_array() {
    jq -nc --args \
        '[range(0; ($ARGS.positional | length); 2) as $i
          | {user: {login: $ARGS.positional[$i]}, body: $ARGS.positional[$i + 1]}]' \
        "$@"
}

# Run the function under the SAME shell options the script runs under on direct
# execution (`set -euo pipefail`) and capture its exit code. The subshell is
# required for errexit to actually take effect inside the function: a bare
# `fn || rc=$?` would disable errexit within fn (bash treats it as part of a `||`
# list), so the test would not exercise the production strict-mode behavior.
rc_of() { local fn="$1" rc=0; ( set -euo pipefail; "$fn" ) || rc=$?; echo "$rc"; }

assert_rc() {
    local label="$1" fn="$2" want="$3" got
    got="$(rc_of "$fn")"
    if [[ "$got" == "$want" ]]; then
        printf 'ok   %-40s rc=%s\n' "$label" "$got"
    else
        printf 'FAIL %-40s want rc=%s got rc=%s\n' "$label" "$want" "$got"
        fails=$((fails + 1))
    fi
}

# The genuine machine marker CodeRabbit emits when it auto-pauses: an HTML
# comment in the `<!-- ... by coderabbit.ai -->` family.
GENUINE_MARKER='<!-- This is an auto-generated comment: review paused by coderabbit.ai -->'

# Bot walkthrough prose that mentions the feature without the HTML wrapper. Cases
# 2 and the non-tautology guard MUST share this exact string: the differential
# only proves the regression if both implementations see the same input.
PROSE_FIXTURE='CodeRabbit can keep reviews paused after N commits; the pause marker is documented here.'

# --- Contract cases -------------------------------------------------------

# 1. Genuine HTML pause marker in a bot comment -> paused.
FIXTURE_FAIL=0
FIXTURE_JSON="$(comment_array "$BOT" "$GENUINE_MARKER")"
assert_rc "genuine HTML marker -> paused" review_is_paused 0

# 2. Bot walkthrough prose mentioning the feature, with NO <!-- wrapper -> not
#    paused. This is the regression the HTML-marker fix guards.
FIXTURE_JSON="$(comment_array "$BOT" "$PROSE_FIXTURE")"
assert_rc "walkthrough prose -> not paused" review_is_paused 1

# 3. Non-bot comment containing the prose -> not paused (bot-login filter drops
#    it before the body is ever grepped).
FIXTURE_JSON="$(comment_array "some-human" "reviews paused, in my opinion")"
assert_rc "non-bot prose -> not paused" review_is_paused 1

# 4. Genuine marker on a later comment (not the first): a benign bot comment
#    precedes it. Asserts the matcher scans every fetched body, not just the
#    first. (The --paginate flag itself is the gh client's job — review_is_paused
#    has no page loop to unit-test.)
FIXTURE_JSON="$(comment_array "$BOT" "Walkthrough: summary of changes." "$BOT" "$GENUINE_MARKER")"
assert_rc "marker on later comment -> paused" review_is_paused 0

# 5. Comment fetch failure -> unverifiable (fail closed).
FIXTURE_FAIL=1
FIXTURE_JSON='[]'
assert_rc "fetch failure -> unverifiable" review_is_paused 2

# --- Non-tautology guard --------------------------------------------------
# The prose fixture (case 2) is where the real and pre-fix implementations
# diverge: the broad-grep version reports it as paused (0), the fixed version
# does not (1). Asserting both directions proves the prose case is a genuine
# regression guard rather than a restatement of current behavior.
FIXTURE_FAIL=0
FIXTURE_JSON="$(comment_array "$BOT" "$PROSE_FIXTURE")"
assert_rc "prose: pre-fix broad-grep -> paused"  review_is_paused__pre_fix_broad_grep 0
assert_rc "prose: fixed function   -> not paused" review_is_paused 1

# --- Summary --------------------------------------------------------------
echo
if [[ "$fails" -eq 0 ]]; then
    echo "All checks passed."
    exit 0
fi
echo "$fails check(s) failed."
exit 1
