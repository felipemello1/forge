Run the project test suite using the correct flags and directories.

Use the project's test runner script:

```bash
.claude/scripts/run-tests.sh
```

This runs all unit tests and loss tests with `-vv --tb=short --durations=10`.

For a specific test file or directory, pass it as an argument:

```bash
.claude/scripts/run-tests.sh tests/rl/loss/test_grpo.py
```

For fail-fast mode (stop at first failure):

```bash
.claude/scripts/run-tests.sh --quick
```

Notes:
- Unit tests require a GPU
- Integration tests (8 GPUs) are NOT included — those only run in CI
- If tests fail on import, check that dependencies are installed: `uv pip install .[dev]`
