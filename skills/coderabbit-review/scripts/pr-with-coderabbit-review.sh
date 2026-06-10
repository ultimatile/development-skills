#!/usr/bin/env bash
# Create a PR and wait for the auto-triggered CodeRabbit review.
#
# CodeRabbit is app-driven: once the GitHub app is installed on the
# repository, a review starts automatically on PR open and an
# incremental review starts on every push. There is no reviewer-request
# step, so every mode below resolves to "wait for a CodeRabbit review
# of the PR's current head commit".
#
# Matching is by commit: a review counts only if its commit_id equals
# the PR's current head SHA. This makes the wait race-free — a review
# that arrived between the push and this script's start still matches,
# and stale reviews of earlier commits never satisfy the wait.
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
set -euo pipefail

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

# Poll until a CodeRabbit review of the PR's current head commit exists,
# then print its summary body and that review's inline comments.
poll_for_review() {
    local head_sha
    head_sha=$(gh api "repos/$repo/pulls/$pr_number" --jq '.head.sha')
    echo "Waiting for CodeRabbit review of head ${head_sha:0:8} (polling every ${POLL_INITIAL}s)..." >&2
    local interval=$POLL_INITIAL

    for ((i = 1; i <= POLL_ATTEMPTS; i++)); do
        sleep "$interval"

        review_id=$(
            gh api "repos/$repo/pulls/$pr_number/reviews?per_page=100" \
                --jq "[.[] | select(.user.login == \"$BOT_LOGIN\" and .commit_id == \"$head_sha\")] | last | .id // empty" \
                2>/dev/null
        ) || true

        if [[ -n "$review_id" ]]; then
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
        fi

        echo "  attempt $i/$POLL_ATTEMPTS — no review for current head yet, next check in ${interval}s" >&2
        interval=$(( interval * 2 ))
        (( interval > POLL_MAX )) && interval=$POLL_MAX
    done

    echo "Timeout: CodeRabbit review of head ${head_sha:0:8} did not arrive after $POLL_ATTEMPTS attempts" >&2
    echo "If automatic reviews are disabled (or the app missed the event), trigger one manually:" >&2
    echo "  gh pr comment $pr_number --repo $repo --body \"@coderabbitai review\"" >&2
    echo "then re-run this script with --poll." >&2
    return 1
}

# --- Mode selection -------------------------------------------------------
if [[ "${1:-}" == "--poll" ]]; then
    shift
    pr_url="${1:?Usage: $0 --poll <PR_URL>}"
    parse_pr_url "$pr_url"
    echo "Polling existing PR: $pr_url" >&2
    poll_for_review || { echo "Check manually: $pr_url" >&2; exit 1; }
    exit 0
fi

if [[ "${1:-}" == "--re-review" ]]; then
    shift
    pr_url="${1:?Usage: $0 --re-review <PR_URL>}"
    parse_pr_url "$pr_url"
    # No trigger step: the push that preceded this call already started
    # CodeRabbit's incremental review. Head-SHA matching ignores all
    # reviews of earlier commits, so waiting is the whole job.
    echo "Waiting for incremental review on PR #$pr_number (auto-triggered by the push)..." >&2
    poll_for_review || { echo "Check manually: $pr_url" >&2; exit 1; }
    exit 0
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
poll_for_review || { echo "Check manually: $pr_url" >&2; exit 1; }
exit 0
