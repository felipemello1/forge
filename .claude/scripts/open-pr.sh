#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
# All rights reserved.
#
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree.

# Open a PR linked to a GitHub issue.
#
# Usage:
#   open-pr.sh <issue-number> [pr-title]
#
# If pr-title is omitted, it's derived from the issue title.
# Set SUMMARY and TEST_PLAN env vars to fill PR body, or pipe a body via stdin.

set -euo pipefail

if [[ -z "${1:-}" ]]; then
    echo "Usage: open-pr.sh <issue-number> [pr-title]" >&2
    exit 1
fi

ISSUE_NUM="$1"
shift

# Check gh is authenticated
if ! gh auth status &>/dev/null; then
    echo "Error: gh is not authenticated." >&2
    echo "Fix: Run 'gh auth login' first." >&2
    exit 1
fi

# Ensure we're not on main
CURRENT_BRANCH="$(git branch --show-current)"
if [[ "$CURRENT_BRANCH" == "main" ]]; then
    echo "Error: Cannot open a PR from main." >&2
    echo "Fix: Use worktree-setup.sh to create a feature branch first." >&2
    exit 1
fi

# Check branch is ahead of main
if ! git log "origin/main..HEAD" --oneline | grep -q .; then
    echo "Error: No commits ahead of origin/main." >&2
    echo "Fix: Commit your changes first." >&2
    exit 1
fi

# Get PR title
if [[ -n "${1:-}" ]]; then
    PR_TITLE="$*"
else
    ISSUE_TITLE="$(gh issue view "$ISSUE_NUM" --json title --jq '.title' 2>/dev/null)" || ISSUE_TITLE="issue ${ISSUE_NUM}"
    PR_TITLE="Fix #${ISSUE_NUM}: ${ISSUE_TITLE}"
fi

# Truncate title to 72 chars
if [[ ${#PR_TITLE} -gt 72 ]]; then
    PR_TITLE="${PR_TITLE:0:69}..."
fi

# Build PR body
if [[ -n "${SUMMARY:-}" ]]; then
    PR_BODY="$(cat <<EOF
## Summary

${SUMMARY}

## Test Plan

${TEST_PLAN:-Ran unit tests with \`pytest tests/unit_tests tests/rl/loss -vv\`}

Fixes #${ISSUE_NUM}
EOF
)"
elif [[ ! -t 0 ]]; then
    PR_BODY="$(cat)

Fixes #${ISSUE_NUM}"
else
    PR_BODY="Fixes #${ISSUE_NUM}"
fi

# Push to a remote branch with the same name (not the tracked upstream, which
# may be main). Without the explicit refspec, git could push to main.
git push -u origin "${CURRENT_BRANCH}:${CURRENT_BRANCH}"

gh pr create \
    --title "$PR_TITLE" \
    --body "$PR_BODY" \
    --base main

echo ""
echo "PR created and linked to issue #${ISSUE_NUM}."
