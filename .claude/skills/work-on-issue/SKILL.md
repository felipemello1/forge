---
name: work-on-issue
description: >
  Resolves a GitHub issue end-to-end: fetches context, creates a worktree, writes
  failing tests (TDD), implements the fix, and opens a PR. Use when the user says
  "work on issue", "fix issue", or provides an issue number to resolve.
---

# Work on Issue

Copy this checklist and track progress:

```
- [ ] Fetch issue context
- [ ] Create worktree
- [ ] Read relevant code
- [ ] Plan approach
- [ ] Write failing test → verify it fails
- [ ] Implement fix → verify test passes
- [ ] Run full test suite
- [ ] Format and lint
- [ ] Commit and open PR
```

## Step 1: Fetch the Issue

```bash
.claude/scripts/fetch-issue.sh <ISSUE_NUMBER>
```

Understand: what's the bug/feature? Are there reproduction steps? Constraints in comments?

If the issue is unclear, ask the user for clarification before proceeding.

## Step 2: Create a Worktree

```bash
.claude/scripts/worktree-setup.sh <ISSUE_NUMBER>
```

Change your working directory to the new worktree. If already in a worktree or on a feature branch, skip this step.

**Important:** After switching to a worktree, all file reads and edits must use worktree paths (e.g., `/home/user/forge-issue-123/src/...`), not main repo paths. The tools require reading from the exact path you intend to edit.

## Step 3: Read Relevant Code

Before writing any code, read the files relevant to the issue. Refer to CLAUDE.md for architecture and conventions.

- Identify which files need to change
- Read the existing tests for those files
- Understand the patterns used (actor model, loss function pattern, config pattern)

Do NOT propose changes to code you haven't read.

## Step 4: Plan

**Bug fixes:** Identify the root cause. State it clearly.

**Features:** Outline in 3-5 bullets. If the change touches >3 files or involves an architectural decision, present the plan and wait for approval.

## Step 5: Write a Failing Test

Write a test that demonstrates the bug or validates the feature:

- Put it in `tests/unit_tests/` or `tests/rl/loss/`
- Class-based grouping: `class TestXxx`
- `torch.testing.assert_close` for numerical comparisons
- Descriptive name that explains what it tests

**Gate: test must fail.** Run it and confirm it fails for the expected reason:

```bash
.claude/scripts/run-tests.sh <test-file>::<TestClass>::<test_method>
```

If it passes, the bug doesn't exist or the feature already works — stop and report. If it fails for an unexpected reason (import error, fixture), fix the test, not the source.

## Step 6: Implement the Fix

Minimum code to make the test pass. Follow conventions from CLAUDE.md.

## Step 7: Verify

**Gate: your test passes.**
```bash
.claude/scripts/run-tests.sh <test-file>::<TestClass>::<test_method>
```

**Gate: full suite passes.**
```bash
.claude/scripts/run-tests.sh
```

If anything fails, fix it before proceeding.

## Step 8: Format and Lint

```bash
pre-commit run --all-files
```

## Step 9: Commit and Open PR

```bash
git add <specific-files>
git commit -m "$(cat <<'EOF'
Fix <brief description> (#<ISSUE_NUMBER>)

<1-2 sentence explanation of root cause and fix>
EOF
)"
```

Then open the PR:
```bash
SUMMARY="<what changed and why>" \
TEST_PLAN="<how it was tested>" \
.claude/scripts/open-pr.sh <ISSUE_NUMBER>
```

**Gate: PR quality.**
- [ ] Title under 72 chars
- [ ] Body has Summary + Test Plan
- [ ] References `Fixes #N`
- [ ] No debug prints, commented-out code, or TODOs

## Done

Report: what the issue was, root cause (for bugs), what you changed, the PR link, any concerns.
