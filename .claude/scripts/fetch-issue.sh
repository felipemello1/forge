#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
# All rights reserved.
#
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree.

# Fetch a GitHub issue and output clean markdown for Claude to consume.
#
# Usage:
#   fetch-issue.sh <issue-number>
#
# Output: Structured markdown with title, labels, body, and comments.

set -euo pipefail

if [[ -z "${1:-}" ]]; then
    echo "Usage: fetch-issue.sh <issue-number>" >&2
    exit 1
fi

ISSUE_NUM="$1"

# Check gh is authenticated
if ! gh auth status &>/dev/null; then
    echo "Error: gh is not authenticated." >&2
    echo "Fix: Run 'gh auth login' first." >&2
    exit 1
fi

# Fetch issue details as JSON
ISSUE_JSON="$(gh issue view "$ISSUE_NUM" --json title,body,labels,state,author,createdAt,comments 2>&1)" || {
    echo "Error: Could not fetch issue #${ISSUE_NUM}." >&2
    echo "Check: Does the issue exist? Are you in the right repo?" >&2
    echo "Debug: gh issue view $ISSUE_NUM" >&2
    exit 1
}

# Extract fields
TITLE="$(echo "$ISSUE_JSON" | jq -r '.title')"
STATE="$(echo "$ISSUE_JSON" | jq -r '.state')"
AUTHOR="$(echo "$ISSUE_JSON" | jq -r '.author.login')"
CREATED="$(echo "$ISSUE_JSON" | jq -r '.createdAt' | cut -d'T' -f1)"
LABELS="$(echo "$ISSUE_JSON" | jq -r '[.labels[].name] | join(", ")')"
BODY="$(echo "$ISSUE_JSON" | jq -r '.body // "No description provided."')"
NUM_COMMENTS="$(echo "$ISSUE_JSON" | jq -r '.comments | length')"

# Output structured markdown
cat <<EOF
# Issue #${ISSUE_NUM}: ${TITLE}

**State:** ${STATE} | **Author:** ${AUTHOR} | **Created:** ${CREATED}
**Labels:** ${LABELS:-none}

## Description

${BODY}
EOF

# Add comments if any
if [[ "$NUM_COMMENTS" -gt 0 ]]; then
    echo ""
    echo "## Comments (${NUM_COMMENTS})"
    echo ""
    echo "$ISSUE_JSON" | jq -r '.comments[] | "### \(.author.login) (\(.createdAt | split("T")[0]))\n\n\(.body)\n\n---\n"'
fi
