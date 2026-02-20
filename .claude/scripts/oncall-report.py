#!/usr/bin/env python3
# Copyright (c) Meta Platforms, Inc. and affiliates.
# All rights reserved.
#
# This source code is licensed under the BSD-style license found in the
# LICENSE file in the root directory of this source tree.

"""Oncall report: fetch GitHub issues/PRs, compute fields, write CSV.

Usage:
    oncall-report.py sync [--limit N] [--repo OWNER/REPO]
    oncall-report.py assemble <tmpdir>
"""

import csv
import json
import os
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path


def _clean_env():
    env = os.environ.copy()
    env.pop("LD_LIBRARY_PATH", None)
    env.pop("LD_PRELOAD", None)
    return env


def gh(args: list[str]) -> list[dict] | dict:
    r = subprocess.run(["gh"] + args, capture_output=True, text=True, env=_clean_env())
    if r.returncode != 0:
        print(f"gh error: {r.stderr.strip()}", file=sys.stderr)
        return []
    return json.loads(r.stdout) if r.stdout.strip() else []


def days_ago(iso: str) -> int:
    return (
        datetime.now(timezone.utc) - datetime.fromisoformat(iso.replace("Z", "+00:00"))
    ).days


def ci_status(checks: list[dict]) -> str:
    real = [c for c in checks if c.get("workflowName") not in ("", "Docs")]
    if not real:
        return ""
    conclusions = [c.get("conclusion", "") for c in real]
    if "FAILURE" in conclusions:
        return "fail"
    if all(c in ("SUCCESS", "SKIPPED") for c in conclusions):
        return "pass"
    return "pending"


def latest_review(reviews: list[dict]) -> tuple[str, str, int]:
    if not reviews:
        return "", "", 0
    by_author = {}
    for r in reviews:
        login = r.get("author", {}).get("login", "")
        if login:
            by_author[login] = r
    if not by_author:
        return "", "", 0
    latest = max(by_author.values(), key=lambda r: r.get("submittedAt", ""))
    return (
        latest["author"]["login"],
        latest.get("state", ""),
        days_ago(latest["submittedAt"]) if latest.get("submittedAt") else 0,
    )


def action_for(row: dict) -> str:
    t, idle, ci = row["Type"], row["Idle"], row["CI"]
    owner, reviewer = row["Owner"], row["Reviewer"]
    labels = set(row.get("Labels", "").split(", ")) - {""}
    review_state = row.get("_review_state", "")

    if t == "issue":
        # Label-aware priority
        if "high priority" in labels and "triage review" in labels:
            return "discuss: high priority"
        if "triage review" in labels:
            return "discuss in meeting"
        if "question" in labels and idle > 7:
            return "answer or close"
        if "triaged" in labels:
            if owner and idle > 14:
                return "waiting on owner"
            return ""  # triaged = someone looked at it, lower urgency
        # No labels
        if not owner and idle > 30:
            return "close?"
        if not labels and not owner:
            return "triage"
        if owner and idle > 7:
            return "waiting on owner"
        return ""

    # PR
    if ci == "fail":
        return "author: fix CI"
    if review_state == "APPROVED" and ci == "pass":
        return "merge"
    if review_state == "CHANGES_REQUESTED" and idle > 3:
        return "waiting on author"
    if not reviewer:
        return "needs reviewer"
    rd = row["Reviewer Days"]
    if rd and int(rd) > 5:
        return "waiting on review"
    return ""


def section_for(row: dict) -> str:
    if row.get("_closed"):
        return "closed this week"
    action = row["Action"]
    if action:
        return "action needed"
    if row["Idle"] > 7:
        return "action needed"
    return "on track"


def priority_sort_key(row: dict) -> tuple:
    """Sort key: high-priority first, then by section, then by idle days."""
    section_order = {"action needed": 0, "on track": 1, "closed this week": 2}
    labels = row.get("Labels", "")
    has_high = 0 if "high priority" in labels else 1
    return (section_order.get(row["Section"], 9), has_high, -int(row.get("Idle") or 0))


FIELDS = [
    "Number",
    "Title",
    "Type",
    "Section",
    "Labels",
    "Owner",
    "Reviewer",
    "Reviewer Days",
    "Age",
    "Idle",
    "CI",
    "Action",
    "Notes",
]


def repo_root() -> Path:
    return Path(
        subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            env=_clean_env(),
        ).stdout.strip()
    )


# ── sync ──────────────────────────────────────────────────────────────────────


