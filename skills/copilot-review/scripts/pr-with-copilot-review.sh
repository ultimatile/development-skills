#!/usr/bin/env bash
# Create a PR with Copilot review and poll until the review arrives.
#
# Modes:
#   Normal:     all arguments forwarded to `gh-post pr create --reviewer @copilot`
#   Poll:       --poll <PR_URL> — wait for review on existing PR
#   Re-review:  --re-review <PR_URL> — trigger new review + wait for it
#
# Body must flow through `--body-file <path>` or `--body-stdin`; the
# `gh-post` wrapper rejects inline `--body <string>` / `-b` so every
# body passes the hardwrap validator stack before reaching GitHub.
#
# Usage:
#   ./pr-with-copilot-review.sh --title "fix: foo" --body-file /tmp/body.md --base main
#   ./pr-with-copilot-review.sh --poll https://github.com/owner/repo/pull/123
#   ./pr-with-copilot-review.sh --re-review https://github.com/owner/repo/pull/123
#
# Environment variables:
#   COPILOT_POLL_INITIAL   Initial poll interval in seconds (default: 60)
#   COPILOT_POLL_MAX       Max poll interval in seconds     (default: 300)
#   COPILOT_POLL_ATTEMPTS  Max number of poll attempts      (default: 10)
set -euo pipefail

POLL_INITIAL="${COPILOT_POLL_INITIAL:-60}"
POLL_MAX="${COPILOT_POLL_MAX:-300}"
POLL_ATTEMPTS="${COPILOT_POLL_ATTEMPTS:-10}"

parse_pr_url() {
    local url="$1"
    repo=$(echo "$url" | sed -E 's|https://github.com/([^/]+/[^/]+)/pull/[0-9]+|\1|')
    pr_number=$(echo "$url" | grep -oE '[0-9]+$')
    if [[ -z "$repo" || -z "$pr_number" ]]; then
        echo "Error: could not parse PR URL: $url" >&2
        exit 1
    fi
}

# Count existing Copilot reviews on the PR
count_copilot_reviews() {
    gh api "repos/$repo/pulls/$pr_number/reviews" \
        --jq '[.[] | select(.user.login == "copilot-pull-request-reviewer[bot]")] | length' \
        2>/dev/null || echo "0"
}

# Poll until a new Copilot review appears (review count exceeds $1)
poll_for_review() {
    local baseline_count="${1:-0}"
    echo "Waiting for Copilot review (baseline: ${baseline_count} existing, polling every ${POLL_INITIAL}s)..." >&2
    local interval=$POLL_INITIAL

    for ((i = 1; i <= POLL_ATTEMPTS; i++)); do
        sleep "$interval"

        current_count=$(count_copilot_reviews)

        if (( current_count > baseline_count )); then
            echo "Copilot review received (review #${current_count})" >&2

            # Get the latest review ID and body
            latest_review_id=$(
                gh api "repos/$repo/pulls/$pr_number/reviews" \
                    --jq '[.[] | select(.user.login == "copilot-pull-request-reviewer[bot]")] | last | .id' \
                    2>/dev/null
            ) || true

            echo "=== Review Summary ==="
            gh api "repos/$repo/pulls/$pr_number/reviews" \
                --jq '[.[] | select(.user.login == "copilot-pull-request-reviewer[bot]")] | last | .body'

            # Filter inline comments to only those from the latest review
            comments=$(
                gh api "repos/$repo/pulls/$pr_number/comments" \
                    --jq "[.[] | select(.user.login == \"Copilot\" and .pull_request_review_id == ${latest_review_id})] | .[] | \"\\(.path):\\(.line)\\t\\(.body)\"" \
                    2>/dev/null
            ) || true

            if [[ -n "$comments" ]]; then
                echo ""
                echo "=== Inline Comments ==="
                echo "$comments"
            fi

            return 0
        fi

        echo "  attempt $i/$POLL_ATTEMPTS — no new review yet, next check in ${interval}s" >&2
        interval=$(( interval * 2 ))
        (( interval > POLL_MAX )) && interval=$POLL_MAX
    done

    echo "Timeout: new Copilot review did not arrive after $POLL_ATTEMPTS attempts" >&2
    return 1
}

# --- Mode selection -------------------------------------------------------
if [[ "${1:-}" == "--poll" ]]; then
    shift
    pr_url="${1:?Usage: $0 --poll <PR_URL>}"
    parse_pr_url "$pr_url"
    echo "Polling existing PR: $pr_url" >&2
    poll_for_review 0 || { echo "Check manually: $pr_url" >&2; exit 1; }
    exit 0
fi

if [[ "${1:-}" == "--re-review" ]]; then
    shift
    pr_url="${1:?Usage: $0 --re-review <PR_URL>}"
    parse_pr_url "$pr_url"

    # Record current review count before triggering
    baseline=$(count_copilot_reviews)
    echo "Re-requesting Copilot review on PR #$pr_number (${baseline} existing reviews)..." >&2

    if ! gh pr edit "$pr_number" --add-reviewer @copilot 2>/dev/null; then
        echo "Error: failed to re-request Copilot review" >&2
        exit 1
    fi

    poll_for_review "$baseline" || { echo "Check manually: $pr_url" >&2; exit 1; }
    exit 0
fi

# --- Normal mode: create PR + request review + poll -----------------------
# Routes through `gh-post pr create` (not `gh pr create`) so the body
# passes the hardwrap validator stack at submission, closing the last
# known body-validation bypass. `gh-post` forwards unknown flags
# (`--reviewer`, `--base`, etc.) to `gh` verbatim, so the script's
# invocation surface is unchanged for callers using `--body-file`.
echo "Creating PR with Copilot review..." >&2
pr_url=$(gh-post pr create --reviewer @copilot "$@") || {
    echo "Error: gh-post pr create failed" >&2
    exit 1
}
echo "PR created: $pr_url" >&2

parse_pr_url "$pr_url"
poll_for_review 0 || { echo "Check manually: $pr_url" >&2; exit 1; }
exit 0
