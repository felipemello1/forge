---
name: oncall-report
description: >
  Generates an oncall report as a CSV with all open issues/PRs, staleness tracking,
  recommended actions, and AI-generated notes. Use when the user says "oncall report",
  "oncall status", or asks about open issues/PRs status.
---

# Oncall Report

## Step 1: Sync

```bash
python .claude/scripts/oncall-report.py sync
```

This fetches all open issues/PRs, recently closed items, and computes fields (age, idle days, CI status, reviewer, recommended action). It prints a tmpdir path to stdout and a summary to stderr.

Capture the tmpdir path from stdout.

## Step 2: Generate Notes

Read `<tmpdir>/updates.json`. For each item, generate a concise note (1-2 sentences max) summarizing the current state: what's the issue about, what's blocking it, what happened recently.

Write `<tmpdir>/notes.json` as a JSON object mapping issue/PR number (as string) to the note text:

```json
{"123": "OOM when batch_size > 32, author asked for repro steps", "456": "XPU support PR, awaiting review from maintainers"}
```

If `updates.json` is empty (`[]`), write an empty `notes.json` (`{}`).

## Step 3: Assemble

```bash
python .claude/scripts/oncall-report.py assemble <tmpdir>
```

This merges notes into the table, sorts it, and writes `reports/oncall.csv`. It prints the CSV path to stdout and a commit-message-ready summary to stderr.

## Step 4: Report

Show the user the summary from stderr and tell them where the CSV is. Do NOT auto-commit — let the user decide.
