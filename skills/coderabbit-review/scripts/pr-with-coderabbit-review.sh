#!/usr/bin/env bash
# Create a PR and wait for the auto-triggered CodeRabbit review.
#
# CodeRabbit is app-driven: once the GitHub app is installed on the
# repository, a review starts automatically on PR open and an
# incremental review starts on every push. There is no reviewer-request
# step, so every mode below resolves to "wait for a CodeRabbit review
# of the PR's current head commit".
#
# Completion is detected via the `CodeRabbit` commit status on the PR's
# current head SHA (Review queued / in progress -> Review completed). A
# clean review posts NO review object, so review presence cannot be the
# completion signal. When a review object does exist it is matched to
# the head commit by commit_id, so a review that arrived between the
# push and this script's start still counts, and stale reviews of
# earlier commits are never reported.
#
# Modes:
#   Normal:     all arguments forwarded to `gh-post pr create`
#   Poll:       --poll <PR_URL> — wait for a review of the current head
#   Re-review:  --re-review <PR_URL> — for fix loops: the push that
#               preceded this call already triggered the incremental
#               review; this waits for it (same wait as --poll)
#
# Body must flow through `--body-file <path>` or `--body-stdin`; the
# `gh-post` wrapper rejects inline `--body <string>` / `-b` so every
# body passes the hardwrap validator stack before reaching GitHub.
#
# Usage:
#   ./pr-with-coderabbit-review.sh --title "fix: foo" --body-file /tmp/body.md --base main
#   ./pr-with-coderabbit-review.sh --poll https://github.com/owner/repo/pull/123
#   ./pr-with-coderabbit-review.sh --re-review https://github.com/owner/repo/pull/123
#
# Environment variables:
#   CODERABBIT_POLL_INITIAL   Initial poll interval in seconds (default: 60)
#   CODERABBIT_POLL_MAX       Max poll interval in seconds     (default: 300)
#   CODERABBIT_POLL_ATTEMPTS  Max number of poll attempts      (default: 10)
#
# `set -euo pipefail` is deferred to the direct-execution guard at the bottom so
# this file can be sourced (by the contract test) for its function definitions
# without imposing strict mode on the caller's shell.

# REST endpoints report the app's login with the `[bot]` suffix.
BOT_LOGIN="coderabbitai[bot]"

POLL_INITIAL="${CODERABBIT_POLL_INITIAL:-60}"
POLL_MAX="${CODERABBIT_POLL_MAX:-300}"
POLL_ATTEMPTS="${CODERABBIT_POLL_ATTEMPTS:-10}"

parse_pr_url() {
    local input="$1"
    local url
    # Pluck the first PR URL out of `$input`. Normal mode passes the
    # multi-line stdout of `gh-post pr create` (gh's URL line plus the
    # view-summary block); `--poll` / `--re-review` pass a single bare
    # URL. Both shapes feed through the same regex.
    #
    # `|| true` neutralizes two failures under `set -euo pipefail`:
    #   - grep exit 1 when the input contains no URL (the diagnostic
    #     `[[ -z "$url" ]]` branch below is the intended error gate),
    #   - SIGPIPE on grep when `head -1` closes the pipe before grep
    #     finishes scanning a multi-match input.
    url=$(echo "$input" | grep -oE 'https://github\.com/[^/[:space:]]+/[^/[:space:]]+/pull/[0-9]+' | head -1 || true)
    if [[ -z "$url" ]]; then
        echo "Error: could not parse PR URL from input" >&2
        exit 1
    fi
    repo=$(echo "$url" | sed -E 's|https://github.com/([^/]+/[^/]+)/pull/[0-9]+|\1|')
    pr_number=$(echo "$url" | grep -oE '[0-9]+$')
    if [[ -z "$repo" || -z "$pr_number" ]]; then
        echo "Error: could not parse PR URL: $url" >&2
        exit 1
    fi
}

# Print the review object for the head commit (if any). Returns 0 when a
# review object was found and printed, 1 when none exists.
print_review_if_any() {
    local head_sha="$1"
    review_id=$(
        gh api "repos/$repo/pulls/$pr_number/reviews?per_page=100" \
            --jq "[.[] | select(.user.login == \"$BOT_LOGIN\" and .commit_id == \"$head_sha\")] | last | .id // empty" \
            2>/dev/null
    ) || true
    [[ -n "$review_id" ]] || return 1

    echo "CodeRabbit review received (review id ${review_id})" >&2

    echo "=== Review Summary ==="
    gh api "repos/$repo/pulls/$pr_number/reviews/$review_id" --jq '.body'

    # Inline comments belonging to this review only — earlier
    # iterations' comments are excluded by the review id.
    comments=$(
        gh api "repos/$repo/pulls/$pr_number/comments?per_page=100" \
            --jq "[.[] | select(.user.login == \"$BOT_LOGIN\" and .pull_request_review_id == ${review_id})] | .[] | \"\\(.path):\\(.line)\\t\\(.body)\"" \
            2>/dev/null
    ) || true

    if [[ -n "$comments" ]]; then
        echo ""
        echo "=== Inline Comments ==="
        echo "$comments"
    fi
    return 0
}

