# TorchForge Review Criteria

Review each PR against these Forge-specific checks. This supplements CLAUDE.md conventions.

## Correctness

- Does the code do what the PR claims?
- For RL/loss changes: is the math correct? Trace through with concrete numbers if needed.
- For actor changes: are endpoints properly async? Is `setup()` used for heavy init (not `__init__`)?
- Are there edge cases not handled?

## torch.compile Compatibility

- Hot path code (loss functions, model forward) must not break the graph
- No data-dependent control flow in compiled regions
- No in-place ops on views
- No Python-side logging or metrics in compiled regions
- Did the author test with `torch.compile`?

## Test Coverage

- Bug fixes MUST have a test that would have caught the bug
- Tests in the right directory: `tests/unit_tests/` or `tests/rl/loss/`
- Class-based grouping: `class TestXxx`
- `torch.testing.assert_close` for numerical comparisons (not `assertEqual`)
- Tests verify behavior, not just "it runs without error"

## Style (beyond what pre-commit catches)

- Composition over inheritance (max 1 level)
- No unnecessary abstractions or helpers
- No "just in case" fields or parameters
- Type hints: `X | None` not `Optional[X]`
- No backward-compatibility hacks (unused renamed `_vars`, `# removed` comments)

## Config Changes

- Field names correct and consistent with existing configs?
- `@parse` / OmegaConf resolution still works?
- Custom resolvers (`${sum:}`, `${not:}`, `${oc.env:}`) used correctly?

## vLLM Changes

- Works for both v0 (`actors/vllm/v0/`) and v1 (`actors/vllm/v1/`)?
- `generator.py` auto-detection logic still correct?

## Observability

- `record_metric` calls use correct `Reduce` mode?
- Metrics disabled in tests? (`FORGE_DISABLE_METRICS=true` via `tests/conftest.py`)

## No Bloat

- Unrelated changes mixed in?
- Comments/docstrings/type annotations added to unchanged code?
- Unnecessary refactoring?
