#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
# All rights reserved.
#
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree.

# Fetch a GitHub PR and output structured context for review.
#
# Usage:
#   fetch-pr.sh <pr-number>
#
# Output: Structured markdown with PR details, diff stats, and review comments.

set -euo pipefail

if [[ -z "${1:-}" ]]; then
    echo "Usage: fetch-pr.sh <pr-number>" >&2
    exit 1
fi

PR_NUM="$1"

# Check gh is authenticated
if ! gh auth status &>/dev/null; then
    echo "Error: gh is not authenticated." >&2
    echo "Fix: Run 'gh auth login' first." >&2
    exit 1
fi

# Fetch PR details
PR_JSON="$(gh pr view "$PR_NUM" --json title,body,state,author,createdAt,labels,reviews,headRefName,baseRefName,additions,deletions,changedFiles 2>&1)" || {
    echo "Error: Could not fetch PR #${PR_NUM}." >&2
    echo "Check: Does the PR exist? Are you in the right repo?" >&2
    exit 1
}

TITLE="$(echo "$PR_JSON" | jq -r '.title')"
STATE="$(echo "$PR_JSON" | jq -r '.state')"
AUTHOR="$(echo "$PR_JSON" | jq -r '.author.login')"
CREATED="$(echo "$PR_JSON" | jq -r '.createdAt' | cut -d'T' -f1)"
LABELS="$(echo "$PR_JSON" | jq -r '[.labels[].name] | join(", ")')"
HEAD="$(echo "$PR_JSON" | jq -r '.headRefName')"
BASE="$(echo "$PR_JSON" | jq -r '.baseRefName')"
ADDITIONS="$(echo "$PR_JSON" | jq -r '.additions')"
DELETIONS="$(echo "$PR_JSON" | jq -r '.deletions')"
CHANGED="$(echo "$PR_JSON" | jq -r '.changedFiles')"
BODY="$(echo "$PR_JSON" | jq -r '.body // "No description provided."')"
NUM_REVIEWS="$(echo "$PR_JSON" | jq -r '.reviews | length')"

cat <<EOF
# PR #${PR_NUM}: ${TITLE}

**State:** ${STATE} | **Author:** ${AUTHOR} | **Created:** ${CREATED}
**Branch:** ${HEAD} → ${BASE}
**Labels:** ${LABELS:-none}
**Stats:** +${ADDITIONS} -${DELETIONS} across ${CHANGED} files

## Description

${BODY}
EOF

# CI status
echo ""
echo "## CI Status"
echo ""
gh pr checks "$PR_NUM" 2>/dev/null || echo "No CI checks found."

# Diff
echo ""
echo "## Changed Files"
echo ""
gh pr diff "$PR_NUM" --stat 2>/dev/null || echo "Could not fetch diff stats."

echo ""
echo "## Full Diff"
echo ""
gh pr diff "$PR_NUM" 2>/dev/null || echo "Could not fetch diff."

# Reviews
if [[ "$NUM_REVIEWS" -gt 0 ]]; then
    echo ""
    echo "## Reviews (${NUM_REVIEWS})"
    echo ""
    echo "$PR_JSON" | jq -r '.reviews[] | "### \(.author.login) — \(.state)\n\n\(.body // "No comment.")\n\n---\n"'
fi