# Detect whether CodeRabbit has auto-paused reviews on this PR.
#
# `auto_pause_after_reviewed_commits` makes CodeRabbit stop reviewing after
# a number of commits, yet it still emits a terminal `success` commit status
# with description "Review completed" — indistinguishable from a genuine
# clean pass on the status alone. The authoritative pause signal is instead
# the marker CodeRabbit writes into its PR summary issue comment. This gate
# runs only before declaring a zero-finding pass, so a paused (unreviewed)
# push is never reported as clean.
#
# Returns: 0 = pause marker found, 1 = fetched but no marker, 2 = fetch failed.
review_is_paused() {
    local bodies
    # `--paginate` walks every page: on a long-lived PR the summary comment
    # carrying the marker can fall outside the first 100 issue comments, and
    # missing it would misreport an auto-paused run as a clean pass. With
    # `--paginate` the `--jq` filter runs per page and the matching bodies are
    # concatenated, so one body per line is the right shape for the grep below.
    # `|| return 2` distinguishes a fetch/jq failure from an empty-but-OK
    # result (no bot comments still exits 0 with empty stdout -> "no marker").
    bodies=$(
        gh api --paginate "repos/$repo/issues/$pr_number/comments?per_page=100" \
            --jq ".[] | select(.user.login == \"$BOT_LOGIN\") | .body" \
            2>/dev/null
    ) || return 2
    # Match CodeRabbit's machine-emitted HTML pause marker, NOT visible prose.
    # CodeRabbit's own PR walkthrough describes this very feature with the words
    # "reviews paused" / "pause marker", so matching bare prose self-triggers a
    # false pause on any PR that touches or mentions this code. The genuine
    # auto-pause emits an HTML-comment marker in the `<!-- ... by coderabbit.ai
    # -->` family (observed siblings: `skip review by coderabbit.ai`,
    # `summarize by coderabbit.ai`); requiring the `<!--` wrapper excludes prose
    # and quoted code. `if`-guarded so a grep miss does not trip set -e.
    if grep -qiE '<!--[^>]*review paused by coderabbit\.ai' <<<"$bodies"; then
        return 0
    fi
    return 1
}

