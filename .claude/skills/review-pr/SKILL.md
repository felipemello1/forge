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

Check against the conventions in CLAUDE.md. Focus on correctness, test coverage, torch.compile safety, and whether the change introduces unnecessary complexity.

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
