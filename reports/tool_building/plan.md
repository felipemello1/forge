# AI-Native TorchForge: Implementation Plan

## Current State

We have 13 files drafted (CLAUDE.md, README, settings.json, 6 scripts, 1 template, 2 skills, 1 command). These cover the basic issue-to-PR workflow. But after studying OpenEnv's 42-file setup, there are clear gaps — particularly around **enforcement** (hooks), **session context**, and **TDD as a real workflow, not just instructions**.

The goal of this plan is to adopt OpenEnv's best patterns while keeping our file count reasonable (~20 files vs their 42). OpenEnv's complexity comes from separating agents from skills (9+9 files) and having many trivial hooks. We can get the same behavior with fewer files.

---

## What We Have vs What We Need

| Capability | Current State | Gap |
|-----------|--------------|-----|
| Codebase context | CLAUDE.md (141 lines) | Done |
| Issue-to-PR workflow | `work-on-issue` skill | Needs hooks for enforcement |
| PR review | `review-pr` skill | Done for now |
| Worktree management | 2 scripts | Done |
| Issue/PR fetching | 2 scripts | Done |
| PR creation | 1 script + template | Done |
| Test running | 1 script + command | Done |
| **TDD enforcement** | Described in skill, not enforced | **Missing** |
| **Session context** | None | **Missing** — Claude doesn't know what mode it's in |
| **Pre-PR validation** | None | **Missing** — no branch freshness check |
| **Hooks in settings.json** | None (permissions only) | **Missing** — the big gap |
| **Docs as reference targets** | Everything in CLAUDE.md | May need to split if CLAUDE.md grows |

---

## What to Adopt from OpenEnv (Simplified)

### 1. TDD Enforcement (OpenEnv: ~140 lines across 4 files → Ours: ~60 lines in 1 file)

OpenEnv's approach: `.tdd-session.json` marker + `tdd-state.sh` (73 lines) + `no-direct-code.sh` (57 lines) + `tdd-deactivate.sh` (7 lines).

**Our simplified version:** One script, `tdd-guard.sh`, that handles both state management and the PreToolUse check. The `work-on-issue` skill writes the marker. The hook reads it.

```
When TDD is active:
  - Claude CAN edit/create files in tests/
  - Claude CANNOT edit files in src/forge/ until tests exist for the change
  - Claude CAN read any file
  - Claude CAN run any command
```

This is the single highest-value hook from OpenEnv. It turns "please write tests first" into "you must write tests first."

### 2. Session Start Banner (OpenEnv: 66 lines → Ours: ~30 lines)

OpenEnv's `session-start.sh` shows a banner with mode, issue number, branch. Ours would be simpler (we have fewer modes):

```
┌─ FORGE: Working on Issue #456
│  Branch: issue-456
│  Worktree: /home/user/forge-issue-456
│  TDD: Active (tests first!)
│  Workflow: /work-on-issue → write tests → implement → /run-tests → PR
└─
```

Or if not in a worktree:
```
┌─ FORGE: Explore Mode
│  Branch: main
│  Direct edits allowed. Use /work-on-issue <N> to start TDD.
└─
```

### 3. Pre-PR Validation Hook (OpenEnv: 68 lines → Ours: ~30 lines)

Intercept `gh pr create` and block if:
- On main branch (almost certainly a mistake)
- Branch is behind origin/main (PR will have merge conflicts)

OpenEnv also validates after push (154 lines for description quality, CI status). We skip that for now — our `open-pr.sh` script handles the template.

### 4. Stop Hook for TDD Compliance (OpenEnv: prompt-based)

When Claude tries to stop and TDD is active, a prompt-based hook asks: "Did you edit src/ files? If so, do tests exist? If not, continue and write tests." This catches the case where Claude says "done" without actually following TDD.

### 5. Settings.json with Hooks

Combine permissions + hooks in one file. Our version:

```json
{
  "permissions": { ... },
  "hooks": {
    "SessionStart": [session-start.sh],
    "PreToolUse": [
      {"matcher": "Edit|Write", "hooks": [tdd-guard.sh]},
      {"matcher": "Bash", "hooks": [pre-pr-check.sh]}
    ],
    "Stop": [prompt-based TDD compliance check]
  }
}
```