# Poll the `CodeRabbit` commit status on the PR's head commit until it
# reaches a terminal state, then print the review (if one was posted).
#
# The status — not review presence — is the completion signal: CodeRabbit
# reports Review queued / Review in progress (pending) -> Review completed
# (success) on the head SHA, and a clean review posts NO review object at
# all (only the walkthrough comment plus this status). Waiting on review
# presence would therefore hang forever on every zero-finding PR.
poll_for_review() {
    local head_sha
    head_sha=$(gh api "repos/$repo/pulls/$pr_number" --jq '.head.sha')
    echo "Waiting for CodeRabbit on head ${head_sha:0:8} (polling every ${POLL_INITIAL}s)..." >&2
    local interval=$POLL_INITIAL

    for ((i = 1; i <= POLL_ATTEMPTS; i++)); do
        sleep "$interval"

        # Combined status endpoint: latest status per context.
        status_state=$(
            gh api "repos/$repo/commits/$head_sha/status" \
                --jq '[.statuses[] | select(.context == "CodeRabbit")] | first | .state // empty' \
                2>/dev/null
        ) || true
        status_desc=$(
            gh api "repos/$repo/commits/$head_sha/status" \
                --jq '[.statuses[] | select(.context == "CodeRabbit")] | first | .description // empty' \
                2>/dev/null
        ) || true

        if [[ "$status_state" == "success" || "$status_state" == "failure" || "$status_state" == "error" ]]; then
            echo "CodeRabbit status: ${status_desc} (${status_state})" >&2

            if print_review_if_any "$head_sha"; then
                return 0
            fi

            if [[ "$status_state" == "success" ]]; then
                # Small grace window: the review object can land moments
                # after the status flips to success.
                sleep 10
                if print_review_if_any "$head_sha"; then
                    return 0
                fi
                # `success` + no review object is ambiguous: it is either a
                # genuine clean pass or an auto-paused (unreviewed) push.
                # Disambiguate via the PR summary comment before reporting.
                local pause_rc=0
                review_is_paused || pause_rc=$?
                if [[ "$pause_rc" -eq 0 ]]; then
                    echo "=== Review Auto-Paused ==="
                    echo "CodeRabbit auto-paused reviews on this PR — the terminal 'success' status reflects a"
                    echo "skipped (unreviewed) push, not a clean pass. Resume the review, then re-poll:"
                    echo "  gh pr comment $pr_number --repo $repo --body \"@coderabbitai review\""
                    echo "  $0 --poll https://github.com/$repo/pull/$pr_number"
                    return 2
                fi
                if [[ "$pause_rc" -eq 2 ]]; then
                    # Fail closed: the whole point of this gate is to never call
                    # an unreviewed push clean, so an unverifiable pause state
                    # must not fall through to a zero-finding report. Halt and
                    # let the caller re-poll or inspect the PR.
                    echo "Could not verify pause state from PR comments — refusing to report a clean pass." >&2
                    echo "Re-poll, or inspect the PR manually before proceeding." >&2
                    return 1
                fi
                echo "=== Review Result ==="
                echo "Review completed with zero findings — CodeRabbit posts no review object on a clean pass (status: ${status_desc})."
                return 0
            fi

            echo "Review ended without completing: ${status_desc} (${status_state})" >&2
            return 1
        fi

        echo "  attempt $i/$POLL_ATTEMPTS — status: ${status_desc:-not reported yet}, next check in ${interval}s" >&2
        interval=$(( interval * 2 ))
        (( interval > POLL_MAX )) && interval=$POLL_MAX
    done

    echo "Timeout: no terminal CodeRabbit status on head ${head_sha:0:8} after $POLL_ATTEMPTS attempts" >&2
    echo "No status at all means the review never started — check the app installation, plan," >&2
    echo "and automatic-review settings in the CodeRabbit dashboard. (A repo .coderabbit.yaml" >&2
    echo "with reviews.commit_status: false also hides the signal.) To trigger manually:" >&2
    echo "  gh pr comment $pr_number --repo $repo --body \"@coderabbitai full review\"" >&2
    echo "then re-run this script with --poll." >&2
    return 1
}

# Translate poll_for_review's return code into a process exit, preserving the
# auto-pause signal as a distinct code so callers (e.g. review-pipeline-
# coderabbit) can resume rather than treat a paused push as a clean pass:
#   0 -> clean / findings printed;  2 -> auto-paused (resume needed);
#   anything else -> failure.
# `rc=0; poll_for_review || rc=$?` captures the code without tripping set -e.
poll_and_exit() {
    local pr_url="$1"
    local rc=0
    poll_for_review || rc=$?
    case "$rc" in
        0) exit 0 ;;
        2) exit 2 ;;
        *) echo "Check manually: $pr_url" >&2; exit 1 ;;
    esac
}

# Stop here when sourced (e.g. by the contract test): only the constant and
# function definitions above are wanted, not the PR-creation side effects below.
# `set -euo pipefail` is enabled here, in the direct-execution path only, so the
# run-as-script behavior is unchanged while sourcing leaves the caller's shell
# options untouched.
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
    return 0 2>/dev/null || exit 0
fi
set -euo pipefail

# --- Mode selection -------------------------------------------------------
if [[ "${1:-}" == "--poll" ]]; then
    shift
    pr_url="${1:?Usage: $0 --poll <PR_URL>}"
    parse_pr_url "$pr_url"
    echo "Polling existing PR: $pr_url" >&2
    poll_and_exit "$pr_url"
fi

if [[ "${1:-}" == "--re-review" ]]; then
    shift
    pr_url="${1:?Usage: $0 --re-review <PR_URL>}"
    parse_pr_url "$pr_url"
    # No trigger step: the push that preceded this call already started
    # CodeRabbit's incremental review. Head-SHA matching ignores all
    # reviews of earlier commits, so waiting is the whole job.
    echo "Waiting for incremental review on PR #$pr_number (auto-triggered by the push)..." >&2
    poll_and_exit "$pr_url"
fi

# --- Normal mode: create PR + poll -----------------------------------------
# Routes through `gh-post pr create` (not `gh pr create`) so the body
# passes the hardwrap validator stack at submission. No reviewer flag:
# the CodeRabbit app starts its review on PR open by itself.
echo "Creating PR (CodeRabbit reviews automatically on open)..." >&2
pr_url=$(gh-post pr create "$@") || {
    echo "Error: gh-post pr create failed" >&2
    exit 1
}
echo "PR created: $pr_url" >&2

parse_pr_url "$pr_url"
poll_and_exit "$pr_url"
