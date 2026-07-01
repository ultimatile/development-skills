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

# Detect whether CodeRabbit SKIPPED the review instead of running it.
#
# A terminal `success` "Review completed" status with no review object is
# ambiguous: it is either a genuine zero-finding pass or a NON-REVIEW skip that
# still emits terminal success. Three skip causes are known, each leaving a
# discriminator in CodeRabbit's bot issue comments:
#
#   paused        auto-pause (`auto_pause_after_reviewed_commits` stops reviewing
#                 after N commits) — HTML marker `review paused by coderabbit.ai`.
#   rate-limited  the per-developer PR review limit was reached, so the review
#                 never started — HTML marker `rate limited by coderabbit.ai`.
#   file-limit    the diff exceeds the max-files-per-review cap, so the review was
#                 skipped to avoid a low-quality review — matched on the machine
#                 prose `skipped due to max files limit` co-occurring with the
#                 `skip review by coderabbit.ai` marker. CodeRabbit reuses that
#                 marker for this AND for intentional config skips (title patterns,
#                 drafts, path filters), so the marker alone cannot single out an
#                 unintended file-count skip; the prose alone would self-trigger on
#                 a bot walkthrough that merely quotes the phrase (this repo ships
#                 that exact sentence). Requiring BOTH — the marker scopes the match
#                 to a real skip comment, the prose selects the file-count kind —
#                 brings this check to the same anchoring the other two get from the
#                 `<!--` wrapper. Deliberate config skips (marker without the
#                 file-count prose) are intentionally NOT flagged — an intentional
#                 skip is not a false clean pass. Residual gap: CodeRabbit controls
#                 the prose and could reword it, which would slip through as a false
#                 clean pass; no stable file-count marker exists to close that.
#
# The marker checks require the `<!--` wrapper so bot walkthrough prose that merely
# describes the feature does not self-trigger (CodeRabbit's own walkthrough of a PR
# touching this code echoes words like "reviews paused"). This gate runs only
# before declaring a zero-finding pass, so a skipped (unreviewed) push is never
# reported as clean.
#
# Echoes the cause token on the first match. Returns: 0 = skip signature found
# (token on stdout), 1 = fetched but none found, 2 = fetch failed.
review_skip_reason() {
    local bodies
    # `--paginate` walks every page: on a long-lived PR the marker-bearing comment
    # can fall outside the first 100 issue comments, and missing it would misreport
    # a skipped run as a clean pass. `.body | @json` emits each comment body as one
    # JSON-escaped line, so a body's internal newlines don't split it — the
    # file-limit check below needs the marker and the prose in the SAME comment, so
    # per-comment granularity matters. `|| return 2` distinguishes a fetch/jq
    # failure from an empty-but-OK result (no bot comments still exits 0 with empty
    # stdout -> "no marker").
    bodies=$(
        gh api --paginate "repos/$repo/issues/$pr_number/comments?per_page=100" \
            --jq ".[] | select(.user.login == \"$BOT_LOGIN\") | .body | @json" \
            2>/dev/null
    ) || return 2
    # Pause / rate-limit: a single HTML marker anywhere in any body is sufficient,
    # so grep the whole set. `if`-guarded so a miss does not trip set -e.
    if grep -qiE '<!--[^>]*review paused by coderabbit\.ai' <<<"$bodies"; then
        echo "paused"; return 0
    fi
    if grep -qiE '<!--[^>]*rate limited by coderabbit\.ai' <<<"$bodies"; then
        echo "rate-limited"; return 0
    fi
    # File-count: the `skip review` marker AND the file-count prose must sit in the
    # SAME comment — the marker also flags deliberate config skips, and the prose
    # alone would self-trigger on a walkthrough that quotes it, so neither in
    # isolation nor split across two comments qualifies. Scan per body (one
    # JSON-encoded line each) rather than the concatenated set.
    local body
    while IFS= read -r body; do
        [[ -n "$body" ]] || continue
        if grep -qiE '<!--[^>]*skip review by coderabbit\.ai' <<<"$body" \
            && grep -qiE 'skipped due to max files limit' <<<"$body"; then
            echo "file-limit"; return 0
        fi
    done <<<"$bodies"
    return 1
}

# Print a cause-specific notice for a detected non-review skip. All three causes
# mean "the review did not run" (the caller maps this to exit 2), but the remedy
# differs, so the message is per-cause. Reads the globals $repo / $pr_number.
print_skip_notice() {
    local reason="$1"
    local trigger="  gh pr comment $pr_number --repo $repo --body \"@coderabbitai review\""
    # `${BASH_SOURCE[0]}`, not `$0`: this file is designed to be sourced (the
    # contract test sources it), and the recovery hint must print the script's own
    # path even if the function is ever reached from a sourced context where `$0`
    # would be the calling shell.
    local poll_cmd="  ${BASH_SOURCE[0]} --poll https://github.com/$repo/pull/$pr_number"
    case "$reason" in
        paused)
            echo "=== Review Auto-Paused ==="
            echo "CodeRabbit auto-paused reviews on this PR — the terminal 'success' status reflects a"
            echo "skipped (unreviewed) push, not a clean pass. Resume the review, then re-poll:"
            echo "$trigger"
            echo "$poll_cmd"
            ;;
        rate-limited)
            echo "=== Review Rate-Limited ==="
            echo "CodeRabbit hit its per-developer PR review limit — the review did NOT run, so the terminal"
            echo "'success' status is not a clean pass. Wait for the limit to reset (the 'Review limit reached'"
            echo "comment on the PR states the window), then push a new commit or resume, and re-poll:"
            echo "$trigger"
            echo "$poll_cmd"
            ;;
        file-limit)
            echo "=== Review Skipped (max files) ==="
            echo "The diff exceeds CodeRabbit's max-files-per-review limit, so the review was skipped to avoid"
            echo "a low-quality review — the terminal 'success' status is not a clean pass. A bare re-trigger"
            echo "will NOT help (the file count is unchanged): reduce the diff (split the PR) or raise the limit"
            echo "(plan / .coderabbit.yaml), then re-poll:"
            echo "$poll_cmd"
            ;;
        *)
            echo "=== Review Skipped ==="
            echo "CodeRabbit skipped the review (cause: ${reason}) — not a clean pass. Inspect the PR before proceeding."
            ;;
    esac
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
                # genuine clean pass or a NON-REVIEW skip (auto-pause, rate
                # limit, or file-count) that still emits terminal success. Rule
                # out every skip signature before reporting a clean pass.
                local skip_reason skip_rc=0
                skip_reason=$(review_skip_reason) || skip_rc=$?
                if [[ "$skip_rc" -eq 0 ]]; then
                    print_skip_notice "$skip_reason"
                    return 2
                fi
                if [[ "$skip_rc" -eq 2 ]]; then
                    # Fail closed: the whole point of this gate is to never call
                    # an unreviewed push clean, so an unverifiable skip state
                    # must not fall through to a zero-finding report. Halt and
                    # let the caller re-poll or inspect the PR.
                    echo "Could not verify skip state from PR comments — refusing to report a clean pass." >&2
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
# non-review-skip signal as a distinct code so callers (e.g. review-pipeline-
# coderabbit) can resume rather than treat a skipped push as a clean pass:
#   0 -> clean / findings printed;
#   2 -> non-review skip (auto-pause / rate-limit / file-count) — the printed
#        notice states the per-cause remedy; the review did not run;
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