def cmd_sync(limit: int = 200, repo: str | None = None):
    root = repo_root()
    csv_path = root / "reports" / "oncall.csv"
    outdir = Path(tempfile.mkdtemp(prefix="oncall-"))
    repo_flag = ["--repo", repo] if repo else []

    # Previous notes
    prev = {}
    if csv_path.exists():
        with open(csv_path) as f:
            for r in csv.DictReader(f):
                prev[r["Number"]] = r.get("Notes", "")

    print("Fetching issues and PRs...", file=sys.stderr)
    issues = gh(
        [
            "issue",
            "list",
            "--state",
            "open",
            "--limit",
            str(limit),
            "--json",
            "number,title,assignees,labels,createdAt,updatedAt",
        ]
        + repo_flag
    )
    prs = gh(
        [
            "pr",
            "list",
            "--state",
            "open",
            "--limit",
            str(limit),
            "--json",
            "number,title,author,labels,reviews,reviewRequests,createdAt,updatedAt,statusCheckRollup",
        ]
        + repo_flag
    )
    closed_prs = gh(
        [
            "pr",
            "list",
            "--state",
            "closed",
            "--limit",
            "30",
            "--json",
            "number,title,author,createdAt,closedAt,mergedAt",
        ]
        + repo_flag
    )
    closed_issues = gh(
        [
            "issue",
            "list",
            "--state",
            "closed",
            "--limit",
            "30",
            "--json",
            "number,title,createdAt,closedAt,stateReason",
        ]
        + repo_flag
    )

    rows, needs_update = [], []

    for i in issues:
        n = i["number"]
        assignees = i.get("assignees") or []
        owner = assignees[0]["login"] if assignees else ""
        labels = ", ".join(l["name"] for l in i.get("labels", []))
        idle = days_ago(i["updatedAt"])
        row = dict(
            Number=n,
            Title=i["title"],
            Type="issue",
            Owner=owner,
            Labels=labels,
            Reviewer="",
            **{"Reviewer Days": ""},
            Age=days_ago(i["createdAt"]),
            Idle=idle,
            CI="",
            Notes=prev.get(str(n), ""),
            _review_state="",
            _closed=False,
        )
        row["Action"] = action_for(row)
        row["Section"] = section_for(row)
        rows.append(row)
        if not row["Notes"]:
            needs_update.append(
                dict(number=n, title=i["title"], type="issue", labels=labels)
            )

    for p in prs:
        n = p["number"]
        author = p.get("author", {}).get("login", "")
        labels = ", ".join(
            l["name"] for l in p.get("labels", []) if l["name"] != "CLA Signed"
        )
        reviewer, rev_state, rev_days = latest_review(p.get("reviews", []))
        if not reviewer:
            reqs = p.get("reviewRequests") or []
            if reqs:
                reviewer = reqs[0].get("login", "")
                rev_state, rev_days = "PENDING", days_ago(p["createdAt"])
        ci = ci_status(p.get("statusCheckRollup", []))
        idle = days_ago(p["updatedAt"])
        row = dict(
            Number=n,
            Title=p["title"],
            Type="PR",
            Owner=author,
            Labels=labels,
            Reviewer=reviewer,
            **{"Reviewer Days": rev_days if reviewer else ""},
            Age=days_ago(p["createdAt"]),
            Idle=idle,
            CI=ci,
            Notes=prev.get(str(n), ""),
            _review_state=rev_state,
            _closed=False,
        )
        row["Action"] = action_for(row)
        row["Section"] = section_for(row)
        rows.append(row)
        if not row["Notes"]:
            needs_update.append(
                dict(number=n, title=p["title"], type="PR", labels=labels)
            )

    # Closed (last 7 days, deduplicated)
    seen_closed = set()
    open_numbers = {r["Number"] for r in rows}
    for p in sorted(closed_prs, key=lambda x: x.get("closedAt", ""), reverse=True):
        if not p.get("closedAt") or days_ago(p["closedAt"]) > 7:
            continue
        if p["number"] in open_numbers:
            continue
        dedup_key = (p.get("author", {}).get("login", ""), p["title"].strip())
        if dedup_key in seen_closed:
            continue
        seen_closed.add(dedup_key)
        merged = bool(p.get("mergedAt"))
        rows.append(
            dict(
                Number=p["number"],
                Title=p["title"],
                Type="PR",
                Section="closed this week",
                Labels="",
                Owner=p.get("author", {}).get("login", ""),
                Reviewer="",
                **{"Reviewer Days": ""},
                Age=days_ago(p["createdAt"]),
                Idle=days_ago(p["closedAt"]),
                CI="",
                Action="",
                Notes="merged" if merged else "closed without merge",
                _review_state="",
                _closed=True,
            )
        )

    for i in closed_issues:
        if not i.get("closedAt") or days_ago(i["closedAt"]) > 7:
            continue
        reason = (i.get("stateReason") or "completed").lower()
        rows.append(
            dict(
                Number=i["number"],
                Title=i["title"],
                Type="issue",
                Section="closed this week",
                Labels="",
                Owner="",
                Reviewer="",
                **{"Reviewer Days": ""},
                Age=days_ago(i["createdAt"]),
                Idle=days_ago(i["closedAt"]),
                CI="",
                Action="",
                Notes=f"closed: {reason}",
                _review_state="",
                _closed=True,
            )
        )

    # Fetch content for items needing notes
    print(
        f"Downloading {len(needs_update)} items for note generation...", file=sys.stderr
    )
    for item in needs_update:
        n = item["number"]
        cmd = "issue" if item["type"] == "issue" else "pr"
        fields = "body,comments" if cmd == "issue" else "body,comments,commits"
        data = gh([cmd, "view", str(n), "--json", fields] + repo_flag)
        if not data:
            continue
        item["body"] = (data.get("body") or "")[:500]
        comments = (data.get("comments") or [])[-5:]
        item["recent_comments"] = [
            dict(
                author=c.get("author", {}).get("login", ""),
                body=c.get("body", "")[:300],
            )
            for c in comments
            if not c.get("author", {}).get("is_bot", False)
        ]
        if item["type"] == "PR":
            item["commit_messages"] = [
                c.get("messageHeadline", "") for c in (data.get("commits") or [])[-5:]
            ]

    # Write outputs
    draft = outdir / "draft.csv"
    with open(draft, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS, extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)

    with open(outdir / "updates.json", "w") as f:
        json.dump(needs_update, f, indent=2)

    n_issues = sum(1 for r in rows if r["Type"] == "issue" and not r.get("_closed"))
    n_prs = sum(1 for r in rows if r["Type"] == "PR" and not r.get("_closed"))
    n_action = sum(1 for r in rows if r.get("Section") == "action needed")
    print(outdir)  # stdout: tmpdir path
    print(
        f"Open: {n_issues} issues, {n_prs} PRs | Action needed: {n_action} | "
        f"Need notes: {len(needs_update)}",
        file=sys.stderr,
    )


