#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
# All rights reserved.
#
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree.

# Remove a git worktree created by worktree-setup.sh.
#
# Usage:
#   worktree-cleanup.sh <issue-number>          # removes worktree for issue-<N>
#   worktree-cleanup.sh --branch <branch-name>  # removes worktree for branch
#   worktree-cleanup.sh --all                   # removes ALL forge worktrees
#
# By default, the local branch is also deleted. Use --keep-branch to keep it.

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel)"
REPO_NAME="$(basename "$REPO_ROOT")"
KEEP_BRANCH=false

# Parse arguments
if [[ "${1:-}" == "--all" ]]; then
    # List and remove all worktrees except the main one
    echo "Removing all worktrees..."
    git -C "$REPO_ROOT" worktree list --porcelain | grep "^worktree " | awk '{print $2}' | while read -r wt; do
        if [[ "$wt" != "$REPO_ROOT" ]]; then
            echo "  Removing: $wt"
            git -C "$REPO_ROOT" worktree remove --force "$wt" 2>/dev/null || true
        fi
    done
    git -C "$REPO_ROOT" worktree prune
    echo "Done."
    exit 0
fi

if [[ "${1:-}" == "--branch" ]]; then
    BRANCH="${2:-}"
    if [[ -z "$BRANCH" ]]; then
        echo "Error: --branch requires a branch name" >&2
        exit 1
    fi
    WORKTREE_DIR="$(dirname "$REPO_ROOT")/${REPO_NAME}-${BRANCH}"
    shift 2
elif [[ -n "${1:-}" && "${1:-}" != "--keep-branch" ]]; then
    ISSUE_NUM="$1"
    BRANCH="issue-${ISSUE_NUM}"
    WORKTREE_DIR="$(dirname "$REPO_ROOT")/${REPO_NAME}-issue-${ISSUE_NUM}"
    shift
else
    echo "Usage: worktree-cleanup.sh <issue-number>" >&2
    echo "       worktree-cleanup.sh --branch <branch-name>" >&2
    echo "       worktree-cleanup.sh --all" >&2
    exit 1
fi

if [[ "${1:-}" == "--keep-branch" ]]; then
    KEEP_BRANCH=true
fi

# Remove the worktree
if [[ -d "$WORKTREE_DIR" ]]; then
    git -C "$REPO_ROOT" worktree remove --force "$WORKTREE_DIR"
    echo "Removed worktree: $WORKTREE_DIR"
else
    echo "Warning: Worktree not found at $WORKTREE_DIR" >&2
fi

# Prune stale worktree references
git -C "$REPO_ROOT" worktree prune

# Delete the branch unless told to keep it
if [[ "$KEEP_BRANCH" == false && -n "${BRANCH:-}" ]]; then
    if git -C "$REPO_ROOT" branch --list "$BRANCH" | grep -q .; then
        git -C "$REPO_ROOT" branch -D "$BRANCH"
        echo "Deleted branch: $BRANCH"
    fi
fi

echo "Cleanup complete."
