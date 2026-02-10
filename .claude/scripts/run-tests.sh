#!/bin/bash
# Copyright (c) Meta Platforms, Inc. and affiliates.
# All rights reserved.
#
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree.

# Run tests with the correct project flags.
#
# Usage:
#   run-tests.sh                    # run all unit + loss tests
#   run-tests.sh tests/rl/loss      # run only loss tests
#   run-tests.sh tests/unit_tests/test_service.py  # run specific file
#   run-tests.sh --quick            # run with fail-fast (-x)
#
# Note: Unit tests require a GPU. Integration tests (8 GPUs) are NOT
# run by this script — those only run in CI on push to main.

set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel)"

PYTEST_ARGS=(-vv --tb=short --durations=10)
TEST_PATHS=()

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --quick)
            PYTEST_ARGS+=(-x)
            ;;
        --*)
            PYTEST_ARGS+=("$arg")
            ;;
        *)
            TEST_PATHS+=("$arg")
            ;;
    esac
done

# Default: run unit tests + loss tests
if [[ ${#TEST_PATHS[@]} -eq 0 ]]; then
    TEST_PATHS=("${REPO_ROOT}/tests/unit_tests" "${REPO_ROOT}/tests/rl/loss")
fi

echo "Running: pytest ${PYTEST_ARGS[*]} ${TEST_PATHS[*]}"
echo ""

# Use PYTHONPATH so tests import from this directory's src/, not from wherever
# pip install -e was last run. Critical for worktrees to test their own code.
cd "$REPO_ROOT"
PYTHONPATH="${REPO_ROOT}/src:${PYTHONPATH:-}" python -m pytest "${PYTEST_ARGS[@]}" "${TEST_PATHS[@]}"