# ── assemble ──────────────────────────────────────────────────────────────────


def cmd_assemble(tmpdir: str):
    root = repo_root()
    outdir = Path(tmpdir)
    notes = {}
    if (outdir / "notes.json").exists():
        with open(outdir / "notes.json") as f:
            notes = json.load(f)

    rows = []
    with open(outdir / "draft.csv") as f:
        for row in csv.DictReader(f):
            if not row["Notes"] and row["Number"] in notes:
                row["Notes"] = notes[row["Number"]]
            rows.append(row)

    rows.sort(key=priority_sort_key)

    csv_path = root / "reports" / "oncall.csv"
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with open(csv_path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS)
        w.writeheader()
        w.writerows(rows)

    n_issues = sum(
        1 for r in rows if r["Type"] == "issue" and r["Section"] != "closed this week"
    )
    n_prs = sum(
        1 for r in rows if r["Type"] == "PR" and r["Section"] != "closed this week"
    )
    n_action = sum(1 for r in rows if r["Section"] == "action needed")
    n_closed = sum(1 for r in rows if r["Section"] == "closed this week")
    today = datetime.now().strftime("%Y-%m-%d")
    print(csv_path)
    print(
        f"oncall report: {today} | Open: {n_issues} issues, {n_prs} PRs | "
        f"Action needed: {n_action} | Closed this week: {n_closed}",
        file=sys.stderr,
    )

    import shutil

    shutil.rmtree(outdir, ignore_errors=True)


# ── main ──────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in ("sync", "assemble"):
        print(__doc__, file=sys.stderr)
        sys.exit(1)

    if sys.argv[1] == "sync":
        limit, repo = 200, None
        args = sys.argv[2:]
        while args:
            if args[0] == "--limit":
                limit = int(args[1])
                args = args[2:]
            elif args[0] == "--repo":
                repo = args[1]
                args = args[2:]
            else:
                args = args[1:]
        cmd_sync(limit, repo)

    elif sys.argv[1] == "assemble":
        cmd_assemble(sys.argv[2])
