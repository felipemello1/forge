---
name: review-pr
description: >
  Reviews a GitHub PR against TorchForge's conventions. Fetches the diff, checks
  correctness, style, test coverage, and torch.compile safety, then posts actionable
  comments. Use when the user says "review PR" or asks for code review on a PR number.
allowed-tools: Read, Grep, Glob, Bash
---

# Review PR

## Step 1: Fetch the PR

```bash
.claude/scripts/fetch-pr.sh <PR_NUMBER>
```

Understand: what does this PR do? What files changed? Is there a linked issue? CI status?

## Step 2: Read the Diff

Read every changed file. For each file, read enough surrounding code to understand context — don't review in isolation.

## Step 3: Review

Check against the criteria in [review-criteria.md](review-criteria.md). Focus on:

1. **Correctness** — does it do what it claims? Edge cases?
2. **Tests** — bug fixes MUST have a test. Are they in the right place?
3. **torch.compile** — hot path changes must be compile-safe
4. **Style** — matches CLAUDE.md conventions?
5. **Bloat** — unrelated changes? Unnecessary abstractions?

## Step 4: Post Review

```
## Summary
<1-2 sentences: what this PR does, overall assessment>

## Issues
<Specific problems with file:line references. Each must be actionable.>

## Suggestions
<Optional improvements that don't block merging>

## Verdict
<APPROVE / REQUEST CHANGES / COMMENT>
```

Post via:
```bash
gh pr review <PR_NUMBER> --comment --body "<review>"
```

## What Makes a Good Review

- **Be specific.** "Line 45: `foo` should be `bar` because X"
- **Be actionable.** Every issue tells the author what to do.
- **Don't nitpick style** if pre-commit handles it.
- **Don't suggest bloat.** No extra abstractions, error handling, or features.
- **Do catch correctness bugs.** Wrong math, broken compile, race conditions.
