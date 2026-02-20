# Oncall Report Skill — Proposal

## User Feedback (accumulated during design)

- Notes column should be AI-generated, not human-written — this is where AI adds real value
- Only re-read issues/PRs with new activity since last run — saves LLM context
- Output must be CSV: openable in Google Sheets / Excel, AND renderable on GitHub
- Multi-section layout (needs attention / on track / closed) → a `Section` column, not separate tables
- Deterministic work (fetching, computing fields, sorting) belongs in scripts — Claude only generates notes
- This is NOT auto-triage (PyTorch's approach). Auto-triage solves routing at scale. This solves awareness for a small team. Different problems.
- Closed/merged items don't need AI notes — deterministic strings ("merged", "closed: not planned") suffice

---

## Problem Statement

Small team oncall pain points:
1. **Handoff amnesia** — new oncall inherits zero context about what's in-flight
2. **Silent staleness** — PRs wait weeks for review, nobody notices
3. **Manual meeting prep** — someone scrambles to build a summary before the weekly
4. **No single source of truth** — state is scattered across GitHub notifications, Slack, and memory

## Solution

A Claude Code skill (`/oncall-report`) that:
1. Fetches all open issues/PRs from GitHub
2. Computes staleness, ownership, CI status, and recommended actions
3. Uses AI to generate concise notes only for items with new activity
4. Writes a CSV to `reports/oncall.csv` and commits it

## Output Format

Single CSV file at `reports/oncall.csv`. GitHub renders it as a sortable table. Sheets/Excel open it natively.

### Columns

```csv
Number,Title,Type,Section,Owner,Reviewer,Reviewer Days,Age,Idle,CI,Linked PR,Action,Notes
```

- `Number` — issue/PR number
- `Title` — title
- `Type` — `issue` or `PR`
- `Section` — `action needed`, `on track`, or `closed this week`
- `Owner` — assignee (issues) or author (PRs)
- `Reviewer` — reviewer name (PRs only)
- `Reviewer Days` — days reviewer has had the PR (numeric, for sorting)
- `Age` — days since opened (numeric)
- `Idle` — days since last activity (numeric)
- `CI` — `pass`, `fail`, or empty (issues)
- `Linked PR` — PR number linked to an issue (if any)
- `Action` — computed recommendation (see rules below)
- `Notes` — AI-generated 1-line summary of current state

### Section Assignment Rules

An item is `action needed` if ANY of:
- No owner/assignee (needs triage)
- Idle > 7 days (going stale)
- CI failing (PR needs fix)
- PR has no reviewer assigned
- Reviewer waiting > 5 days
- Changes requested + author idle > 3 days

Otherwise: `on track`.

Recently closed/merged items (last 7 days): `closed this week`.

### Action Rules

| State | Action |
|-------|--------|
| Issue, no assignee, no labels | `triage` |
| Issue, assigned, idle > 7d | `ping owner or deprioritize` |
| Issue, idle > 30d, no assignee | `close?` |
| PR, no reviewer | `needs reviewer` |
| PR, CI failing | `author: fix CI` |
| PR, approved + CI passing | `merge` |
| PR, changes requested, author idle > 3d | `ping author` |
| PR, merge conflicts | `author: rebase` |
| PR, many comments, no resolution | `discuss in meeting` |
| On track item | (empty) |
| Closed/merged | (empty) |

### Sort Order

1. `action needed` first (sorted by Idle descending — stalest at top)
2. `on track` (sorted by Idle descending)
3. `closed this week` (sorted by close date descending)

### Commit Message

The commit message carries the summary so `git log` is useful:

```
oncall report: 2026-02-13 | Open: 8 issues, 3 PRs | Stale: 2 | Since last: +1 new, 1 merged
```

## Architecture

### Data Flow

```
oncall-sync.py                     Claude                      oncall-assemble.py
┌─────────────────────┐     ┌──────────────────┐     ┌─────────────────────────┐
│ gh issue list       │     │ Read updates.json │     │ Read draft.csv          │
│ gh pr list          │     │ Generate 1-line   │     │ Read notes.json         │
│ Read existing CSV   │────▶│ note per item     │────▶│ Merge notes into table  │
│ Compute all fields  │     │ Write notes.json  │     │ Sort by section + idle  │
│ Diff: what changed? │     └──────────────────┘     │ Write oncall.csv        │
│ Download changed    │                               │ Print commit message    │
│ Write draft.csv     │                               └─────────────────────────┘
│ Write updates.json  │
└─────────────────────┘
```

### Files

```
.claude/
  skills/oncall-report/SKILL.md       # Orchestrates the 3 steps
  scripts/
    oncall-sync.py                    # Fetch, compute, diff, download
    oncall-assemble.py                # Merge notes, sort, write final CSV

reports/oncall.csv                    # The output (committed to git)
```

### oncall-sync.py

Input: `reports/oncall.csv` (if exists)
Output: `<tmpdir>/draft.csv` + `<tmpdir>/updates.json`

Steps:
1. `gh issue list --state open --json number,title,assignee,labels,createdAt,updatedAt`
2. `gh pr list --state open --json number,title,author,reviews,reviewRequests,createdAt,updatedAt,statusCheckRollup`
3. `gh issue list --state closed` (last 7 days)
4. `gh pr list --state merged` (last 7 days)
5. Read existing `reports/oncall.csv` to get previous notes + last run date
6. For each item, compute: age, idle, CI, reviewer, reviewer_days, linked_pr, section, action
7. For closed/merged: set notes deterministically ("merged", "closed: not planned", "fixed by #N")
8. For open items where `updatedAt > last_run_date`: fetch full content via `gh issue view <N> --json body,comments` or `gh pr view <N> --json body,comments,reviews`
9. For open items where `updatedAt <= last_run_date`: keep existing note from CSV
10. Write `draft.csv` (all rows with computed fields; notes filled for unchanged items, empty for changed)
11. Write `updates.json` (array of `{number, title, type, body, recent_comments}` for items needing AI notes)
12. Print to stdout: "12 items total, 3 need note updates, 2 newly closed"

### Claude (SKILL.md)

1. Run `oncall-sync.py`, capture stdout summary and tmpdir path
2. Read `<tmpdir>/updates.json`
3. For each item: generate a concise 1-line note (what's happening, what's blocking)
4. Write `<tmpdir>/notes.json`: `{"123": "Author can't repro, asked for env details", "456": "Segfault in collate with mixed-length batches"}`
5. Run `oncall-assemble.py <tmpdir>/draft.csv <tmpdir>/notes.json`
6. `git add reports/oncall.csv && git commit -m "<commit message from stdout>"`

### oncall-assemble.py

Input: `draft.csv` + `notes.json`
Output: `reports/oncall.csv` + commit message on stdout

Steps:
1. Read `draft.csv`
2. Read `notes.json`, fill in empty notes
3. Sort: action needed first (idle desc), on track (idle desc), closed this week (close date desc)
4. Write `reports/oncall.csv`
5. Print commit message to stdout
6. Clean up temp files

## Usage Scenarios

### Scenario 1: Monday morning, new oncall rotation
```
> /oncall-report
```
First run: all items fetched, all notes generated. Opens CSV on GitHub or Sheets.

### Scenario 2: Mid-week check
```
> /oncall-report
```
3 of 12 items had activity. Only those 3 get new notes. Others just increment idle days. Git diff shows what changed.

### Scenario 3: Before weekly meeting
Run `/oncall-report`, open in Sheets, filter `Section = action needed`, share screen. Go row by row.

### Scenario 4: "What happened this week?"
```
git log --oneline reports/oncall.csv
```
Commit messages show daily summaries.

### Scenario 5: Oncall handoff
New oncall reads CSV. Notes column has context: "Author says fix coming next week", "Blocked on vLLM v1 release". No context lost.

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| CSV not markdown | Opens in Sheets/Excel. GitHub renders it as sortable table. Best of both worlds. |
| Python not bash | CSV parsing, date arithmetic, JSON manipulation are painful in bash+jq. |
| Scripts handle 90% | Deterministic work (fetch, compute, sort) doesn't need LLM tokens. |
| AI only for notes | The one place where summarization adds value over computation. |
| Single file, git-tracked | Diffs show changes. History survives oncall rotation. Blame shows who ran it. |
| Commit message as summary | `git log` becomes the trend line without opening the file. |
| No auto-actions | No auto-close, auto-assign, or GitHub comments. Read-only reporter. |
| 7-day window for closed items | Keeps the table bounded. Older closed items are in git history. |

---

## Review Findings (3 independent critics)

### Bugs in the Proposal

These are factual errors that must be fixed before implementation.

- **`gh pr list --state merged` does not exist.** Valid states are `open`, `closed`, `all`. Merged PRs have state `closed`. Must use `gh pr list --state closed --json mergedAt` and filter by `mergedAt != null && mergedAt > 7 days ago`.
- **`last_run_date` is undefined.** The proposal says "Read existing CSV to get previous notes + last run date" but the CSV schema has no `last_run_date` field. Options: (a) use the CSV file's git commit timestamp, (b) store a `_metadata` row or separate file, (c) store per-item `updatedAt` in a hidden column. Git commit timestamp is simplest but breaks if the CSV is manually edited.
- **Missing `mergeable` field.** The action rule "PR, merge conflicts → `author: rebase`" requires `gh pr view --json mergeable`, but this field isn't in the `gh pr list` JSON query. Must be fetched per-PR.
- **No `Closed Date` column** but the sort order requires sorting closed items by close date. Either add a hidden column or compute sort order differently.
- **stdout serves double duty.** `oncall-sync.py` prints a summary to stdout AND `oncall-assemble.py` prints a commit message to stdout. The SKILL.md must parse these separately. Use stderr for the summary and stdout for the commit message, or write the commit message to a file.

### Column Issues

- **`Owner` is semantically overloaded.** For issues it's the assignee (who should work on it). For PRs it's the author (who wrote it). This is confusing — when a PR needs action, sometimes the author needs to act (fix CI), sometimes the reviewer does (review it). Consider splitting into `Author` + `Assignee` or renaming to something less ambiguous.
- **`Labels` column missing.** The action rules reference labels ("Issue, no assignee, no labels → triage") but there's no Labels column in the CSV. Add it or remove labels from the action rules.
- **`Reviewer Days` undefined when no reviewer.** Empty string breaks numeric sorting. 0 is misleading. Proposal should specify: empty string for issues, empty string for PRs with no reviewer.
- **CI aggregation unspecified.** `statusCheckRollup` returns an array. What if some checks pass and others fail? What about `pending` or `skipped`? Need aggregation logic: `fail` if any fail, `pending` if any pending and none fail, `pass` otherwise.
- **Changes Requested detection is non-trivial.** Requires finding the most recent review per reviewer and checking if state is `CHANGES_REQUESTED`. Not a simple field lookup.

### Workflow Gaps

- **Worktree confusion.** If run from a worktree, `reports/oncall.csv` goes to the worktree, not the main repo. The skill should either detect this and error, or always resolve to the main repo root.
- **Uncommitted changes.** The skill ends with `git commit`. What if there are uncommitted changes to other files? The skill should only stage `reports/oncall.csv`, never `git add -A`.
- **Branch protection unresolved.** If main requires PRs, the commit succeeds locally but can't be pushed. The skill should detect this or document it.
- **First run is expensive.** 30 open items = 30 AI note generations. Need progress indication and a `--skip-notes` fallback.
- **Interrupted runs leave temp files.** If the skill is Ctrl+C'd between sync and assemble, `draft.csv` and `updates.json` are orphaned. Next run re-creates them, but cleanup should be explicit.
- **`updatedAt` is noisy.** GitHub fires `updatedAt` on bot comments, label changes, milestone changes, and cross-references. A bot adding a label resets the idle counter and triggers unnecessary note regeneration. Consider filtering bot activity.

### Note Quality

- **Unbounded comment volume.** An issue with 50+ comments gets all of them in `updates.json`. This blows up context. Cap at last 5-10 comments, or last N that are from humans (not bots).
- **1-line too rigid.** Complex issues need more context. Use a character limit (~200 chars) rather than a line count.
- **Stale notes.** An item idle 30+ days keeps its original note. The note may say "Author says fix coming next week" from 5 weeks ago. Consider forcing note regeneration after N days of idle, or appending "(noted Feb 1)" to preserved notes.

### Meeting UX

- **GitHub CSV can't filter, only sort.** The "filter by Section in Sheets" workflow requires downloading the file. Consider printing a meeting-ready summary to stdout (not committed) that lists action-needed items in a readable format.
- **13 columns may be too wide** for GitHub's CSV renderer. Horizontal scrolling makes Notes (the most useful column, placed last) invisible without scrolling. Reorder to put high-value columns first.

### Philosophy Alignment

- **Is the 3-stage pipeline over-engineered?** A single `oncall-report.py` that calls `gh`, computes fields, invokes Claude inline for notes, and writes the CSV would eliminate tmpdir/JSON coordination. The 3-stage design implies parallelism that doesn't exist — Claude runs synchronously between the two scripts anyway.
- **Speculative columns.** Does Forge actually use issue-PR linking? Does it assign formal reviewers? If not, `Linked PR` and `Reviewer`/`Reviewer Days` are always empty.
- **Thresholds (7d, 5d, 3d) are unjustified.** Are these based on Forge's actual workflow or generic defaults?

### Alternatives Worth Considering

- **GitHub Action + Discussion/Wiki** instead of committed CSV. Avoids CI triggers, merge conflicts, and git history pollution from daily auto-commits.
- **Deterministic last-comment** instead of AI notes. First 80 chars of the most recent human comment is free, deterministic, and often captures the state. AI notes add value only for long/complex threads.
- **GitHub Project Board** auto-populated by `gh project`. Native filtering, sorting, assignment without CSV.
