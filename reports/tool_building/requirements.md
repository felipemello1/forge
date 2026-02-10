# AI-Native TorchTitan & TorchForge: Requirements

## Core Philosophy

The goal is NOT to build a big AI agent system upfront. The goal is to make the codebase **easy for AI to work on**, and to improve that iteratively. This means:

1. Handcraft a good GitHub issue
2. Tell Claude to handle it
3. Claude decides which skills/context to use
4. As we iterate, we discover gaps — then build new docs, improve skills, fix CLAUDE.md
5. The library becomes progressively easier for AI to work on

This is a **feedback loop**, not a one-shot design.

## The Primary Workflow: Issue-Based Development

Everything revolves around issues. The core loop is:

```
Issue → Claude reads it → Claude plans → TDD (write failing test → fix) → PR
```

This must work well for a single issue before we think about parallelism. Parallelism (N issues → N PRs) comes from git worktrees, not from complex orchestration.

### What Claude Needs to Do This Well

1. **Read issue context** — retrieve description, comments, labels from GitHub
2. **Understand the codebase** — architecture, style rules, where things live
3. **Write tests first (TDD)** — following project test conventions, verify they fail
4. **Fix the code** — minimal, focused changes
5. **Open a PR** — proper description, linked to the issue, following style

### What We Need to Provide

1. **CLAUDE.md** — project context, style rules, architecture overview, gotchas
2. **A small number of high-value skills** — only when a workflow is complex enough to warrant one
3. **Good test guidelines** — so Claude writes tests that actually test the right thing
4. **Worktree setup** — so parallel work is isolated (this is infrastructure, not a skill)

## Key Requirements

### R1: Style Rules Must Be Documented
Titan and Forge have specific design philosophies:
- "Prefer composition over inheritance; if you must inherit, do it at most once"
- "Minimal and easy to fork — a starting point, not an endpoint"
- "Not feature-complete by design"

These rules MUST live somewhere Claude can read them (CLAUDE.md or a referenced doc). Without them, Claude will write Java-style enterprise code.

### R2: Organization Must Be Human-Readable
A human should be able to look at `.claude/` and immediately understand:
- What skills exist and what each one does (from names alone)
- What the README/index says about workflows
- How to add a new skill

OpenEnv is the anti-pattern here: too many files, unclear boundaries between agents, hard to tell what's what. We want the opposite.

### R3: Nothing Gets Stale
Every doc and skill must earn its place. If something isn't being used or is out of date, it should be removed. Prime-RL's approach of "the agent maintains its own skills" is interesting but risky — we should start with human curation.

Concrete rule: **if a skill hasn't been useful in the last month, consider deleting it.**

### R4: TDD is the Default
Claude should write a failing test BEFORE fixing code. This is non-negotiable for bug fixes. For features, it depends, but tests should come early. We need:
- Clear test conventions (where tests live, naming, fixtures)
- Guidelines for what makes a good test (not just "it passes")
- A way to run tests and verify they fail/pass

### R5: Worktrees for Parallelism
Running N issues in parallel = N git worktrees, each with its own Claude session. This is the simplest model and avoids all the complexity of multi-agent coordination within a single session.

What we need:
- A script or guide to set up worktrees
- Each worktree gets its own branch
- Claude works independently in each one
- PRs are opened from each branch

### R6: PR Quality
Every PR must:
- Link to the issue it addresses
- Have a clear description of what changed and why
- Follow the project's style
- Include tests
- Not include unrelated changes

### R7: Minimal Skill Count
Start with 0-2 skills. Add more only when a clear gap is identified through actual usage. Each skill must have:
- A clear, distinct purpose (obvious from the name)
- A reason it can't just be in CLAUDE.md
- Evidence it's needed (a real scenario where Claude failed without it)

## What We're NOT Building (Yet)

- **Complex multi-agent orchestration** — worktrees + separate sessions is enough
- **Triage system** — we don't have enough issues to justify this
- **Model porting pipeline** — future direction (agent-teams for bringing HF models to Titan), but not now
- **Auto-updating skills** — start with human curation
- **Blocking hooks** — start with documentation, not enforcement

## Future Directions (Not for V1)

### Model Porting with Agent Teams
Give Claude a reference implementation repo (e.g., HuggingFace) and ask it to port a model to TorchTitan. This could use agent-teams mode where different agents handle different aspects (architecture, tests, config). We'd validate this by deleting an existing model (e.g., Qwen) but keeping its tests, then seeing if Claude can recreate it from HF.

### Parallel Issue Processing
Once single-issue workflow is solid, scale to N issues with a launcher script that creates worktrees and starts Claude sessions. This is an infrastructure problem, not a skills problem.

### Skills for Common Complex Workflows
If we keep hitting the same complex scenarios (e.g., distributed debugging, config validation), then those become skills. But only after we've hit them multiple times.

## Success Criteria

1. Claude can take a well-written issue and produce a PR with tests, without human intervention beyond approval
2. A new engineer can understand the AI setup by reading CLAUDE.md + the skills README in < 10 minutes
3. The total AI configuration is < 500 lines across all files (excluding test fixtures)
4. No skill or doc exists without a clear, demonstrated need

## Open Questions

1. Should Claude produce a plan.md before coding, and wait for approval? Or just go?
2. What's the right granularity for worktree setup — one script, a skill, or just docs?
3. How do we handle issues that require changes across multiple repos (titan + forge)?
4. Should there be a skill specifically for "learn about this codebase" or is CLAUDE.md + exploration enough?
5. When Claude opens a PR, should it also run CI and report results, or leave that to GitHub Actions?
