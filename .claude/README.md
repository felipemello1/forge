# AI Development Setup

## Quick Reference

| Want to... | Use |
|------------|-----|
| Fix a GitHub issue | `/work-on-issue <number>` |
| Review a pull request | `/review-pr <number>` |
| Run tests | `/run-tests` |
| Generate oncall report | `/oncall-report` |

## File Structure

```
CLAUDE.md                           # Codebase context (always loaded)
.claude/
├── settings.json                   # Permissions + hooks
├── scripts/
│   ├── worktree-setup.sh           # Create worktree + branch
│   ├── worktree-cleanup.sh         # Remove worktree
│   ├── fetch-issue.sh              # GitHub issue → markdown
│   ├── fetch-pr.sh                 # GitHub PR → markdown
│   ├── open-pr.sh                  # Create PR linked to issue
│   ├── run-tests.sh               # pytest with project flags
│   └── oncall-report.py            # Fetch issues/PRs, compute fields, write CSV
├── hooks/
│   └── pre-pr-check.sh             # Block PR if on main or branch stale
├── templates/
│   └── pr-description.md           # PR body template
├── skills/
│   ├── work-on-issue/
│   │   └── SKILL.md                # Issue → TDD → PR
│   ├── review-pr/
│   │   └── SKILL.md                # Structured PR review
│   └── oncall-report/
│       └── SKILL.md                # Oncall status report → CSV
└── commands/
    └── run-tests.md                # Ad-hoc test runner
```

## Dependencies

```
/work-on-issue
  ├── fetch-issue.sh
  ├── worktree-setup.sh
  ├── run-tests.sh
  ├── open-pr.sh
  │   └── pr-description.md
  └── CLAUDE.md (for style/conventions)

/review-pr
  ├── fetch-pr.sh
  ├── review-criteria.md
  └── CLAUDE.md (for style/conventions)

/run-tests
  └── run-tests.sh
```

## Hooks

Hooks run automatically via `settings.json` — no manual invocation needed.

| Hook | Trigger | What it does |
|------|---------|-------------|
| `pre-pr-check.sh` | Any `gh pr create` command | Blocks if on main (wrong branch) or behind main (will show conflicts). Adapted from OpenEnv. |

Planned hooks (not yet implemented):
- `session-start.sh` — show mode/branch/issue banner on session start
- `tdd-guard.sh` — block src/ edits when TDD is active and no tests exist yet

## Adding a New Skill

1. Create `.claude/skills/<name>/SKILL.md`
2. Add a verification gate ("don't claim done until X passes")
3. Reference shared scripts — don't duplicate
4. Add an entry to this README