No PostToolUse hooks, no SubagentStop hooks (we don't have separate agents yet).

---

## Updated File Structure

```
CLAUDE.md                                          # Codebase context (already written)

.claude/
  README.md                                        # Human guide (already written)
  settings.json                                    # Permissions + hooks (NEEDS UPDATE)

  scripts/
    worktree-setup.sh                              # (already written)
    worktree-cleanup.sh                            # (already written)
    fetch-issue.sh                                 # (already written)
    fetch-pr.sh                                    # (already written)
    open-pr.sh                                     # (already written)
    run-tests.sh                                   # (already written)

  hooks/
    session-start.sh                               # NEW — banner with mode/branch/issue
    tdd-guard.sh                                   # NEW — PreToolUse: block src/ edits without tests
    pre-pr-check.sh                                # NEW — PreToolUse: block PR if branch stale or on main

  templates/
    pr-description.md                              # (already written)

  skills/
    work-on-issue/SKILL.md                         # (already written, needs TDD marker addition)
    review-pr/SKILL.md                             # (already written)

  commands/
    run-tests.md                                   # (already written)
```

**Total: 17 files** (13 existing + 3 new hooks + 1 updated settings.json). Compare to OpenEnv's 42.

---

## Priority Ranking

### Done — Already Implemented

| Item | Source | Status |
|------|--------|--------|
| `settings.json` with permissions, env, hooks | Amaia (permissions, env), OpenEnv (hooks) | Done |
| `hooks/pre-pr-check.sh` | OpenEnv (direct adaptation) | Done |
| `PYTHONPATH=src` in settings.json env | Amaia, OpenEnv | Done |
| `work-on-issue` skill | OpenEnv (concept), scripts are Forge-original | Done |
| `review-pr` skill + review-criteria.md | PyTorch (concept + progressive disclosure) | Done |
| 6 shared scripts | Worktree scripts from OpenEnv (concept), rest Forge-original | Done |

### P0 — Add Next

| Item | Source | Why |
|------|--------|-----|
| `hooks/session-start.sh` | OpenEnv (adapt their 66-line script) | Claude needs immediate context on session start |
| `hooks/post-push-pr.sh` | OpenEnv (adapt their 154-line script) | Validates PR after creation: description quality, CI, conflicts |
| `pre-commit-check.sh` | OpenEnv (adapt their 39-line script) | Soft warning on `git commit` to run tests first |
| Self-maintaining skills directive | Prime-RL (add to CLAUDE.md) | "If you fix a workflow, update the relevant skill" |

### P1 — Add After Testing P0

| Item | Source | Why |
|------|--------|-----|
| TDD enforcement (`no-direct-code.sh` + `tdd-state.sh`) | OpenEnv (adapt their scripts) | Blocks src/ edits when TDD active. Most impactful hook but most complex. |
| Stop hook for TDD compliance | OpenEnv (prompt-based) | Catches "I'm done" without tests |

### P2 — Add When Justified by Real Usage

| Item | Source Pattern | Trigger |
|------|---------------|---------|
| `.claude/docs/` directory | OpenEnv, Amaia | When CLAUDE.md exceeds ~300 lines |
| Per-skill `allowed-tools` | Open-Instruct | When a skill does something it shouldn't |
| SubagentStop chaining | OpenEnv | When we have 3+ skills that chain |
| Pre-commit git hook (not Claude hook) | OpenEnv `install.sh` | When engineers commit without formatting |

---

## How We Use OpenEnv's Patterns

| OpenEnv Pattern | What They Have | What We Do |
|----------------|---------------|------------|
| TDD state machine | 4 files, 140 lines (tdd-state.sh, no-direct-code.sh, tdd-deactivate.sh, .tdd-session.json) | P1: adapt their scripts directly, simplify where possible |
| Session start banner | session-start.sh (66 lines) | P0: adapt directly |
| Pre-PR validation | pre-pr-check.sh (68 lines) | Done: adapted directly |
| Post-PR validation | post-push-pr.sh (154 lines) | P0: adapt directly |
| Pre-commit warning | pre-commit-check.sh (39 lines) | P0: adapt directly |
| 9 separate agent files | .claude/agents/*.md with model/tool specs | Skip: inline into skill frontmatter instead |
| 16 hook scripts | Many are trivial echoes (after-tester.sh = 9 lines) | Adopt only the ones with real logic |
| 6 docs under .claude/docs/ | Separate principles, invariants, patterns, etc. | P2: keep in CLAUDE.md until it gets too long |
| SubagentStop chaining | 3 after-*.sh + catch-all prompt | P2: skip for now |
| Sprint (Agent Teams) | Complex orchestration with conflict detection | Future: worktrees + separate sessions |
| Issue/PR scripts | None — Claude uses `gh` directly | Keep our scripts (add error handling OpenEnv lacks) |

---

## Good Ideas for Follow-Up (Not Now)

These are patterns we identified from 9 repos that are genuinely useful but not justified yet.

### From OpenEnv
- **Sprint skill for Agent Teams**: Multi-issue parallel work with conflict detection and stacked PRs. Wait until single-issue workflow is solid and Agent Teams API stabilizes.
- **SubagentStop chaining**: Auto-suggest next workflow step after a subagent completes. Useful when we have 3+ skills that form a pipeline.
- **Docs as a first-class layer**: When CLAUDE.md grows past ~300 lines, split into `.claude/docs/PATTERNS.md`, `.claude/docs/TESTING.md`, etc. Skills reference these instead of repeating info.
- ~~Post-push PR validation~~ → promoted to P0.
- ~~Session start banner~~ → promoted to P0.
- ~~Pre-commit warning~~ → promoted to P0.
- ~~TDD enforcement~~ → promoted to P1.

### From PyTorch
- **Skill-level hooks in YAML frontmatter**: Hooks that only fire when a specific skill is active. Add when we need per-skill enforcement (e.g., a config-writing skill that validates configs).
- **Distributed debugging decision tree**: A skill encoding NCCL timeout → check X, NaN loss → check Y, OOM → check Z. Build after Claude has attempted distributed debugging and we know what guidance it needs.
- **Domain-specific transformation skills**: Mechanical recipes like "add a new loss function" with step-by-step file changes. Build when we have a recurring task that Claude gets wrong.
- **Meta-skill (skill-writer)**: A skill for creating new skills consistently. Useful when we reach 5+ skills.

### From Prime-RL
- ~~Self-maintaining skills directive~~ → promoted to P0 (add to CLAUDE.md).
- **Skills at repo root (symlinked)**: Makes skills visible to humans browsing the repo. Consider if `.claude/skills/` feels too hidden.

### From Open-Instruct
- **Skill composition**: One skill invokes another (e.g., work-on-issue invokes run-tests). Useful when skills share sub-workflows.
- **Experiment launch-monitor-report**: Chain: launch training → wait → diagnose → update PR. Build when we have a smoke test config.
- **CHANGELOG mandate**: Every PR adds to CHANGELOG.md. Add when we start doing releases.
- **Earned knowledge in skills**: When Claude discovers a workaround (e.g., "don't use `gh pr edit --body`, use REST API"), encode it in the skill so it never happens again.

### From Verifiers
- **Verification gates on every skill**: "Run these commands before claiming done." Already in our `work-on-issue` skill. Extend to all future skills.
- **Context grounding**: "Read source code before proposing anything." Good principle to add to skills that involve design decisions.

### From Amaia
- **Hierarchical CLAUDE.md**: Root + `src/forge/rl/CLAUDE.md` for RL-specific context. Add when the RL subsystem becomes complex enough to warrant its own doc.
- **"Note for Claude Code" about limitations**: Explicitly document what Claude cannot do (e.g., "Cannot run 8-GPU integration tests locally").

### From SkyRL
- **Troubleshooting matrix**: Table of (issue → cause → solution) with file:line references. Build after accumulating 5+ solved debugging sessions.
- **Critical file references with line numbers**: In CLAUDE.md, point to exact lines for key logic. Helps Claude jump to relevant code.

### From Tinker-Cookbook
- **Agent empathy**: Explicitly acknowledge what Claude struggles with. E.g., "Agents often struggle with the actor lifecycle. Key file: `src/forge/controller/actor.py`."
- **Helper function recommendations**: "Use X instead of building Y manually." Prevents reinvention.

### Future: Model Porting with Agent Teams
Give Claude a reference HF implementation and have an agent team port it to TorchTitan. Validate by deleting an existing model (keep tests), see if Claude recreates it from HF. This is a significant project — needs the basics solid first.

---

## Decision Log

| Decision | Rationale |
|----------|-----------|
| 17 files, not 42 | OpenEnv's complexity comes from agent/skill separation (18 files) and trivial hooks (10 files). We inline agents and skip trivial hooks. |
| TDD enforcement via hooks | Instructions alone don't work — OpenEnv proved that enforcement changes behavior. |
| 1 TDD script, not 4 | OpenEnv's state machine is over-separated. One script can do state management + PreToolUse check. |
| No separate agent files | Our skills are simple enough to specify model/tools in frontmatter. Separate agents only pay for themselves with SubagentStop matching. |
| No SubagentStop hooks | We have 2 skills, not a pipeline. Add when we have 3+ skills that chain. |
| No .claude/docs/ yet | CLAUDE.md is 141 lines. Split when it reaches ~300. |
| Pre-PR check blocks, post-PR check doesn't exist | Blocking stale branches prevents wasted CI. Post-push validation is nice-to-have. |
| Stop hook is P1, not P0 | Prompt-based hooks are hard to test. Ship the mechanical hooks first, add the judgment-based one after. |
| No degrees-of-freedom labeling | Labeling each step as high/medium/low freedom (from best-practices.md) adds overhead without payoff. Claude handles mixed-freedom steps fine. |
| No formal evaluation JSON | Writing evaluation specs before skills (best-practices.md) is impractical for v1. Testing on real issues is our evaluation. |
| Progressive disclosure for review-pr | Split review criteria into a reference file (review-criteria.md) so SKILL.md stays concise. PyTorch does this with review-checklist.md + bc-guidelines.md. |
| Copy-paste checklist in work-on-issue | Best-practices.md recommends trackable checklists. Added to work-on-issue for Claude to copy and track progress. |
| allowed-tools on review-pr | Review should be read-only. Restrict to Read, Grep, Glob, Bash(gh*) to prevent accidental code edits. (Open-Instruct pattern.) |
| Agent empathy in CLAUDE.md | Acknowledge what Claude struggles with (Tinker-Cookbook pattern). Added to gotchas section. |
| Error handling in scripts | Best-practices.md: "solve, don't punt." Scripts now check for prerequisites (gh auth, git state) and give actionable errors. |
