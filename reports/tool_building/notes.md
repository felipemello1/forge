# AI-Native Research Notes (Cleaned)

## Scope

This document covers the 9 repos that have actual AI-native configs. All others (OpenRLHF, fairseq2, torchtitan, miles, trl, verl, vllm, etc.) are excluded — they have no AI configs to learn from.

## settings.json Census

Only 2 repos out of 9 have a `.claude/settings.json`: **Amaia** and **OpenEnv**. PyTorch, Open-Instruct, Prime-RL, Verifiers, ROLL, SkyRL, and Tinker-Cookbook do not. PyTorch puts enforcement in skill-level hooks (YAML frontmatter) instead. Open-Instruct uses per-skill `allowed-tools` in frontmatter. The rest rely entirely on CLAUDE.md behavioral instructions.

---

## Deep Dive Findings (Every File Read)

### 1. PyTorch — The Gold Standard

**Files read:** 9 SKILL.md, 2 supporting .md per pr-review, 2 hook scripts, 1 README, 1 labels.json, 1 templates.json, CLAUDE.md

**Skill inventory:**
| Skill | Lines | Innovation |
|-------|-------|------------|
| triaging-issues | 212 | Skill-level hooks (PreToolUse/PostToolUse in YAML frontmatter), labels.json allowlist, templates.json for canned responses, 2-stage GitHub Action for security |
| pr-review | 204 | Multi-file (SKILL.md + review-checklist.md + bc-guidelines.md), usage modes (PR#, branch, GitHub Actions), structured output format |
| skill-writer | 386 | Meta-skill — a skill for creating skills. 10-step process with validation checklist |
| docstring | 360 | Domain codification — encodes PyTorch's exact reST/Sphinx conventions with before/after examples |
| metal-kernel | 338 | Step-by-step recipe for 3-file changes across native_functions.yaml → Metal kernel → host stub |
| add-uint-support | 320 | Transformation skill with decision tree: "Is AT_DISPATCH_V2? → Does it use AT_INTEGRAL_TYPES? → Replace vs Append" |
| aoti-debug | 163 | Debugging guide as a skill — env vars table, systematic "Step 1: Check device → Step 2: Check shapes → Step 3: Kernel debugger" |
| at-dispatch-v2 | 306 | Mechanical code transformation with 7-step process, type group reference table |
| pyrefly-type-coverage | 223 | Migration skill — remove ignore directives, add pyrefly.toml entry, iterate until clean |

**Key innovations:**
1. **Skill-level hooks** — triaging-issues has `hooks:` in its YAML frontmatter with PreToolUse validator that reads stdin JSON, validates labels against 305-label allowlist, exits 2 to block forbidden labels. PostToolUse auto-adds `bot-triaged` via `gh issue edit`. This is NOT a global hook — it only fires when THIS skill is active.
2. **2-stage GitHub Action** — Stage 1 (untrusted trigger) captures issue# as artifact. Stage 2 (protected environment with AWS/Bedrock) downloads artifact and runs triage. Solves the "OSS users can't trigger protected workflows" problem.
3. **Templates as data** — templates.json has canned responses (redirect_to_forum, request_more_info, needs_reproduction, numerical_accuracy) that the skill references. Separates content from logic.
4. **Debugging skills** — aoti-debug isn't "fix bugs generically." It encodes THE specific debugging workflow for AOTInductor: env vars summary table, intermediate value debugger, kernel-by-kernel inspection. Domain knowledge as a skill.
5. **Transformation skills** — at-dispatch-v2 and add-uint-support encode mechanical before/after transformations with decision trees. The agent follows a recipe, not inventing solutions.
6. **Testing repo** — README reveals `https://github.com/pytorch/ciforge` exists as a staging ground for testing skill changes before upstream.

**Actual hook script pattern (from validate_labels.py):**
```python
# PreToolUse hook — reads stdin JSON, validates, exits 0 (allow) or 2 (block)
data = json.load(sys.stdin)
tool_input = data.get("tool_input", {})
labels = tool_input.get("labels", [])
forbidden = [label for label in labels if is_forbidden(label)]
if forbidden:
    print(f"BLOCKED: Cannot add forbidden labels: {forbidden}", file=sys.stderr)
    print("ACTION REQUIRED: Add ONLY the 'triage review' label instead.", file=sys.stderr)
    sys.exit(2)
```

---

### 2. Prime-RL — Self-Evolving Agent

**Files read:** CLAUDE.md (1 line: `@AGENTS.md`), AGENTS.md (73 lines)

**Key innovations:**
1. **Agent self-maintains skills** — "You are responsible for maintaining the skills folder. When a workflow fails and you fix it — whether with help from the user or through trial and error — you must update the skills to make implicit knowledge explicit." The agent literally evolves its own documentation.
2. **Skills symlinked** — "Skills live in `skills/` and are symlinked to `.claude/skills/`." Skills are part of the repo structure, not hidden in .claude/.
3. **Release notes workflow** — Detailed 8-step process: check previous release style → gather commits → check for new commits before publishing → structure into highlights → verify config field names against code → use clickable links → rank contributors by commit count → always draft first.
4. **Anti-patterns with rationale** — "Avoid try/except blocks unless really necessary. It's fine that a program fails... this helps catch non-obvious bugs."
5. **Zen of Python as guidance** — Literally includes the Zen of Python as coding philosophy.

---

### 3. Amaia — Monorepo Hierarchy

**Files read:** CLAUDE.md (206 lines), apps/llm/CLAUDE.md (228 lines), .claude/settings.json (33 lines)

**Key innovations:**
1. **Hierarchical CLAUDE.md** — Root has project structure + key commands. `apps/llm/CLAUDE.md` has LLM-specific entry points, config patterns, eval options. "App-specific details are in `apps/*/CLAUDE.md`."
2. **settings.json permissions** — Explicit allowlist (ruff, mypy, pre-commit, git read-only) and denylist (git push, git reset --hard, rm -rf).
3. **run.sh wrapper** — All commands go through `./run.sh` which handles conda/micromamba activation. Agent never needs to know about environment management.
4. **"Note for Claude Code"** — Explicitly documents what the agent CANNOT do: "The salloc + srun workflow is for interactive human debugging and cannot be used by Claude Code directly."
5. **Common Gotchas with semantic clarity** — "Step counting: `TrainState.step` counts optimizer steps (incremented every `grad_acc_steps` accumulations). All `*_freq` params use optimizer steps." Prevents the #1 confusion.
6. **Config inheritance** — `__preset_config: "path/to/base.yaml"` pattern documented.

**settings.json pattern:**
```json
{
  "permissions": {
    "defaultMode": "default",
    "allow": ["Bash(ruff*)", "Bash(mypy*)", "Bash(pre-commit*)", "Bash(git status*)", "Bash(git diff*)", "Bash(git log*)"],
    "deny": ["Bash(git push*)", "Bash(git reset*)", "Bash(rm -rf /*)"]
  },
  "env": { "PYTHONPATH": "." }
}
```

---

### 4. Open-Instruct — Workflow Orchestration

**Files read:** CLAUDE.md (42 lines), 2 SKILL.md files, 3 command .md files

**Key innovations:**
1. **Commands as CI pipelines** — `run-and-fix.md` runs 3 scripts IN ORDER, waits for each to finish, fixes errors, then updates the PR body with Beaker links. A full CI pipeline in a slash command.
2. **Skill composition** — `run-gpu-tests.md` says: "Monitor the experiment using the monitor-experiment skill. When the test has passed, update the PR body with the update-pr-body skill." One skill calls another.
3. **allowed-tools restriction** — `allowed-tools: Bash(beaker:*)` on monitor-experiment. `allowed-tools: Bash(gh:*)` on update-pr-body. Principle of least privilege PER SKILL.
4. **Workaround documentation** — update-pr-body: "Do NOT use `gh pr edit --body` — it fails with a GraphQL error about Projects (classic) deprecation. Always use the REST API approach below instead." This is EARNED KNOWLEDGE — someone hit this bug, and now the skill prevents it forever.
5. **CHANGELOG mandate** — "When creating a PR, always add a summary to `CHANGELOG.md` with a link to the PR."

**Actual command orchestration (run-and-fix.md):**
```markdown
Please run, in order, the following scripts:
1. @scripts/train/debug/single_gpu_on_beaker.sh
2. @scripts/train/debug/tools/olmo_3_parser_multigpu.sh
3. @scripts/train/debug/large_test_script.sh

Wait for each to finish successfully before starting the next one.
Monitor the results and fix any errors.

If they pass, then update the PR with links to them...
```

---

### 5. Verifiers — Complete Research Lifecycle

**Files read:** CLAUDE.md (6 lines), AGENTS.md (23 lines), environments/AGENTS.md (807 lines), 7 SKILL.md files

**Key innovations:**
1. **7 skills = full R&D lifecycle** — brainstorm → browse-environments → create-environments → evaluate-environments → optimize-with-environments → review-environments → train-with-environments. Not individual tasks, but an ENTIRE WORKFLOW PIPELINE.
2. **Context grounding** — brainstorm skill: "Read local source before proposing workflows: ~/dev/prime-cli, ~/dev/prime-rl, current verifiers workspace docs/configs." Forces the agent to read actual code before ideating.
3. **Verification gates** — Every skill has concrete "run these before claiming done" sections:
   ```bash
   prime env install my-env
   prime eval run my-env -m gpt-4.1-mini -n 5
   prime eval run my-env -m gpt-4.1-mini -n 50 -r 1 -s
   ```
4. **Model family nudge** — Skills explicitly recommend model families: "Instruct go-tos: gpt-4.1 series, qwen3 instruct series. Reasoning go-tos: gpt-5 series, qwen3 thinking series."
5. **Publish gate** — Skills proactively suggest: "After smoke tests pass, recommend pushing to Hub before large evals or RL training. Ask the user explicitly whether visibility should be PUBLIC or PRIVATE."
6. **Anti-patterns explicit** — "Do not recommend building from scratch if a strong ecosystem option exists. Do not rely on README claims without running at least one quick eval."
7. **Deliverable format** — Every skill specifies exactly what to return: "1. Baseline metrics. 2. Optimized metrics. 3. Prompt diff summary. 4. Recommendation to adopt, iterate, or stop."

---

### 6. ROLL — Architecture as Documentation

**Files read:** CLAUDE.md (160 lines)

**Key innovations:**
1. **Architecture overview IS the CLAUDE.md** — Describes the full system: Pipeline types, Distributed system, Worker types, Model support. This makes the agent understand the system before touching code.
2. **Configuration-driven design** — "Hydra for hierarchical YAML configs, CLI overrides, modular configuration."
3. **Development philosophy section** — "Less Code = Less Debt" as an explicit principle.
4. **"Build Iteratively"** — "Start with minimal functionality and verify it works before adding complexity." Applied to agent behavior.

---

### 7. SkyRL — Living Project Status

**Files read:** project-summary.md (137 lines), rl-loop-verify.md (201 lines), tinker-skyrl-quickstart.md (147 lines)

**Key innovations:**
1. **3-layer docs** — project-summary (what's done + PRs + issues), rl-loop-verify (phase-by-phase verification plan), quickstart (how to run). Three separate concerns.
2. **Timestamp + branch + PR reference** — "Last Updated: 2026-02-06, Branch: tyler/tinker-sampling-main (PR #999), Status: Ready for Merge." Full reproducibility context.
3. **Feature status tables** — Verified Functionality table with Feature/Status/Notes columns. At a glance: what works, what doesn't.
4. **Troubleshooting matrix** — Issue/Cause/Solution table: "NotImplementedError: Sampling not supported → Wrong branch → Verify on tyler/tinker-sampling-main"
5. **Critical file references with LINE NUMBERS** — "skyrl_train.py:240-280: sample() with logprobs" — agent can jump directly to relevant code.
6. **What rl_loop.py Actually Requires** — Explicit API checklist: 7 required APIs (all ✅), 3 required data types (all ✅), 2 NOT required (❌). No ambiguity.

---

### 8. Tinker-Cookbook — Agent Empathy

**Files read:** CLAUDE.md (134 lines)

**Key innovations:**
1. **Documentation map** — Points to 20+ docs/ files with 1-line descriptions. Agent doesn't need to explore randomly.
2. **"Agents often struggle with..."** — Explicitly acknowledges AI limitations: "Agents often struggle with the nested type hierarchy. Key resources: docs/api-reference/types.md"
3. **Helper function recommendations** — "Use these instead of manual construction: `datum_from_model_input_weights()`, `conversation_to_datum()`, `renderer.build_supervised_example()`" — prevents the agent from reinventing the wheel.
4. **Subscript conventions** — `_P` (problems), `_G` (groups), `_T` (tokens), `_D` (datums). Naming conventions that help the agent understand tensor semantics.
5. **Common Pitfalls** — 7 numbered gotchas, each specific and actionable: "LoRA LR: Use `hyperparam_utils.get_lr(model_name)` — LoRA needs ~10x higher LR than full fine-tuning."
6. **Builder pattern explained** — "Config objects are `chz` dataclasses. They expose `.build()`/`__call__()` returning runtime objects." Saves the agent from pattern-matching on unfamiliar architecture.

---

### 9. OpenEnv — The Most Sophisticated Setup (42 files in .claude/)

**Files read:** CLAUDE.md (251 lines), settings.json (105 lines), 9 agents, 6 docs, 9 skills, 16 hooks, 2 scripts

**Scale:** 42 files in `.claude/`. By far the largest AI-native config of any repo studied.

**Architecture:**
```
.claude/
├── settings.json                    # Permissions + hooks (SessionStart, PreToolUse, PostToolUse, Stop, SubagentStop)
├── agents/ (9)                      # Separate agent definitions with model selection + tool restrictions
├── docs/ (6)                        # CONTRIBUTING, INVARIANTS, PATTERNS, PRINCIPLES, REPO_WALKTHROUGH, TESTING_STRATEGY
├── hooks/ (16)                      # Shell scripts for enforcement + chaining
├── scripts/ (2)                     # worktree-create.sh, worktree-cleanup.sh
└── skills/ (9)                      # alignment-review, implement, pre-submit-pr, rfc-check, simplify, sprint, update-docs, work-on-issue, write-tests
```

**Key innovations:**

1. **TDD enforcement via hooks, not just instructions.** The system has a state machine:
   - `/work-on-issue` writes `.tdd-session.json` (issue number, branch, timestamp)
   - `tdd-state.sh` provides activate/deactivate/check functions (73 lines)
   - PreToolUse hook on Edit|Write (`no-direct-code.sh`) checks if TDD is active → blocks `.py` file edits in `src/` or `envs/` (exits 2 with guidance)
   - Stop hook (prompt-based) evaluates TDD compliance when Claude tries to stop — if implementation files were edited without tests, Claude gets told to continue
   - Test files, non-Python files, and non-src files are always allowed
   - TDD is opt-in (only active when `/work-on-issue` creates the marker), not location-based

2. **Session start banner.** `session-start.sh` (66 lines) detects three states and shows a banner:
   - TDD MODE ACTIVE: issue number, worktree name, branch, workflow commands, "Direct code edits blocked"
   - WORKTREE (no TDD): branch info, "Direct edits allowed"
   - MAIN REPO (Explore Mode): "Direct edits allowed", suggests `/work-on-issue`
   This gives Claude immediate context about what mode it's in.

3. **SubagentStop chaining.** After each subagent completes, a hook fires with next-step guidance:
   - after-tester.sh → "Next: `/implement`"
   - after-implementer.sh → "Next: `/update-docs` → `/simplify` → mark todo complete → `/pre-submit-pr`"
   - after-docs-updater.sh → "Next: `/simplify` → `/pre-submit-pr`"
   Creates an automatic TDD pipeline: write-tests → implement → update-docs → simplify → pre-submit-pr

4. **Agents ≠ Skills.** OpenEnv separates them:
   - **Agents** = isolated execution with specific model + tools (`.claude/agents/*.md`). E.g., `implementer` uses sonnet, can only Edit/Write/Bash, and is told "write MINIMUM code to make tests pass, do NOT add extras, do NOT refactor."
   - **Skills** = orchestration that may spawn agents (`.claude/skills/*/SKILL.md`). E.g., `implement/SKILL.md` says "runs forked with agent: implementer."
   - This lets them: (a) use opus for reasoning-heavy agents (issue-worker, pr-planner) and sonnet for execution (tester, implementer), (b) match SubagentStop hooks by agent name.

5. **Pre-PR validation hooks.** Two hooks intercept PR-related actions:
   - `pre-pr-check.sh` (68 lines): PreToolUse on Bash, intercepts `gh pr create`. Blocks (exit 2) if branch is behind base or on main. Cannot be bypassed with `--no-verify`.
   - `post-push-pr.sh` (154 lines): Post-push validation. Checks: PR is OPEN, no merge conflicts (MERGEABLE), branch freshness, description quality, test plan section, CI check statuses, commit count. Produces structured report.

6. **Sprint = parallel Agent Teams.** The `sprint` skill orchestrates multi-issue work:
   - Parse comma-separated issue numbers
   - Spawn issue-worker per issue to extract requirements
   - Create worktrees + TDD per issue
   - Check for file conflicts between issues
   - Create Agent Team: lead (delegate mode) + one teammate per issue
   - After all complete: pr-planner determines stacked PR ordering with rebasing
   - Requires `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`

7. **Docs as a first-class layer.** Six docs under `.claude/docs/`:
   - PRINCIPLES.md: Core design decisions with RFC references
   - INVARIANTS.md: Rules that must NEVER be violated (agents can't reset, client-server separation, rewards in environment)
   - PATTERNS.md: Code patterns (env directory structure, type safety, error handling)
   - TESTING_STRATEGY.md: Testing hierarchy, edge cases, high-signal vs low-signal
   - REPO_WALKTHROUGH.md: Annotated directory structure
   - CONTRIBUTING.md: Agentic-first workflow description
   Skills reference these: "Read PRINCIPLES.md and INVARIANTS.md before reviewing."

**settings.json hooks structure (the most interesting file):**
```json
{
  "hooks": {
    "SessionStart": [session-start.sh],
    "PreToolUse": [
      {matcher: "Bash", hooks: [pre-commit-check.sh, pre-pr-check.sh]},
      {matcher: "Edit|Write", hooks: [no-direct-code.sh]}
    ],
    "PostToolUse": [
      {matcher: "TodoWrite", hooks: [delegate-todos.sh]}
    ],
    "Stop": [prompt-based TDD compliance check],
    "SubagentStop": [
      {matcher: "tester", hooks: [after-tester.sh]},
      {matcher: "implementer", hooks: [after-implementer.sh]},
      {matcher: "docs-updater", hooks: [after-docs-updater.sh]},
      {catch-all: prompt-based completion evaluation}
    ]
  }
}
```

**What's bloated (opportunities to simplify):**

1. **9 agents could be fewer.** Most agent files are 20-40 lines of instructions. For a smaller project, these can be inlined into skill SKILL.md (or specified as frontmatter fields like `model: sonnet`). The separation only pays for itself when you need SubagentStop hook matching by agent name.

2. **16 hooks is a lot.** Several are trivial:
   - `after-tester.sh` (9 lines) = echo "Next: /implement"
   - `after-docs-updater.sh` (11 lines) = echo next steps
   - `tdd-deactivate.sh` (7 lines) = wrapper for `tdd-state.sh deactivate`
   - `check-line-endings.sh` (77 lines) = CRLF check (overkill for most projects)
   - `delegate-todos.sh` (22 lines) = reminder to follow TDD workflow when creating todos
   The core hooks that actually matter are: session-start.sh, no-direct-code.sh, tdd-state.sh, pre-pr-check.sh, lint.sh, test.sh. That's 6 not 16.

3. **The TDD state machine could be simpler.** The `.tdd-session.json` + `tdd-state.sh` (73 lines) + `no-direct-code.sh` (57 lines) + `tdd-deactivate.sh` (7 lines) is ~140 lines for what's essentially: "if marker file exists and target is src/*.py, block." Could be a single 40-line script.

4. **Skills that just spawn an agent could be simpler.** `implement/SKILL.md` is essentially "runs forked with agent: implementer" + 5 lines of anti-patterns. The agent file has the real instructions. If we inline the agent instructions into the skill, we save a file and a level of indirection.

5. **Docs could be more consolidated.** PRINCIPLES.md and INVARIANTS.md overlap conceptually — both are "rules." REPO_WALKTHROUGH.md duplicates what could be in CLAUDE.md. For a smaller project, 2-3 docs would suffice instead of 6.

**What's genuinely excellent (adopt for Forge):**

1. The TDD enforcement concept (marker file + PreToolUse blocking) — but simplified
2. Session start banner showing mode/context
3. Pre-PR validation (branch freshness check)
4. SubagentStop chaining idea (auto-suggest next workflow step)
5. The Stop hook for TDD compliance (prompt-based evaluation when Claude tries to stop)
6. Docs as reference targets that skills point to (instead of repeating information)

**Patterns we explicitly decided NOT to adopt:**
- **Degrees of freedom labeling** (from best-practices.md): Labeling each skill step as high/medium/low freedom adds documentation overhead without clear payoff. Claude handles mixed-freedom steps fine without labels.
- **Evaluation-driven development** (from best-practices.md): Writing formal evaluation JSON before writing skills is good theory but impractical for our first iteration. We'll test on real issues instead — closer to the "Claude A/B" iterative pattern the same doc recommends.

**Learnings from first test run (issue #751):**

1. **Worktree + editable install conflict.** Worktrees don't get their own `pip install -e .`. Tests import from wherever the editable install points (the main repo), not the worktree. Fix: set `PYTHONPATH=src` in settings.json env and run-tests.sh, same as OpenEnv (`PYTHONPATH=src:envs`) and Amaia (`"env": {"PYTHONPATH": "."}`).

2. **Push-to-main via tracking.** If worktree branch tracks `origin/main`, `git push origin <branch>` pushes to main. OpenEnv avoids this by not specifying `origin/main` as the start point in `worktree-create.sh`. Our fix: `--no-track` flag (necessary because we specify `origin/main` to ensure latest base). OpenEnv's `pre-pr-check.sh` hook is the additional safety net.

3. **`.claude/` not in worktree.** Our `.claude/` files are staged but not committed to main. Worktrees created from `origin/main` don't have them. This is a bootstrap problem — resolves once `.claude/` is committed.

4. **Scripts are Forge-original.** `fetch-issue.sh`, `fetch-pr.sh`, `open-pr.sh`, `pr-description.md` have no equivalent in any reference repo. OpenEnv lets Claude use `gh` directly with hooks as guardrails. Our scripts add consistency and error handling. Both approaches are valid.

5. **File path confusion in worktrees.** Claude read files from the main repo path then tried to edit them in the worktree path. The Edit tool requires reading from the exact path you intend to edit.

---

## Cross-Repo Pattern Analysis

### Pattern: Progressive Disclosure Hierarchy

| Level | What | Token Cost | Example |
|-------|------|-----------|---------|
| 1. CLAUDE.md | Project context, always loaded | 100-500 | Amaia root CLAUDE.md |
| 2. Nested CLAUDE.md | Module-specific, loaded on-demand | 200-500 | apps/llm/CLAUDE.md |
| 3. AGENTS.md | Contribution rules, agent behavior | 50-200 | Verifiers AGENTS.md |
| 4. Skills SKILL.md | Workflow knowledge, loaded when matched | 100-400 | pr-review SKILL.md |
| 5. Skill supporting files | Deep reference, loaded on-demand | 200-800 | review-checklist.md |
| 6. Hook scripts | Never loaded into context | 0 | validate_labels.py |
| 7. Data files | Never loaded into context | 0 | labels.json, templates.json |

### Pattern: Skill Sophistication Spectrum

| Level | Description | Example |
|-------|-------------|---------|
| Simple | Steps + examples | open-instruct/monitor-experiment |
| Structured | Goal + Workflow + Output Format + Guardrails | verifiers/evaluate-environments |
| Multi-file | SKILL.md + reference docs + scripts | pytorch/pr-review |
| Hooked | SKILL.md + PreToolUse/PostToolUse hooks | pytorch/triaging-issues |
| Orchestrated | Command that composes multiple skills | open-instruct/run-and-fix |
| Self-maintaining | Agent updates skill when workflow changes | prime-rl agent directive |
| Meta | Skill that creates other skills | pytorch/skill-writer |

### Pattern: What Each Repo Does Best

| Repo | Best At | Adopt For |
|------|---------|-----------|
| pytorch | Skill-level hooks, domain-specific skills | Enforcement, specialized knowledge |
| prime-rl | Self-evolving agent docs | Living documentation |
| amaia | Monorepo hierarchy, permissions | Project structure, safety |
| open-instruct | Workflow orchestration, skill composition | CI pipelines, automation |
| verifiers | Complete R&D lifecycle as skills | Research workflows |
| SkyRL | Project status tracking with line refs | Debugging, verification |
| tinker-cookbook | Agent empathy, pitfall prevention | Onboarding, type systems |
| ROLL | Architecture as documentation | System understanding |
| OpenEnv | TDD enforcement, hooks pipeline, session context | Workflow enforcement, quality gates |

---

## Links & References

**Official:**
- Skills API: https://platform.claude.com/docs/en/agents-and-tools/agent-skills
- Hooks Reference: https://docs.anthropic.com/en/docs/claude-code/hooks

**Community:**
- awesome-claude-code: https://github.com/hesreallyhim/awesome-claude-code
- awesome-claude-skills: https://github.com/travisvn/awesome-claude-skills

---

## Appendix A: File Inventory (Exact Paths)

Every file read during this research, grouped by repo. Use these paths to re-read any file directly.

### PyTorch
```
/home/felipemello/forge/frameworks_non_training/pytorch/CLAUDE.md
/home/felipemello/forge/frameworks_non_training/pytorch/.claude/skills/triaging-issues/SKILL.md
/home/felipemello/forge/frameworks_non_training/pytorch/.claude/skills/triaging-issues/README.md
/home/felipemello/forge/frameworks_non_training/pytorch/.claude/skills/triaging-issues/labels.json
/home/felipemello/forge/frameworks_non_training/pytorch/.claude/skills/triaging-issues/templates.json
/home/felipemello/forge/frameworks_non_training/pytorch/.claude/skills/triaging-issues/scripts/validate_labels.py
/home/felipemello/forge/frameworks_non_training/pytorch/.claude/skills/triaging-issues/scripts/add_bot_triaged.py
/home/felipemello/forge/frameworks_non_training/pytorch/.claude/skills/triaging-issues/pt2-triage-rubric.md  (NOT read — referenced by SKILL.md)
/home/felipemello/forge/frameworks_non_training/pytorch/.claude/skills/pr-review/SKILL.md
/home/felipemello/forge/frameworks_non_training/pytorch/.claude/skills/pr-review/review-checklist.md
/home/felipemello/forge/frameworks_non_training/pytorch/.claude/skills/pr-review/bc-guidelines.md
/home/felipemello/forge/frameworks_non_training/pytorch/.claude/skills/skill-writer/SKILL.md
/home/felipemello/forge/frameworks_non_training/pytorch/.claude/skills/docstring/SKILL.md
/home/felipemello/forge/frameworks_non_training/pytorch/.claude/skills/metal-kernel/SKILL.md
/home/felipemello/forge/frameworks_non_training/pytorch/.claude/skills/add-uint-support/SKILL.md
/home/felipemello/forge/frameworks_non_training/pytorch/.claude/skills/aoti-debug/SKILL.md
/home/felipemello/forge/frameworks_non_training/pytorch/.claude/skills/at-dispatch-v2/SKILL.md
/home/felipemello/forge/frameworks_non_training/pytorch/.claude/skills/pyrefly-type-coverage/SKILL.md
```

### Prime-RL
```
/home/felipemello/forge/frameworks/prime-rl/CLAUDE.md
/home/felipemello/forge/frameworks/prime-rl/AGENTS.md
```
Note: prime-rl has a `skills/` directory symlinked to `.claude/skills/` but the .claude/ dir was empty in our clone (skills may live in `skills/` at repo root and get symlinked).

### Amaia
```
/home/felipemello/forge/frameworks/amaia/CLAUDE.md
/home/felipemello/forge/frameworks/amaia/apps/llm/CLAUDE.md
/home/felipemello/forge/frameworks/amaia/.claude/settings.json
```
Note: amaia also has `apps/kernel_gen/agent/CLAUDE.md` (not read — not in our list).

### Open-Instruct
```
/home/felipemello/forge/frameworks/open-instruct/CLAUDE.md
/home/felipemello/forge/frameworks/open-instruct/.claude/skills/monitor-experiment/SKILL.md
/home/felipemello/forge/frameworks/open-instruct/.claude/skills/update-pr-body/SKILL.md
/home/felipemello/forge/frameworks/open-instruct/.claude/commands/run-and-fix.md
/home/felipemello/forge/frameworks/open-instruct/.claude/commands/run-dpo-experiments.md
/home/felipemello/forge/frameworks/open-instruct/.claude/commands/run-gpu-tests.md
```

### Verifiers
```
/home/felipemello/forge/frameworks/verifiers/CLAUDE.md
/home/felipemello/forge/frameworks/verifiers/AGENTS.md
/home/felipemello/forge/frameworks/verifiers/environments/AGENTS.md
/home/felipemello/forge/frameworks/verifiers/assets/lab/environments/AGENTS.md  (NOT read — duplicate)
/home/felipemello/forge/frameworks/verifiers/skills/brainstorm/SKILL.md
/home/felipemello/forge/frameworks/verifiers/skills/browse-environments/SKILL.md
/home/felipemello/forge/frameworks/verifiers/skills/create-environments/SKILL.md
/home/felipemello/forge/frameworks/verifiers/skills/evaluate-environments/SKILL.md
/home/felipemello/forge/frameworks/verifiers/skills/optimize-with-environments/SKILL.md
/home/felipemello/forge/frameworks/verifiers/skills/review-environments/SKILL.md
/home/felipemello/forge/frameworks/verifiers/skills/train-with-environments/SKILL.md
```

### ROLL
```
/home/felipemello/forge/frameworks/ROLL/CLAUDE.md
```

### SkyRL
```
/home/felipemello/forge/frameworks/SkyRL/claude/project-summary.md
/home/felipemello/forge/frameworks/SkyRL/claude/rl-loop-verify.md
/home/felipemello/forge/frameworks/SkyRL/claude/tinker-skyrl-quickstart.md
```

### Tinker-Cookbook
```
/home/felipemello/forge/frameworks/tinker-cookbook/CLAUDE.md
```

---

## Appendix B: Full Frontmatter Examples

These are the EXACT YAML frontmatter blocks from real skills. Copy-paste-ready for reference.

### Simplest (no hooks, no tool restriction)
```yaml
# From pytorch/docstring
---
name: docstring
description: Write docstrings for PyTorch functions and methods following PyTorch conventions. Use when writing or updating docstrings in PyTorch code.
---
```

### With allowed-tools restriction
```yaml
# From open-instruct/monitor-experiment
---
name: monitor-experiment
description: Monitor Beaker experiments until completion. Use when the user asks to monitor, check, or track a Beaker experiment.
allowed-tools: Bash(beaker:*)
---
```

```yaml
# From open-instruct/update-pr-body
---
name: update-pr-body
description: Update the body of a GitHub pull request. Use when the user asks to update, edit, or modify a PR description/body.
allowed-tools: Bash(gh:*)
---
```

### With skill-level hooks (most advanced)
```yaml
# From pytorch/triaging-issues — the most sophisticated frontmatter in any repo
---
name: triaging-issues
description: Triages GitHub issues by routing to oncall teams, applying labels, and closing questions. Use when processing new PyTorch issues or when asked to triage an issue.
hooks:
  PreToolUse:
    - matcher: "mcp__github__issue_write|mcp__github__update_issue"
      hooks:
        - type: command
          command: "python3 \"$CLAUDE_PROJECT_DIR\"/.claude/skills/triaging-issues/scripts/validate_labels.py"
  PostToolUse:
    - matcher: "mcp__github__issue_write|mcp__github__update_issue|mcp__github__add_issue_comment|mcp__github__transfer_issue"
      hooks:
        - type: command
          command: "python3 \"$CLAUDE_PROJECT_DIR\"/.claude/skills/triaging-issues/scripts/add_bot_triaged.py"
---
```

Key details:
- `matcher` uses `|` for OR between tool names
- `$CLAUDE_PROJECT_DIR` is the env var for project root
- PreToolUse: exit 0 = allow, exit 2 = block with stderr feedback
- PostToolUse: exit 0 = success (always, since action already happened)

---

## Appendix C: Full Content of Key Files

### C.1: PyTorch CLAUDE.md (134 lines)

Key sections (paraphrased to save space, refer to file for exact text):

- **Testing**: Use `TestCase` from `torch.testing._internal.common_utils`, use `assertEqual` for tensors
- **Commit messages**: Don't bullet-list changes. Explain review order for large PRs. Disclose Claude authorship.
- **Coding Style**: Minimize comments. No trivial 1-2 LOC helpers used once. Explicit state management (no dynamic setattr/getattr). Match existing patterns. Assume reader familiarity with PyTorch.
- **Dynamo Config**: Use `torch._dynamo.config.patch` as decorator or context manager, never manual save/restore
- **B950 line too long**: Put `# noqa: B950` on the closing `"""` line, not on the long line itself (which would change the string)
- **Logging/Structured Tracing**: Use `trace_structured` for production debugging (tlparse), local files for dev debugging. Two personas: local dev vs production jobs.

### C.2: Prime-RL AGENTS.md (full content — 73 lines)

```markdown
# AGENTS.md

## Code Guidelines
- Avoid try/except blocks unless it's really necessary. It's fine that a program
  fails if something goes wrong as this helps us to catch non-obvious bugs and
  unforeseen side-effects earlier.
- Do not add unnecessary comments. Especially do not try to explain code change
  that reflect your work process, do not refer to old code.

## Zen of Python
[full zen of python text]

## Running code
- All code should be runnable with `uv run` or `uv run <command>`.
- All dependencies should already be installed and pin in the lock file.

## CLI Usage
- Config files use `@` syntax: `uv run sft @ path/to/config.toml`
- For multi-GPU: `uv run torchrun --nproc-per-node 2 src/prime_rl/trainer/sft/train.py @ path/to/config.toml`
- See the `toml-config` skill in `skills/` for full details.

## Skills
Skills live in `skills/` and are symlinked to `.claude/skills/`.
When you make changes to the codebase, check if any skills need updating.
YOU ARE RESPONSIBLE FOR MAINTAINING THE SKILLS FOLDER.

## Testing
Write tests as plain functions with pytest fixtures. Don't use class-based tests.

## Git
Branch prefixes: `feature/`, `fix/`, `chore/`

## Releases
[8-step release notes workflow — see main notes section 2 for details]
```

### C.3: Open-Instruct CLAUDE.md (42 lines)

Key content:
- `uv run pytest` for tests, `make style && make quality` for linting
- `uv run mkdocs serve` for docs
- "When creating a PR, always add a summary to `CHANGELOG.md` with a link to the PR"
- "Always run the linter and make sure the tests pass before finishing a task"
- "Prefer running single tests, not the whole suite, when developing"
- Lists 3 GRPO test scripts and 3 DPO test scripts with exact paths
- "To run `./scripts/train/build_image_and_launch.sh`, you must commit the current changes"
- "Never use `import logging` directly. Always use `logger = logger_utils.setup_logger(__name__)`"
- "Imports always go at the top of the file, never inline"

### C.4: Verifiers CLAUDE.md + AGENTS.md (29 lines total)

**CLAUDE.md (6 lines):**
```markdown
# CLAUDE.md
<!-- Generated for repository development workflows. Do not edit directly. -->
Before beginning work in this repository, read `AGENTS.md` and follow all scoped AGENTS guidance.
```

**AGENTS.md (23 lines):**
```markdown
## Shared Best Practices (All Contexts)
- Environments expose `load_environment(...) -> vf.Environment` and are installable with `prime env install <env-name>`.
- Validate with `prime eval run <env-name> ...` before sharing.
- Use `ToolEnv`/`MCPEnv` for stateless tools, `StatefulToolEnv` for per-rollout state.
- Validate API keys in `load_environment()` with `vf.ensure_keys(...)`.

## Repository Development Notes
- Always run `uv run pre-commit install` before making changes.
- Run `uv run ruff check --fix .`, `uv run pytest tests/`, `uv run pre-commit run --all-files`.
- Keep changes aligned with documented architecture.
- Prefer a single clear path over parallel approaches.
- Aggressively deprecate/remove inferior paths.
```

### C.5: Verifiers Skill Structure Template

Every verifiers skill follows this consistent structure (shown from brainstorm skill):

```markdown
---
name: brainstorm
description: [what + when to use — 1-2 sentences with trigger words]
---

# Skill Name

## Goal
[1-2 sentences: what success looks like]

## Interaction Style
[How to engage — iterative vs one-shot, questions to ask first]

## [Main Workflow Name] Workflow
[Numbered steps with code blocks]

## Required Grounding Sources
[What to read BEFORE proposing anything]

## [Domain-Specific Section]
[Varies per skill]

## Quality Guardrails
[DO NOT / ALWAYS rules — 3-5 bullets]
```

Some skills add extra sections:
- **Deliverable Format** — "Return: 1. ... 2. ... 3. ... 4. ..."
- **Publish Gate** — "Recommend pushing to Hub. Ask user about PUBLIC vs PRIVATE."
- **Anti-Patterns** — "Do not recommend building from scratch if ecosystem option exists."
- **Endpoint And Model Selection Nudge** — "Ask whether instruct or reasoning models."

### C.6: Full templates.json (PyTorch triage responses)

```json
{
  "templates": {
    "redirect_to_forum": {
      "action": "Close issue and add comment",
      "use_when": "Issue is a usage question, not a bug report or feature request",
      "comment": "Thank you for your interest in PyTorch! This issue appears to be a usage question rather than a bug report or feature request.\n\nFor usage questions, please use the [PyTorch Discussion Forum](https://discuss.pytorch.org/) where you'll get help from both the community and PyTorch maintainers.\n\nClosing this issue, but feel free to reopen if you believe this is actually a bug or feature request."
    },
    "request_more_info": {
      "action": "Add comment and stop",
      "use_when": "Classification is unclear",
      "comment": "Thanks for the report. To triage this, could you share:\n\n- A minimal repro (small script or steps)\n- Full error logs / stack trace\n- Output of `collect_env.py`\n\nOnce we have that, we can classify and route this properly."
    },
    "needs_reproduction": {
      "action": "Edit issue to remove external links, add label 'needs reproduction', and comment",
      "use_when": "Issue requires downloading external files to reproduce",
      "comment": "Thanks for the report! To help us investigate:\n\n1. Can you reproduce this without the external files? (e.g., using random weights or synthetic data)\n2. Are there any extreme or special values in the weights/inputs?\n\nA self-contained script helps maintainers reproduce and debug faster."
    },
    "numerical_accuracy": {
      "action": "Add comment when labeling with 'module: edge cases'",
      "use_when": "Issue involves extremal values or numerical precision differences",
      "comment": "This appears to be related to numerical accuracy limitations in floating point computation. PyTorch documents expected behavior... [links to docs]"
    }
  }
}
```

### C.7: Full add_bot_triaged.py (PostToolUse hook pattern)

```python
#!/usr/bin/env python3
"""PostToolUse hook — auto-adds bot-triaged label after any issue mutation."""
import json, os, subprocess, sys
from datetime import datetime

BOT_TRIAGED_LABEL = "bot-triaged"

def main():
    try:
        data = json.load(sys.stdin)
        tool_input = data.get("tool_input", {})
        owner = tool_input.get("owner")
        repo = tool_input.get("repo")
        issue_number = tool_input.get("issue_number")

        if not all([owner, repo, issue_number]):
            sys.exit(0)  # Missing fields, skip silently

        cmd = ["gh", "issue", "edit", str(issue_number),
               "--repo", f"{owner}/{repo}",
               "--add-label", BOT_TRIAGED_LABEL]
        subprocess.run(cmd, capture_output=True, check=False)
        sys.exit(0)  # Always exit 0 — PostToolUse hooks shouldn't block

    except Exception:
        sys.exit(0)  # Always exit 0 on error too

if __name__ == "__main__":
    main()
```

Key pattern: PostToolUse hooks ALWAYS exit 0. They perform side effects but never block.

---

## Appendix D: PR Review Checklist Details (pytorch)

The `review-checklist.md` covers areas CI CANNOT check. Full categories:

**Code Quality:**
- Clear abstractions, no dynamic setattr/getattr
- Match existing patterns, no over-engineering
- No premature abstraction (three similar lines > one-use helper)
- No trivial 1-2 LOC helpers used once
- No `_internal=True` kwargs gating internal functionality — use separate private functions
- Check if new patterns already exist in codebase before accepting
- No backward-compatibility hacks (unused renamed `_vars`, `// removed` comments)

**Testing:**
- Tests exist for new functionality
- Use `OpInfo` for operator testing
- Inherit from `torch.testing._internal.common_utils.TestCase`
- Use `assertEqual` for tensors, not raw assertions
- Device-generic test classes (take `device` as argument)
- No duplicated test logic — use `_test_foo(config)` helper pattern
- Edge cases and error conditions covered

**Security:**
- No secrets in workflow files (non-ephemeral runners risk)
- Ephemeral runners for sensitive jobs (binary builds, uploads)
- `torch.load` attack surface — prefer safetensors
- TorchScript models are executable code
- `torch.distributed` / RPC / TCPStore have no auth — internal networks only
- No new `pickle.load` or `torch.load` without `weights_only=True`

**Performance:**
- No unnecessary allocations in hot loops
- No Python loops over tensor elements
- CUDA synchronization handled appropriately
- No memory leaks, proper `no_grad()`, `detach()` usage

**Backward Compatibility (from bc-guidelines.md):**
- ANY user-visible behavior change is potentially BC-breaking
- Deprecation pattern: `warnings.warn("...", FutureWarning, stacklevel=2)`
- Adding args: always with defaults
- Changing defaults: sentinel → warn → old default during deprecation
- Changing exception types: new must inherit from old
- Public API defined by: no leading `_`, `__module__` starts with `"torch."`, documented on pytorch.org

---

## Appendix E: Triaging Decision Flow (pytorch)

The triaging-issues SKILL.md encodes a 7-step decision flow. Reproduced here for reference:

```
Step 0: Already Routed?
  └─ Has ANY `oncall:` label → SKIP entirely (sub-team owns it)

Step 1: Question vs Bug/Feature?
  ├─ Question → Close + redirect_to_forum template
  └─ Unclear → request_more_info template, STOP

Step 1.5: External Files?
  └─ Has .zip/.pt/.pkl/Drive/Dropbox links → Remove links, add "needs reproduction", STOP

Step 1.6: Numerical Accuracy?
  └─ Extremal values, precision differences → Add "module: edge cases", numerical_accuracy template

Step 2: Transfer?
  └─ Belongs in vision/text/audio/RL/ExecuTorch → Transfer issue, STOP

Step 2.5: PT2 Issue?
  └─ torch.compile/dynamo/inductor → See pt2-triage-rubric.md for special handling

Step 3: Redirect to Secondary Oncall?
  └─ JIT/Distributed/Export/Quantization/Mobile/Profiler → Add ONE oncall: label, STOP
  └─ CRITICAL: Do NOT add module: labels when redirecting

Step 4: Label the Issue
  └─ Add module: labels, feature/enhancement labels

Step 5: High Priority?
  └─ Crash/correctness/regression → Add "triage review", do NOT add "high priority"

Step 6: bot-triaged (automatic via PostToolUse hook)

Step 7: Mark triaged
  └─ Add "triaged" label if not transferred/redirected/flagged
```

**V1 Constraints:**
- DO NOT close bug reports or feature requests
- DO NOT assign issues to users
- DO NOT add `high priority` without human confirmation
- DO NOT add module labels when redirecting to oncall
- DO close clear usage questions and point to discuss.pytorch.org
- BE CONSERVATIVE — when in doubt, add `triage review`

**Labels blocked by PreToolUse hook:**
- `ciflow/*` — CI job triggers for PRs only
- `test-config/*` — Test suite selectors for PRs only
- `release notes:*` — Auto-assigned
- `ci-*`, `ci:*` — CI infrastructure
- `sev*` — Severity requires human decision
- `merge blocking` — Requires human decision
- Any label containing "deprecated"
- Any label not in labels.json (305 valid labels)

**Redundant label detection:** Hook also blocks adding both `module: rnn` and `module: nn` — removes the general label when specific one is present.

---

## Appendix F: Skill-Writer Validation Rules (pytorch)

The meta-skill `skill-writer` encodes these validation requirements:

**Name rules:**
- Lowercase letters, numbers, hyphens only
- Max 64 characters
- Must match directory name

**Description rules:**
- Max 1024 characters
- Must include BOTH what it does AND when to use it
- Formula: `[What it does] + [When to use it] + [Key triggers]`

**Good description examples:**
```
"Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction."
```

**Bad descriptions:**
```
"Helps with documents"  ← Too vague
"For data analysis"     ← No trigger words
```

**Optional frontmatter fields:**
- `allowed-tools: Read, Grep, Glob` — restrict tool access (comma-separated)

**File structure:**
```
skill-name/
├── SKILL.md (required)
├── reference.md (optional — progressive disclosure)
├── examples.md (optional)
├── scripts/
│   └── helper.py (optional)
└── templates/
    └── template.txt (optional)
```

**Testing:** After creating, restart Claude Code, ask relevant questions, verify the skill activates automatically.

---

## Appendix G: ROLL Architecture Overview (from CLAUDE.md)

```
Pipeline Types:
  ├── RLVR Pipeline (Reinforcement Learning with Verifiable Rewards)
  │   - Multi-domain training with dynamic reward routing
  │   - PPO, GRPO, Reinforce++ algorithms
  │   - Math, code, general reasoning
  └── Agentic Pipeline
      - Environment-based RL (Sokoban, WebShop, FrozenLake)
      - Trajectory collection and policy optimization

Distributed System (Ray-based):
  ├── Executor — Worker management, clusters, model update groups
  ├── Scheduler — Resource management, generation/reward scheduling
  └── Strategy — Multiple backends:
      ├── Megatron-Core (TP, PP, CP, EP)
      ├── DeepSpeed (ZeRO, CPU offloading)
      ├── vLLM/SGLang (high-throughput inference)
      ├── FSDP (PyTorch native)
      └── HuggingFace (standard transformers)

Worker Types:
  ├── Actor Workers — Policy model training and inference
  ├── Critic Workers — Value function estimation
  ├── Reference Workers — KL divergence calculation
  ├── Reward Workers — Domain-specific rewards (math, code, LLM-judge, rule-based)
  └── Environment Workers — For agentic tasks

Config: Hydra hierarchical YAML + CLI overrides
```

---

## Appendix H: SkyRL Troubleshooting Matrix and API Checklist

**Troubleshooting Matrix:**

| Issue | Cause | Solution |
|-------|-------|----------|
| `NotImplementedError: Sampling not supported` | Wrong branch or server config | Verify on `tyler/tinker-sampling-main` |
| `KeyError: 'logprobs'` at rl_loop.py:188 | Sampling not returning logprobs | Check skyrl_train.py:240-280 |
| `Unknown loss function: importance_sampling` | Loss not registered | Check tx/tinker/loss_fns.py:42 |
| OOM during sampling | Too many samples | Reduce batch_size=4, group_size=2 |
| Server shows "SFT-only mode" | num_inference_engines=0 | Check backend-config |
| "Model already exists" error | Stale database | `rm tx/tinker/tinker.db` and restart |
| Disk space errors | Checkpoint accumulation | `rm -rf /tmp/tx_checkpoints/*` |

**Required API Checklist for rl_loop.py:**

| API | Status | Notes |
|-----|--------|-------|
| `ServiceClient.create_lora_training_client(base_model, rank)` | ✅ | |
| `TrainingClient.save_weights_for_sampler(name, ttl_seconds)` | ✅ | persist=False for ephemeral |
| `ServiceClient.create_sampling_client(model_path)` | ✅ | |
| `SamplingClient.sample(prompt, num_samples, sampling_params)` | ✅ | Response logprobs returned |
| `TrainingClient.forward_backward(datums, loss_fn="importance_sampling")` | ✅ | |
| `TrainingClient.optim_step(adam_params)` | ✅ | |
| `ServiceClient.create_training_client_from_state_with_optimizer(path)` | ✅ | For checkpoint resume |

**NOT Required:**
- ❌ Prompt logprobs (rl_loop.py line 188 only asserts RESPONSE logprobs)
- ❌ Multi-checkpoint sampling (always uses latest)

**Critical Files with Line Numbers:**
- `skyrl_train.py:207-300` — sample() with logprobs
- `skyrl_train.py:301-350` — save_weights_for_sampler()
- `skyrl_train.py:400-509` — checkpoint methods
- `worker_dispatch.py:157-202` — forward_backward(loss_fn=...)
- `worker_dispatch.py:318-338` — save_weights_for_sampler()

---

## Appendix I: Tinker-Cookbook Full Pitfalls and Conventions

**All 7 Common Pitfalls:**

1. **LoRA LR:** Use `hyperparam_utils.get_lr(model_name)` — LoRA needs ~10x higher LR than full fine-tuning.
2. **Renderer mismatch:** Match `renderer_name` to model family (`llama3`, `qwen3`, `role_colon`).
3. **Async gaps:** Submit `forward_backward_async` and `optim_step_async` back-to-back before awaiting.
4. **Sampler desync:** Create a **new** sampling client after saving weights.
5. **Type construction:** Use helper functions, not manual dict construction. See `supervised/data.py` and `supervised/common.py`.
6. **Group semantics:** RL advantages are centered within each group.
7. **DPO:** Start with `dpo_beta=0.1`, LR~1e-5.

**Subscript conventions for tensor names:**
- `_P` = problems (dataset examples)
- `_G` = groups (rollouts per problem)
- `_T` = tokens
- `_D` = datums
- Example: `tokens_P_G_T[p][g][t]` = token `t` in group `g` for problem `p`

**Core type hierarchy:**
```
Datum
├── model_input: ModelInput (list of chunks: EncodedTextChunk, ImageChunk)
└── loss_fn_inputs: dict[str, TensorData]

TensorData = wrapper for numpy/torch arrays with shape info
  - TensorData.from_numpy(arr)
  - TensorData.from_torch(tensor)

ModelInput.from_ints(tokens) — create from token list
```

**Helper functions (use INSTEAD of manual construction):**
- `datum_from_model_input_weights(model_input, weights, max_length)` — SL datum (in `supervised/common.py`)
- `conversation_to_datum(messages, renderer, max_length, train_on_what)` — Full pipeline (in `supervised/data.py`)
- `renderer.build_supervised_example(messages)` — Returns (ModelInput, weights)

**Architecture pattern:**
- Config objects are `chz` dataclasses (SupervisedDatasetBuilder, RLDatasetBuilder, EnvGroupBuilder)
- They expose `.build()` / `__call__()` returning runtime objects
- Env objects are single-use (no reset), create via EnvGroupBuilder

**Key code locations:**
```
tinker_cookbook/supervised/train.py   — SL training
tinker_cookbook/rl/train.py           — RL training
tinker_cookbook/preference/train_dpo.py — DPO
tinker_cookbook/renderers/            — Model-family renderers
tinker_cookbook/completers.py         — TokenCompleter vs MessageCompleter
tinker_cookbook/rl/types.py           — RL types
tinker_cookbook/recipes/              — Ready-to-run recipes
```

**Code style:**
- Explicit typing; avoid `Any` / `type: ignore`
- Use `safezip`, `timed`, `scope` helpers
- `@chz.chz` decorator for config serialization
- `ml_log.log_metrics` for metrics; `logtree` for transcripts

---

## Appendix J: Verifiers Environment Types (from environments/AGENTS.md)

The 807-line environments/AGENTS.md documents the full environment hierarchy:

```
Environment Types:
├── SingleTurnEnv (MultiTurnEnv with max_turns=1)
│   - Simplest: dataset + rubric
│   - load_environment() -> vf.SingleTurnEnv(dataset=dataset, rubric=rubric)
│
├── MultiTurnEnv (base for all multi-turn)
│   - Override env_response(messages, state) -> Messages
│   - @vf.stop decorator for stop conditions (with priority)
│   - @vf.cleanup for per-rollout cleanup
│   - @vf.teardown for environment shutdown
│   - setup_state(state) for per-rollout initialization
│   - state["final_env_response"] for early termination
│
├── ToolEnv (extends MultiTurnEnv)
│   - Pass tools as Python functions
│   - Tool schemas extracted from function signatures + docstrings
│   - Auto-tracks tool call counts via monitor rubrics
│
├── MCPEnv (extends ToolEnv)
│   - Wraps MCP (Model Context Protocol) servers
│   - mcp_servers = [{"name": "fetch", "command": "uvx", "args": ["mcp-server-fetch"]}]
│
├── StatefulToolEnv (extends ToolEnv)
│   - Per-rollout state (sandbox, DB, session)
│   - args_to_skip: hide params from model's tool schema
│   - update_tool_args(): inject state into tool calls at runtime
│
├── SandboxEnv (extends StatefulToolEnv)
│   - Containerized bash shell
│   - Auto-managed sandbox lifecycle
│
├── PythonEnv (extends SandboxEnv)
│   - Persistent Python REPL
│   - Inherits SandboxEnv + ToolEnv metrics
│
└── Experimental:
    ├── GymEnv — Gymnasium API
    ├── CliAgentEnv — Agent code in sandboxes, intercept API requests
    ├── HarborEnv — Harbor-format benchmarks
    ├── RLMEnv — Recursive Language Models
    ├── TextArenaEnv — TextArena games
    ├── ReasoningGymEnv — reasoning-gym datasets
    ├── BrowserEnv — Browserbase automation
    └── OpenEnvEnv — OpenEnv contracts
```

**Rubric system:**
```python
# Basic rubric with weighted reward functions
rubric = vf.Rubric(
    funcs=[correct_answer, length_reward],
    weights=[1.0, 0.1]
)

# JudgeRubric for LLM-based evaluation
judge_rubric = vf.JudgeRubric(judge_model="gpt-4.1-mini")

# RubricGroup combines multiple rubrics
rubric = vf.RubricGroup([math_rubric, judge_rubric])

# Metrics (weight=0 — tracked but not in reward)
rubric.add_metric(response_length)
```

**Reward function argument injection:**
Functions request data by NAMING their parameters:
- `completion` — model output messages
- `prompt` — input messages
- `answer` — from dataset
- `info` — from dataset
- `state` — full rollout state
- `parser` — shared parser object
- `judge` — LLM judge callable (JudgeRubric)
- Plural names (`completions`, `answers`) for group-level functions

**Group reward functions** return `list[float]` instead of `float` and operate across all rollouts for the same input.

**Environment packaging:**
```toml
# pyproject.toml for an environment
[project]
name = "my-env"
tags = ["single-turn", "math", "train", "eval"]
dependencies = ["verifiers>=0.1.8"]

[tool.verifiers.eval]
num_examples = 20
rollouts_per_example = 5
```

---

## Appendix K: Amaia Detailed Patterns

### Config System (OmegaConf + dataclasses)

**Pattern:**
1. Dataclass defaults (e.g., `TrainArgs`)
2. Override with YAML config file
3. Override with CLI arguments (dot notation: `model.dim=512`)
4. Config inheritance via `__preset_config: "path/to/base.yaml"`

**Key dataclasses in apps/llm/args.py:**
- `TrainArgs` — Top-level (dump_dir, batch_size, steps, seq_len)
- `DataArgs` — Data sources, tokenizer, shuffling
- `DistributedArgs` — Parallelism (dp_size, tp_size, cp_size), FSDP, torch.compile, FP8
- `OptimArgs` — Optimizer settings, LR schedulers
- `CheckpointArgs` — Checkpoint frequency, storage (local/s3), retention
- `TransformerArgs` — Model architecture

**LR Scheduler — multi-phase:**
```yaml
optim:
  lr: 3e-4
  lr_scheduler:
    - scheduler: warmup
      start_step: 0
      min_lr: 1e-30
    - scheduler: cosine
      start_step: 500
      min_lr: 3e-5
```
Types: warmup, cosine, linear, constant, inv_sqrt, trapezoidal

**Eval during training:**
```yaml
eval:
  tasks: hellaswag, arc_easy, gsm8k
  task_args: {'hellaswag': {'num_shots': 10}, 'gsm8k': {'num_shots': 4}}
eval_freq: 1000
use_async_evals: true   # separate SLURM job
eval_on_gpus: 8
```

### Import Rules (strictly enforced)
- ALL imports at module level. NEVER local imports inside functions.
- `from typing import X` NOT `import typing`
- `from collections.abc import Callable, Iterator, Sequence` NOT from typing
- `list[X]` not `List[X]`, `dict[K,V]` not `Dict`, `X | None` not `Optional`

### Contribution Rules
- Prefer extending core via inheritance in apps
- If modifying core, preserve APIs for other teams
- Don't import from other apps (no compatibility guarantees)
- Don't commit without running `pre-commit run`
- Don't use `users/` patterns as examples

---

## Appendix L: Metal Kernel Writing Pattern (pytorch)

This is the most detailed domain-specific skill. Three-file recipe:

**Step 1: native_functions.yaml**
```yaml
# Shared dispatch (preferred for native Metal)
- func: atan2.out(Tensor self, Tensor other, *, Tensor(a!) out) -> Tensor(a!)
  structured: True
  structured_inherits: TensorIteratorBase
  dispatch:
    CPU, CUDA, MPS: atan2_out  # MPS uses same stub mechanism
```

**Step 2: Metal kernel (aten/src/ATen/native/mps/kernels/)**
```metal
#include <c10/metal/indexing.h>
#include <c10/metal/utils.h>
#include <metal_stdlib>
using namespace metal;
using namespace c10::metal;

struct atan2_functor {
  template <typename T, enable_if_t<is_floating_point_v<T>, bool> = true>
  inline T operator()(const T a, const T b) {
    return static_cast<T>(precise::atan2(float(a), float(b)));
  }
  template <typename T, enable_if_t<is_integral_v<T>, bool> = true>
  inline float operator()(const T a, const T b) {
    return precise::atan2(float(a), float(b));
  }
};

REGISTER_FLOAT_BINARY_OP(atan2);
REGISTER_INT2FLOAT_BINARY_OP(atan2);
```

**Step 3: Host-side stub (aten/src/ATen/native/mps/operations/)**
```objc
static void atan2_mps_kernel(TensorIteratorBase& iter) {
  lib.exec_binary_kernel(iter, "atan2");
}
REGISTER_DISPATCH(atan2_stub, &atan2_mps_kernel)
```

**Registration macros:**
- `REGISTER_FLOAT_BINARY_OP(name)` — float, half, bfloat
- `REGISTER_INT2FLOAT_BINARY_OP(name)` — integral → float output
- `REGISTER_INTEGER_BINARY_OP(name)` — integral → same type
- `REGISTER_OPMATH_FLOAT_BINARY_OP(name)` — higher precision

**After implementation:** Remove from `MPS_XFAILLIST`/`MPS_SKIPLIST` in `torch/testing/_internal/common_mps.py`, run `python test/test_mps.py -k test_output_match_my_op`
