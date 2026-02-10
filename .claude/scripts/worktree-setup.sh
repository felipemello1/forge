#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
# All rights reserved.
#
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree.

# Create a git worktree for working on an issue or arbitrary branch.
#
# Usage:
#   worktree-setup.sh <issue-number>          # creates branch issue-<N>
#   worktree-setup.sh --branch <branch-name>  # uses explicit branch name
#
# The worktree is created at ../forge-issue-<N> (sibling to the main repo).
# If the worktree already exists, the script exits with an error.

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel)"
REPO_NAME="$(basename "$REPO_ROOT")"

# Parse arguments
if [[ "${1:-}" == "--branch" ]]; then
    if [[ -z "${2:-}" ]]; then
        echo "Error: --branch requires a branch name" >&2
        exit 1
    fi
    BRANCH="$2"
    WORKTREE_DIR="$(dirname "$REPO_ROOT")/${REPO_NAME}-${BRANCH}"
elif [[ -n "${1:-}" ]]; then
    ISSUE_NUM="$1"
    BRANCH="issue-${ISSUE_NUM}"
    WORKTREE_DIR="$(dirname "$REPO_ROOT")/${REPO_NAME}-issue-${ISSUE_NUM}"
else
    echo "Usage: worktree-setup.sh <issue-number>" >&2
    echo "       worktree-setup.sh --branch <branch-name>" >&2
    exit 1
fi

# Check if worktree already exists
if [[ -d "$WORKTREE_DIR" ]]; then
    echo "Error: Worktree already exists at $WORKTREE_DIR" >&2
    echo "Run worktree-cleanup.sh to remove it first." >&2
    exit 1
fi

# Get the default branch (usually main)
DEFAULT_BRANCH="$(git -C "$REPO_ROOT" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo main)"

# Fetch latest from remote
git -C "$REPO_ROOT" fetch origin "$DEFAULT_BRANCH" --quiet

# Create the worktree from the latest default branch.
# --no-track: don't track origin/main, so `git push origin <branch>` pushes
# to a remote branch of the same name instead of accidentally pushing to main.
git -C "$REPO_ROOT" worktree add --no-track -b "$BRANCH" "$WORKTREE_DIR" "origin/$DEFAULT_BRANCH"

echo "Worktree created:"
echo "  Path:   $WORKTREE_DIR"
echo "  Branch: $BRANCH"
echo "  Base:   origin/$DEFAULT_BRANCH"
