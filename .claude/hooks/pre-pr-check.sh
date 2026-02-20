#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
# All rights reserved.
#
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree.

# PreToolUse hook: blocks `gh pr create` if on main or behind the base branch.
# Exit 0 = allow, exit 2 = block with error message.

# Read JSON from stdin (Claude Code passes tool input as JSON)
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)

# Only intercept `gh pr create` commands — let everything else through
if [[ "$COMMAND" != *"gh pr create"* ]]; then
    exit 0
fi

# Determine base branch (default: main, or read from --base flag)
BASE="main"
if echo "$COMMAND" | grep -qoP '(?<=--base\s)\S+'; then
    BASE=$(echo "$COMMAND" | grep -oP '(?<=--base\s)\S+')
fi

# Check: are we on main? That's almost certainly a mistake.
BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ "$BRANCH" == "main" || "$BRANCH" == "master" ]]; then
    cat >&2 << EOF

===================================================================
  PR BLOCKED: Cannot create PR from $BRANCH
===================================================================

  Create a feature branch first:
    .claude/scripts/worktree-setup.sh <issue-number>

===================================================================

EOF
    exit 2
fi

# Check: is the branch behind the base? PR will show merge conflicts.
git fetch origin "$BASE" --quiet 2>/dev/null || true
BEHIND=$(git rev-list --count HEAD.."origin/$BASE" 2>/dev/null || echo "?")

if [[ "$BEHIND" != "0" && "$BEHIND" != "?" ]]; then
    cat >&2 << EOF

===================================================================
  PR BLOCKED: Branch is $BEHIND commit(s) behind $BASE
===================================================================

  Your PR will show "out of date with base branch" on GitHub.

  Fix with:
    git fetch origin $BASE
    git rebase origin/$BASE
    git push --force-with-lease

  Then retry gh pr create.

===================================================================

EOF
    exit 2
fi

exit 0
