# Claude AI Tooling Guide for TorchTitan
## Research Summary & Best Practices

*Last Updated: February 6, 2026*

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Core Tooling Overview](#core-tooling-overview)
3. [Skills: The Foundation](#skills-the-foundation)
4. [Hooks: Deterministic Automation](#hooks-deterministic-automation)
5. [CLAUDE.md: Project Memory](#claudemd-project-memory)
6. [Agent Teams (New 4.6 Feature)](#agent-teams-new-46-feature)
7. [Production Examples & References](#production-examples--references)
8. [TorchTitan-Specific Recommendations](#torchtitan-specific-recommendations)
9. [Implementation Roadmap](#implementation-roadmap)
10. [Additional Resources](#additional-resources)

---

## Executive Summary

### What You Need to Know

Claude Code provides four primary extension mechanisms:

1. **Skills** - Reusable, portable expertise packages (instructions + scripts + resources)
2. **Hooks** - Deterministic code that runs at specific lifecycle events
3. **CLAUDE.md** - Project-level persistent context and instructions
4. **Agent Teams** (New in Opus 4.6) - Parallel agent coordination for complex tasks

### Key Principle: Progressive Disclosure

The architecture is designed around "progressive disclosure" - Claude only loads what it needs, when it needs it:
- **Metadata** (~100 tokens): All skills' names/descriptions loaded at startup
- **Full instructions** (<5k tokens): Loaded only when skill is relevant
- **Bundled resources**: Scripts/files accessed on-demand via bash
- **No context penalty**: Large reference files don't count until accessed

This is fundamentally different from stuffing everything into prompts.

---

## Core Tooling Overview

### Skills vs Hooks vs Subagents vs CLAUDE.md

| Tool | Purpose | When to Use | Scope |
|------|---------|-------------|-------|
| **Skills** | Portable expertise packages | Repeatable tasks across projects/conversations | Any Claude instance |
| **Hooks** | Deterministic automation | Enforce rules that must always run | Project/user level |
| **Subagents** | Isolated task execution | Delegate research without context pollution | Single session |
| **CLAUDE.md** | Project context | Document project-specific conventions | Per-project |
| **Agent Teams** | Parallel coordination | Complex multi-perspective work | Session-level |

**Decision Matrix:**
- Need it everywhere? → **Skill**
- Must be deterministic? → **Hook**
- Want isolated context? → **Subagent**
- Project-specific? → **CLAUDE.md**
- Multiple parallel efforts? → **Agent Team**

---

## Skills: The Foundation

### What Are Skills?

Skills are filesystem-based folders that teach Claude how to perform specialized tasks. Each skill contains:

```
my-skill/
├── SKILL.md          # Main instructions (required)
├── scripts/          # Executable utilities (optional)
│   └── validate.py
└── resources/        # Reference materials (optional)
    └── API_DOCS.md
```

### SKILL.md Structure

```markdown
---
name: skill-name
description: Brief description for skill discovery. Include BOTH what it does AND when to use it.
---

# Full Instructions

Claude reads these when the skill is activated.

## Usage
Step-by-step guidance...

## Examples
Concrete examples...
```

### Best Practices for Skills

#### 1. **Keep Descriptions Precise**

❌ Bad:
```yaml
description: Helpful for PDFs
```

✅ Good:
```yaml
description: Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction.
```

#### 2. **Keep SKILL.md Under 500 Lines**

Use progressive disclosure:
```markdown
## Database Patterns

For detailed schema information, see `resources/DATABASE_SCHEMA.md`
For migration patterns, see `resources/MIGRATIONS.md`
```

Claude will only read these files when needed.

#### 3. **Use Scripts for Deterministic Tasks**

```markdown
## Validation Process

1. Write your code following the patterns in STYLE_GUIDE.md
2. Run validation: `bash scripts/validate.sh`
3. If errors found, fix and re-run
4. Only proceed when validation passes
```

The script's code never enters context - only its output does.

#### 4. **Create Evaluations BEFORE Writing Extensive Docs**

This is critical. Don't write documentation for imagined problems:

1. Identify gaps (run Claude without skill, document failures)
2. Create 3 evaluation scenarios
3. Establish baseline performance
4. Write minimal instructions to pass evals
5. Iterate based on real usage

### Skill Examples from the Wild

#### Example 1: PyTorch Lightning Skill

```yaml
---
name: pytorch-lightning
description: High-level PyTorch framework with Trainer class, automatic distributed training (DDP/FSDP/DeepSpeed), callbacks system. Use when you want clean training loops with built-in best practices.
---

# PyTorch Lightning

## Quick Start

Lightning organizes PyTorch code to eliminate boilerplate:

[code example here]

## Distributed Training

See references/distributed.md for:
- DDP setup
- FSDP configuration
- DeepSpeed ZeRO integration
- Multi-node setup
```

**Key lessons:**
- Description mentions specific features (DDP/FSDP/DeepSpeed)
- References docs for deep-dive topics
- Focuses on the 80% use case in main instructions

#### Example 2: Trail of Bits Security Skills

From their extensive collection:

```yaml
---
name: differential-review
description: Security-focused diff review with git history analysis. Use when reviewing code changes for security implications.
---

# Security-Focused Code Review

## Process

1. Analyze git diff for security-relevant changes
2. Check historical context via git blame
3. Identify potential vulnerabilities
4. Generate structured review comments
```

**Key lessons:**
- Very specific use case
- Process-oriented structure
- Leverages existing tools (git)

---

## Hooks: Deterministic Automation

### What Are Hooks?

Hooks run arbitrary shell commands (or prompt-based LLM checks) at specific lifecycle events. Unlike skills (which Claude *may* use), hooks *always* run.

### Hook Events

| Event | Fires When | Common Use |
|-------|------------|------------|
| `SessionStart` | Claude enters repo | Load context, set env vars |
| `SessionEnd` | Session ends | Cleanup, logging |
| `PreToolUse` | Before tool execution | Block dangerous commands, validate inputs |
| `PostToolUse` | After tool completes | Auto-format, run tests |
| `PostMCPToolUse` | After MCP tool | Modify tool output |
| `Stop` | Claude finishes response | Generate summary, play TTS |
| `SubagentStop` | Subagent completes | Aggregate results |
| `UserPromptSubmit` | User sends prompt | Add context, validate prompt |
| `PreCompact` | Before context compression | Backup transcript |
| `Notification` | Claude needs input | Send desktop notification |

### Hook Configuration

**User Settings** (`~/.claude/settings.json`):
```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "prettier --write ${TOOL_INPUT_FILE_PATH}",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

**Project Settings** (`.claude/settings.json`):
```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "prompt",
            "prompt": "Check if this bash command is safe. Return 'allow' or 'deny'. Command: $TOOL_INPUT_COMMAND"
          }
        ]
      }
    ]
  }
}
```

**Plugin Hooks** (`.claude-plugin/hooks/hooks.json`):
```json
{
  "description": "Auto-format Python code",
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/format-python.sh"
          }
        ]
      }
    ]
  }
}
```

### Best Practices for Hooks

#### 1. **Use for Enforcement, Not Guidance**

❌ Don't use hooks for:
- Things Claude should decide (use skills instead)
- Suggestions that might not apply

✅ Do use hooks for:
- Formatting that must always happen
- Security checks that cannot be skipped
- Required logging/audit trails

#### 2. **Prefer Command Hooks for Simplicity**

```bash
# hooks/format-code.sh
#!/bin/bash
input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path')

if [[ $file_path == *.py ]]; then
  black "$file_path"
  ruff check --fix "$file_path"
fi
```

#### 3. **Use Prompt Hooks for Complex Logic**

```json
{
  "type": "prompt",
  "prompt": "Analyze this bash command for security risks. Check for: command injection, path traversal, dangerous file operations. Return JSON: {\"decision\": \"allow|deny|ask\", \"reason\": \"...\"}"
}
```

#### 4. **Leverage Environment Variables**

Available in all hooks:
- `$CLAUDE_PROJECT_DIR` - Project root
- `$CLAUDE_PLUGIN_ROOT` - Plugin directory
- `$CLAUDE_ENV_FILE` - Persistent env vars (SessionStart only)
- `$TOOL_INPUT_*` - Tool-specific inputs
- Custom env vars you set

#### 5. **SessionStart for Environment Persistence**

```bash
#!/bin/bash
# Load project type
echo "export PROJECT_TYPE=pytorch" >> "$CLAUDE_ENV_FILE"

# Inject context
echo '{
  "additionalContext": "This is a PyTorch distributed training project. Always use DDP for multi-GPU."
}'
```

### Production Hook Examples

#### Example: Auto-Format on Write (from disler/claude-code-hooks-mastery)

```json
{
  "PostToolUse": [
    {
      "matcher": "Write",
      "hooks": [
        {
          "type": "command",
          "command": "bash ${CLAUDE_PROJECT_DIR}/.claude/hooks/auto-format.sh"
        }
      ]
    }
  ]
}
```

```bash
#!/bin/bash
input=$(cat)
file=$(echo "$input" | jq -r '.tool_input.file_path')

case "$file" in
  *.py)   black "$file" ;;
  *.js)   prettier --write "$file" ;;
  *.cpp)  clang-format -i "$file" ;;
esac
```

#### Example: Security Validation (from affaan-m/everything-claude-code)

```json
{
  "PreToolUse": [
    {
      "matcher": "Bash",
      "hooks": [
        {
          "type": "command",
          "command": "python ${CLAUDE_PLUGIN_ROOT}/scripts/validate-command.py"
        }
      ]
    }
  ]
}
```

```python
import sys, json

dangerous = ['rm -rf /', 'curl | bash', ':(){ :|:& };:', 'sudo chmod 777']

data = json.loads(sys.stdin.read())
cmd = data['tool_input']['command']

for pattern in dangerous:
    if pattern in cmd:
        print(json.dumps({
            "hookSpecificOutput": {"permissionDecision": "deny"},
            "systemMessage": f"Blocked dangerous command pattern: {pattern}"
        }))
        sys.exit(0)

print(json.dumps({"hookSpecificOutput": {"permissionDecision": "allow"}}))
```

---

## CLAUDE.md: Project Memory

### What is CLAUDE.md?

A markdown file that Claude reads at the start of every session. It's project-specific context that persists across conversations.

### WHAT-WHY-HOW Framework

Anthropic recommends organizing around three layers:

#### 1. WHAT (Project Context)

```markdown
# Project Overview

This is TorchTitan, a minimal PyTorch distributed training library for pretraining, SFT, and RL.

## Tech Stack
- PyTorch 2.6+ with native distributed (DDP/FSDP)
- Python 3.11+
- No dependencies on Lightning or Accelerate (intentional design choice)

## Directory Structure
- `torchtitan/` - Core library
- `train.py` - Main training entry point
- `configs/` - Training configurations
- `test/` - Test suite
```

#### 2. WHY (Design Philosophy)

```markdown
## Design Principles

### Minimalism
We intentionally avoid heavy frameworks. Each abstraction must justify its existence.

### Native PyTorch APIs
We use PyTorch's distributed APIs directly (DDP, FSDP, DTensor) rather than wrapping them. This ensures:
- Latest features are immediately available
- Users learn transferable patterns
- Less surface area for bugs

### Educational Value
Code should be readable as a learning resource, not just a tool.
```

#### 3. HOW (Commands & Workflows)

```markdown
## Common Commands

### Running Tests
```bash
# Unit tests
pytest test/

# Distributed tests (4 GPUs)
torchrun --nproc_per_node=4 test/test_ddp.py
```

### Building Documentation
```bash
# Generate API docs
python docs/build.py

# Preview locally
python -m http.server 8000 --directory docs/build
```

## Workflows

### Adding a New Model

1. Create model file in `torchtitan/models/`
2. Implement `ModelConfig` and `Model` classes
3. Add tests in `test/models/test_<model>.py`
4. Update `torchtitan/models/__init__.py`
5. Add config example in `configs/`
6. Run full test suite before PR

### Code Review Checklist
- [ ] Tests added/updated
- [ ] Documentation updated
- [ ] No new dependencies without discussion
- [ ] Passes distributed tests
```

### Best Practices

#### 1. **Keep It Concise (<300 lines ideal, <500 max)**

Anthropic's recommendation: less is more. Every line competes for attention.

❌ Don't include:
- Code style rules (use linters/formatters + hooks)
- Framework basics Claude already knows
- Historical context not relevant to current work
- Excessive documentation (link to docs instead)

✅ Do include:
- Project-specific conventions
- Non-obvious commands
- Design decisions that inform implementation
- Common gotchas

#### 2. **Use Progressive Disclosure**

```markdown
## Testing Patterns

For unit tests, see `.claude/docs/testing-unit.md`
For distributed tests, see `.claude/docs/testing-distributed.md`
For performance benchmarks, see `.claude/docs/benchmarking.md`
```

Claude will read these only when working on those specific areas.

#### 3. **Leverage Import Syntax**

```markdown
@.claude/rules/code-style.md
@.claude/rules/distributed-patterns.md

# Project-specific content here...
```

Imports are resolved recursively (up to 5 levels).

#### 4. **Child Directory CLAUDE.md for Module-Specific Rules**

```
torchtitan/
├── CLAUDE.md                    # Root project context
├── models/
│   ├── CLAUDE.md               # Model-specific conventions
│   └── llama.py
└── distributed/
    ├── CLAUDE.md               # Distributed-specific patterns
    └── fsdp_utils.py
```

Claude pulls in child CLAUDE.md files on-demand when working in those directories.

#### 5. **Use # Command for Live Updates**

During a session:
```
# Always use error boundaries around components that make API calls
```

Claude automatically appends this to CLAUDE.md. Great for capturing patterns discovered during development.

### Production Examples

#### Example: HumanLayer's 60-Line CLAUDE.md

```markdown
# HumanLayer

TypeScript monorepo for human-in-the-loop tooling.

## Commands

```bash
# Run tests
pnpm test

# Build all packages
pnpm build

# Lint
pnpm lint
```

## Conventions

- Use named exports
- Prefer async/await over promises
- All public functions must have JSDoc comments

## Project-Specific Patterns

### Error Handling
Always wrap external calls:
```ts
try {
  const result = await externalCall();
  return { success: true, data: result };
} catch (error) {
  return { success: false, error: error.message };
}
```

### Testing
Use vitest. One describe block per function.
```

**Why this works:**
- 60 lines total
- Only non-obvious patterns documented
- Commands are project-specific
- No code style (that's in `.editorconfig` + linters)

#### Example: .NET Project with Workflows (from Dometrain guide)

```markdown
# Fitness App - .NET + React

## Common Commands

### Backend
```bash
# Build
dotnet build src/Api/Api.csproj

# Run tests
dotnet test test/Api.Tests/Api.Tests.csproj

# EF migrations
dotnet ef migrations add <name> \
  --project src/Infrastructure \
  --startup-project src/Api \
  --context AppDbContext
```

## Workflows

### Creating/Modifying API Endpoints

1. Plan the endpoint changes (methods, paths, payloads)
2. Confirm with user
3. Implement endpoint in `src/Api/Controllers`
4. Add/update endpoint in `.http` file
5. Write integration test
6. Run tests before committing

**Why this matters:** Prevents Claude from skipping steps or using incorrect EF Core args.
```

---

## Agent Teams (New 4.6 Feature)

### What Are Agent Teams?

Introduced in Claude Opus 4.6 (February 2026), agent teams allow multiple Claude instances to work in parallel with coordination.

### Architecture

```
┌─────────────────────────────────────────────────┐
│  Team Lead (Coordinating Agent)                │
│  - Assigns tasks                                │
│  - Aggregates results                           │
│  - Manages shared state                         │
└──────────────┬──────────────────────────────────┘
               │
       ┌───────┼───────┬────────┬─────────┐
       │       │       │        │         │
       ▼       ▼       ▼        ▼         ▼
    Agent1  Agent2  Agent3   Agent4   Agent5
    (Build) (Test)  (Docs)   (Review) (Monitor)
```

**Key characteristics:**
- Each agent has independent context window
- Shared task list for coordination
- Direct peer-to-peer messaging
- Separate sessions (parallel execution)

### Enabling Agent Teams

```bash
# Environment variable
export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1

# Or in settings
echo '{"experimental": {"agentTeams": true}}' > ~/.claude/settings.json
```

### Use Cases

#### 1. **Parallel Feature Development**

```bash
# Team lead creates plan
/plan_w_team "Implement user authentication system"

# Orchestration prompt
"Create teams: backend engineer, frontend engineer, test engineer, security reviewer"

# Claude generates:
# - Task breakdown
# - Agent assignments
# - Dependencies between tasks
# - Validation commands

# Execute with parallel agents
/build
```

#### 2. **Codebase Review**

Multiple agents review different aspects simultaneously:
- Agent 1: Security vulnerabilities
- Agent 2: Performance issues
- Agent 3: Code style consistency
- Agent 4: Test coverage
- Agent 5: Documentation accuracy

#### 3. **Multi-Component Refactor**

For TorchTitan-style projects:
- Agent 1: Refactor FSDP utilities
- Agent 2: Update test suite
- Agent 3: Migrate configs
- Agent 4: Update documentation
- Validator: Verify integration

### Implementation Pattern (from Anthropic's C Compiler Example)

From their blog post on building a 100k-line C compiler with 16 agents:

```python
# Simplified orchestration harness
import subprocess
from pathlib import Path

def spawn_agent(agent_id: int, task: str, git_worktree: Path):
    """Spawn a Claude Code agent in its own container"""
    container = subprocess.run([
        "docker", "run", "-d",
        "-v", f"{git_worktree}:/workspace",
        "-e", f"CLAUDE_CODE_AGENT_ID={agent_id}",
        "claude-code-image",
        "claude", "--task", task
    ], capture_output=True)
    return container.stdout.decode().strip()

def coordinate_agents():
    """Main orchestration loop"""
    # Create bare git repo for coordination
    upstream = Path("/tmp/upstream.git")
    subprocess.run(["git", "init", "--bare", str(upstream)])

    # Spawn agents
    agents = []
    for i in range(4):
        worktree = Path(f"/tmp/agent_{i}")
        subprocess.run(["git", "clone", str(upstream), str(worktree)])

        agent_container = spawn_agent(
            agent_id=i,
            task="Fix bugs in test suite",
            git_worktree=worktree
        )
        agents.append((i, agent_container, worktree))

    # Monitor and aggregate
    for agent_id, container, worktree in agents:
        # Wait for completion
        subprocess.run(["docker", "wait", container])

        # Push results to upstream
        subprocess.run([
            "git", "-C", str(worktree),
            "push", "origin", "main"
        ])
```

**Key lessons:**
- Use git worktrees for isolation
- Lock files prevent race conditions
- Claude self-coordinates on "next obvious task"
- Tests provide feedback loop
- No explicit orchestrator needed (emergent behavior)

### Current Limitations

Per the official announcement:
- No session resumption yet
- No nested teams (agents can't spawn sub-teams)
- Still experimental with rough edges
- Higher token costs (each agent billed separately)

---

## Production Examples & References

### Official Examples

#### 1. **Anthropic's Own Plugins**

Repository: `anthropics/claude-code`

Best plugins to study:
- `plugin-dev` - Comprehensive toolkit with 7 expert skills
- `hookify` - Interactive rule creation for behavioral enforcement
- `pr-review` - Parallel agents for code review

#### 2. **Trail of Bits Security Suite**

Repository: `trailofbits/*` (on awesome-claude-skills)

Notable skills:
- `differential-review` - Security-focused diff analysis
- `audit-context-building` - Ultra-granular code analysis
- `building-secure-contracts` - Smart contract security with 6 blockchain scanners

**Why they're excellent:**
- Very narrow, specific use cases
- Process-oriented (step-by-step)
- Heavy use of external tools (git, semgrep, etc.)
- Real security engineering workflows

#### 3. **Stripe's Best Practices**

Repository: `stripe/stripe-best-practices`

**Structure:**
```
stripe-best-practices/
├── SKILL.md
├── scripts/
│   └── validate-integration.py
└── resources/
    ├── API_VERSIONING.md
    ├── IDEMPOTENCY.md
    └── WEBHOOK_HANDLING.md
```

**Key patterns:**
- Main skill is navigation hub
- Deep technical details in resources/
- Validation scripts for common mistakes

### Community Examples

#### 1. **obra/superpowers**

20+ battle-tested skills including:
- TDD enforcement
- Debugging workflows
- Collaboration patterns
- /brainstorm, /write-plan, /execute-plan commands

**Installation:**
```bash
/plugin marketplace add obra/superpowers-marketplace
/plugin install superpowers@superpowers
```

#### 2. **affaan-m/everything-claude-code**

From an Anthropic hackathon winner (zenith.chat):

**Structure:**
```
everything-claude-code/
├── agents/           # 15+ specialized agents
├── skills/           # 30+ skills
├── commands/         # 20+ slash commands
├── hooks/           # Pre/post tool use, security
└── .claude-plugin/
```

**Notable components:**
- `continuous-learning-v2` - Learns from mistakes
- Security hooks (XSS, command injection, eval detection)
- Language-specific skills (Python, Rust, Go)

#### 3. **diet103/infrastructure-showcase**

Innovative skill selection via hooks:

**Pattern:**
- Hook detects current context (file types, git branch, etc.)
- Dynamically activates appropriate skill
- Claude intelligently selects right expertise

### Framework-Specific Examples

#### PyTorch Ecosystem

1. **pytorch/pytorch** has `.claude/skills/skill-writer`
2. **Lightning AI** community skills for PyTorch Lightning
3. **TorchRL** patterns from meta-pytorch

#### OpenEnv Reference

From `meta-pytorch/OpenEnv/.claude`:

While they have extensive .claude setup, you're right it's "bloated" - but instructive to see:
- Heavy use of agent coordination
- MCP tool integration
- RFC-driven development patterns
- Environment specification docs

**What to learn from it:**
- How they document design decisions (see `rfcs/`)
- Tool-calling patterns (RFC 004)
- Not to over-engineer (keep it simple!)

---

## TorchTitan-Specific Recommendations

Based on the research and TorchTitan's minimal philosophy, here's a practical setup:

### 1. Core CLAUDE.md (Root Level)

```markdown
# TorchTitan

Minimal PyTorch distributed training library for pretraining, SFT, and RL.

## Philosophy

**Minimalism:** We use native PyTorch APIs (DDP, FSDP, DTensor) without framework wrappers. Each abstraction must justify its existence.

**Educational:** Code should be readable as a learning resource.

## Tech Stack

- PyTorch 2.6+ (native distributed)
- Python 3.11+
- No Lightning/Accelerate dependencies (intentional)

## Directory Structure

```
torchtitan/
├── models/        # Model implementations
├── distributed/   # DDP/FSDP utilities
├── optimizers/    # Custom optimizers
├── configs/       # Training configs
└── datasets/      # Data loading
```

## Common Commands

### Testing
```bash
# Unit tests
pytest test/

# Distributed (4 GPU)
torchrun --nproc_per_node=4 test/distributed/test_fsdp.py

# Full suite
./scripts/run_tests.sh
```

### Training
```bash
# Single GPU
python train.py --config configs/llama_7b.toml

# Multi-GPU (DDP)
torchrun --nproc_per_node=8 train.py --config configs/llama_7b.toml

# Multi-node
torchrun --nnodes=4 --nproc_per_node=8 --rdzv_backend=c10d \
  --rdzv_endpoint=$MASTER_ADDR:$MASTER_PORT \
  train.py --config configs/llama_70b.toml
```

## Workflows

### Adding a New Model (HuggingFace → TorchTitan)

See `.claude/docs/hf-migration-guide.md` for step-by-step process.

### Code Review Requirements

- Tests for distributed scenarios (DDP/FSDP)
- No new dependencies without team discussion
- Config examples for new features
- Performance benchmarks if touching core paths

## Common Gotchas

### FSDP Wrapping
Always wrap from innermost to outermost:
```python
# ✓ Correct
model = FSDP(TransformerBlock(
    FSDP(Attention(...)),
    FSDP(MLP(...))
))

# ✗ Wrong
model = FSDP(TransformerBlock(...))  # Inner layers not sharded
```

### DTensor Initialization
Use `device_mesh` for multi-dimensional parallelism:
```python
mesh = init_device_mesh("cuda", (dp_size, tp_size), mesh_dim_names=("dp", "tp"))
```

@.claude/rules/distributed-best-practices.md
@.claude/rules/testing-requirements.md
```

**Why this works:**
- ~120 lines (well under 300)
- Captures TorchTitan-specific patterns
- References deeper docs via @ syntax
- Philosophy informs implementation decisions
- Gotchas prevent common mistakes

### 2. Skills for TorchTitan

#### Skill: HuggingFace Model Migration

```markdown
---
name: hf-to-torchtitan
description: Step-by-step guide for migrating HuggingFace models to TorchTitan. Use when implementing a model that's available on HF but not yet in TorchTitan, or when asked to add/port models from HuggingFace.
---

# HuggingFace to TorchTitan Migration

## Overview

This skill guides you through migrating a HuggingFace model to TorchTitan's minimal API surface.

## Prerequisites

Check before starting:
- [ ] Model is available on HuggingFace Hub
- [ ] Model architecture is documented
- [ ] TorchTitan doesn't already have this model

## Step-by-Step Process

### 1. Analyze HuggingFace Implementation

```bash
# Clone HF transformers
git clone --depth 1 https://github.com/huggingface/transformers.git /tmp/hf

# Locate model
find /tmp/hf -name "*<model_name>*"
```

Study:
- Model architecture (`modeling_*.py`)
- Config structure (`configuration_*.py`)
- Tokenizer needs (if custom)

### 2. Create TorchTitan Structure

```bash
mkdir -p torchtitan/models/<model_name>
touch torchtitan/models/<model_name>/__init__.py
touch torchtitan/models/<model_name>/model.py
touch torchtitan/models/<model_name>/config.py
```

### 3. Implement Config

TorchTitan configs use `@dataclass`:

```python
from dataclasses import dataclass

@dataclass
class LlamaConfig:
    dim: int = 4096
    n_layers: int = 32
    n_heads: int = 32
    vocab_size: int = 32000
    multiple_of: int = 256
    norm_eps: float = 1e-5

    # Derived properties
    def head_dim(self) -> int:
        return self.dim // self.n_heads
```

**Key differences from HF:**
- No inheritance from `PretrainedConfig`
- No `from_pretrained` (we're minimal)
- Derived properties as methods, not stored

### 4. Implement Model

TorchTitan models:
- Inherit from `nn.Module` (no custom base class)
- Use native PyTorch (no HF abstractions)
- Support FSDP wrapping explicitly

```python
import torch
import torch.nn as nn
from torch.distributed._tensor import DTensor

class LlamaModel(nn.Module):
    def __init__(self, config: LlamaConfig):
        super().__init__()
        self.config = config

        self.tok_embeddings = nn.Embedding(config.vocab_size, config.dim)
        self.layers = nn.ModuleList([
            TransformerBlock(config) for _ in range(config.n_layers)
        ])
        self.norm = RMSNorm(config.dim, eps=config.norm_eps)
        self.output = nn.Linear(config.dim, config.vocab_size, bias=False)

    def forward(self, tokens: torch.Tensor) -> torch.Tensor:
        h = self.tok_embeddings(tokens)
        for layer in self.layers:
            h = layer(h)
        h = self.norm(h)
        output = self.output(h)
        return output
```

**What to remove from HF:**
- `output_hidden_states`, `output_attentions` (we don't need this)
- `use_cache` (for training only)
- `past_key_values` (not needed in forward pass)
- Complex return types (`ModelOutput` → just tensors)

### 5. Add FSDP Support

```python
def apply_fsdp(model: LlamaModel) -> FSDP:
    """Wrap model for FSDP."""
    from torch.distributed.fsdp import FullyShardedDataParallel as FSDP
    from torch.distributed.fsdp.wrap import transformer_auto_wrap_policy

    auto_wrap_policy = transformer_auto_wrap_policy(
        model,
        transformer_layer_cls={TransformerBlock},
    )

    return FSDP(
        model,
        auto_wrap_policy=auto_wrap_policy,
        device_id=torch.cuda.current_device(),
    )
```

### 6. Write Tests

```python
# test/models/test_<model_name>.py
import pytest
import torch
from torchtitan.models.<model_name> import ModelConfig, Model

def test_forward_pass():
    config = ModelConfig(
        dim=512,
        n_layers=4,
        n_heads=8,
        vocab_size=1000
    )
    model = Model(config)

    tokens = torch.randint(0, config.vocab_size, (2, 128))
    output = model(tokens)

    assert output.shape == (2, 128, config.vocab_size)

@pytest.mark.parametrize("n_gpus", [2, 4, 8])
def test_distributed_training(n_gpus):
    # Test with torchrun
    ...
```

### 7. Add Config Example

```toml
# configs/<model_name>_7b.toml
[model]
name = "<model_name>"
dim = 4096
n_layers = 32
n_heads = 32
vocab_size = 32000

[training]
batch_size = 4
sequence_length = 2048
num_steps = 100000

[optimizer]
lr = 3e-4
weight_decay = 0.1
```

### 8. Validation Checklist

Run before submitting PR:

```bash
# Unit tests pass
pytest test/models/test_<model_name>.py

# Distributed tests pass (4 GPU)
torchrun --nproc_per_node=4 test/distributed/test_<model_name>_fsdp.py

# Training runs
torchrun --nproc_per_node=8 train.py --config configs/<model_name>_7b.toml --num_steps=10

# Checkpoint save/load works
python scripts/test_checkpoint.py --model <model_name>
```

## Common Migration Issues

### Issue: HF uses custom activations
**Solution:** Implement in `torchtitan/nn/activations.py`

### Issue: HF has complex attention masking
**Solution:** Simplify to causal mask (we're training-only)

### Issue: HF loads pretrained weights
**Solution:** Not needed - we train from scratch. Document in README if users want to initialize from HF checkpoint.

## Resources

- HuggingFace transformers: https://github.com/huggingface/transformers
- PyTorch FSDP docs: https://pytorch.org/docs/stable/fsdp.html
- TorchTitan model examples: `torchtitan/models/llama/`
```

**Why this skill works:**
- Process-oriented (step-by-step)
- Addresses specific pain points (HF → TorchTitan)
- Validation checklist ensures quality
- Common issues section prevents repeated mistakes

#### Skill: Distributed Testing Patterns

```markdown
---
name: distributed-testing
description: Write robust tests for distributed training code using DDP, FSDP, and DTensor. Use when writing tests for multi-GPU functionality or debugging distributed training issues.
---

# Distributed Testing Patterns

## Overview

Testing distributed code requires special patterns. This skill covers:
- Multi-process test setup
- Collective operation testing
- FSDP-specific tests
- Debugging distributed hangs

## Test Structure

### Basic DDP Test

```python
import torch
import torch.distributed as dist
from torch.nn.parallel import DistributedDataParallel as DDP

def run_ddp_test(rank, world_size):
    """Test function run by each process."""
    # Setup process group
    dist.init_process_group(
        backend="nccl",
        init_method="tcp://localhost:12345",
        rank=rank,
        world_size=world_size
    )

    # Your test logic
    model = MyModel().to(rank)
    model = DDP(model, device_ids=[rank])

    # Test forward/backward
    input = torch.randn(4, 10).to(rank)
    loss = model(input).sum()
    loss.backward()

    # Cleanup
    dist.destroy_process_group()

def test_ddp_training():
    world_size = 4
    torch.multiprocessing.spawn(
        run_ddp_test,
        args=(world_size,),
        nprocs=world_size,
        join=True
    )
```

### Pytest Fixture for Distributed

```python
# conftest.py
import pytest
import torch.distributed as dist

@pytest.fixture
def dist_init(request):
    """Initialize distributed for test."""
    if not dist.is_initialized():
        dist.init_process_group(
            backend="nccl",
            init_method="env://",  # Read from environment
        )

    yield

    if dist.is_initialized():
        dist.destroy_process_group()
```

## Running Distributed Tests

### Via torchrun

```bash
# 4 GPUs
torchrun --nproc_per_node=4 -m pytest test/distributed/

# 2 nodes, 8 GPUs each
torchrun --nnodes=2 --nproc_per_node=8 \
  --rdzv_backend=c10d --rdzv_endpoint=$MASTER_ADDR:12345 \
  -m pytest test/distributed/
```

### Via pytest-xdist (CPU only)

```bash
pytest -n 4 test/distributed/test_cpu.py
```

## Testing Patterns

### 1. Gradient Synchronization

```python
def test_gradient_sync():
    """Verify gradients sync across ranks."""
    model = DDP(SimpleModel())

    # Same input on all ranks
    input = torch.randn(4, 10)
    loss = model(input).sum()
    loss.backward()

    # Check gradients are identical
    for param in model.parameters():
        # All-reduce to verify sync
        dist.all_reduce(param.grad)
        expected = param.grad / world_size
        assert torch.allclose(param.grad, expected)
```

### 2. FSDP State Dict

```python
def test_fsdp_checkpoint():
    """Test FSDP checkpoint save/load."""
    from torch.distributed.fsdp import FullyShardedDataParallel as FSDP
    from torch.distributed.fsdp import StateDictType, FullStateDictConfig

    model = FSDP(LargeModel())

    # Save with full state dict
    with FSDP.state_dict_type(
        model,
        StateDictType.FULL_STATE_DICT,
        FullStateDictConfig(offload_to_cpu=True, rank0_only=True),
    ):
        state_dict = model.state_dict()

    # Only rank 0 saves
    if rank == 0:
        torch.save(state_dict, "checkpoint.pt")

    dist.barrier()

    # Load on all ranks
    checkpoint = torch.load("checkpoint.pt", map_location="cpu")
    model.load_state_dict(checkpoint)
```

### 3. Communication Collectives

```python
@pytest.mark.parametrize("world_size", [2, 4, 8])
def test_allreduce(world_size):
    """Test all-reduce operation."""
    tensor = torch.tensor([rank], device=f"cuda:{rank}")
    dist.all_reduce(tensor, op=dist.ReduceOp.SUM)

    # After all-reduce, should equal sum of all ranks
    expected = sum(range(world_size))
    assert tensor.item() == expected
```

## Debugging Distributed Hangs

### Enable NCCL Debug Logging

```python
import os
os.environ["NCCL_DEBUG"] = "INFO"
os.environ["NCCL_DEBUG_SUBSYS"] = "ALL"
```

### Timeout on Collectives

```python
from torch.distributed import set_timeout

# Fail fast instead of hanging
set_timeout(timedelta(seconds=30))
```

### Find Hanging Process

```python
import torch.distributed as dist
import sys

def debug_hang():
    """Print which collective is causing hang."""
    rank = dist.get_rank()

    print(f"Rank {rank}: Before all_reduce", flush=True)
    dist.all_reduce(some_tensor)
    print(f"Rank {rank}: After all_reduce", flush=True)

    sys.stdout.flush()
```

## Resources

- PyTorch distributed testing guide: See `test/distributed/` in PyTorch repo
- FSDP testing patterns: `torch.distributed.fsdp.test_fsdp_*`
```

**Why this skill works:**
- Addresses common pain point (distributed testing is hard)
- Concrete patterns with code
- Debugging section (distributed hangs are common)
- Parametrized for different world sizes

### 3. Hooks for TorchTitan

#### Hook: Auto-format Python

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "bash ${CLAUDE_PROJECT_DIR}/.claude/hooks/format-python.sh",
            "timeout": 15
          }
        ]
      }
    ]
  }
}
```

```bash
#!/bin/bash
# .claude/hooks/format-python.sh

input=$(cat)
file=$(echo "$input" | jq -r '.tool_input.file_path')

# Only format Python files
if [[ $file == *.py ]]; then
    # Format with black
    black "$file" 2>/dev/null

    # Lint with ruff
    ruff check --fix "$file" 2>/dev/null

    echo "Formatted $file"
fi
```

#### Hook: Validate Distributed Tests

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "python ${CLAUDE_PROJECT_DIR}/.claude/hooks/validate-dist-test.py"
          }
        ]
      }
    ]
  }
}
```

```python
# .claude/hooks/validate-dist-test.py
import sys, json, re

data = json.loads(sys.stdin.read())
cmd = data['tool_input']['command']

# Detect if running distributed tests
is_torchrun = 'torchrun' in cmd
is_dist_test = 'test/distributed' in cmd or 'test_ddp' in cmd or 'test_fsdp' in cmd

if is_dist_test and not is_torchrun:
    print(json.dumps({
        "hookSpecificOutput": {"permissionDecision": "ask"},
        "systemMessage": "Warning: Running distributed test without torchrun. Did you mean to use: torchrun --nproc_per_node=4 ?"
    }))
else:
    print(json.dumps({"hookSpecificOutput": {"permissionDecision": "allow"}}))
```

### 4. Reference Docs Structure

```
.claude/
├── CLAUDE.md                              # Main project context
├── rules/
│   ├── distributed-best-practices.md      # FSDP/DDP patterns
│   ├── testing-requirements.md            # Test standards
│   └── code-review-checklist.md           # PR requirements
├── docs/
│   ├── hf-migration-guide.md              # HuggingFace → TorchTitan
│   ├── performance-tuning.md              # Optimization tips
│   └── debugging-distributed.md           # Common issues
├── skills/
│   ├── hf-to-torchtitan/
│   │   └── SKILL.md
│   ├── distributed-testing/
│   │   └── SKILL.md
│   └── performance-profiling/
│       ├── SKILL.md
│       └── scripts/
│           └── profile.py
└── hooks/
    ├── hooks.json                         # Hook configuration
    ├── format-python.sh
    └── validate-dist-test.py
```

---

## Implementation Roadmap

Here's a practical, incremental approach for TorchTitan:

### Phase 1: Foundation (Week 1)

1. **Create minimal CLAUDE.md**
   - Project overview
   - Common commands
   - Design philosophy
   - ~100 lines to start

2. **Add auto-format hook**
   - PostToolUse for Python files
   - Black + ruff
   - Immediate value

3. **Test and iterate**
   - Use Claude Code for a week
   - Note where it makes mistakes
   - Document in CLAUDE.md

### Phase 2: Skills (Week 2-3)

1. **Identify top 3 pain points**
   - Example: HuggingFace model migration
   - Example: Distributed testing
   - Example: Performance profiling

2. **Create one skill per pain point**
   - Start with process documentation
   - Add scripts if needed
   - Test with real tasks

3. **Gather team feedback**
   - Do skills save time?
   - Are they being used?
   - Refine based on usage

### Phase 3: Advanced (Week 4+)

1. **Add validation hooks**
   - Distributed test detection
   - Dangerous command blocking
   - Pre-commit checks

2. **Experiment with agent teams**
   - Parallel code review
   - Multi-component refactors
   - Complex migrations

3. **Build team muscle**
   - Share best practices
   - Document learnings
   - Iterate on structure

### Metrics to Track

- Time saved on repeated tasks
- Reduction in PR review iterations
- Onboarding time for new contributors
- Code quality improvements (via hooks)

---

## Additional Resources

### Official Documentation

- **Claude Code Docs**: https://code.claude.com/docs
- **Skills API Reference**: https://platform.claude.com/docs/en/agents-and-tools/agent-skills
- **Hooks Reference**: https://docs.anthropic.com/en/docs/claude-code/hooks

### Community Resources

- **awesome-claude-code**: https://github.com/hesreallyhim/awesome-claude-code
- **awesome-claude-skills**: https://github.com/travisvn/awesome-claude-skills
- **ClaudeLog** (community best practices): https://claudelog.com/

### Blog Posts

- **Anthropic: Agent Teams**: https://www.anthropic.com/engineering/building-c-compiler
- **Anthropic: How teams use Claude Code**: https://claude.com/blog/how-anthropic-teams-use-claude-code
- **Skills Explained**: Anthropic blog (Nov 2025)

### Video Resources

- **Claude Code Hooks Mastery**: https://github.com/disler/claude-code-hooks-mastery (includes YouTube tutorials)
- **Product Talk: Claude Code Features**: https://www.producttalk.org/how-to-use-claude-code-features/

### Reference Repositories

1. **anthropics/claude-code** - Official plugins
2. **anthropics/skills** - Official skill examples
3. **obra/superpowers** - Community skill suite
4. **affaan-m/everything-claude-code** - Hackathon winner's setup
5. **trailofbits/*** - Security engineering skills
6. **stripe/stripe-best-practices** - API integration patterns

---

## Final Thoughts

### For TorchTitan Specifically

Given TorchTitan's minimalist philosophy, I'd recommend:

**DO:**
- Create focused, process-oriented skills (HF migration, distributed testing)
- Use hooks for formatting and validation
- Keep CLAUDE.md under 200 lines
- Document design decisions (why no Lightning/Accelerate)
- Leverage progressive disclosure heavily

**DON'T:**
- Over-engineer like OpenEnv (you noted it's too bloated)
- Create skills for basic PyTorch knowledge
- Use hooks for guidance (use skills instead)
- Document every possible scenario upfront

### Key Success Factors

1. **Start minimal, grow based on real pain**
   - Don't anticipate problems
   - Let actual usage drive additions

2. **Focus on team-specific patterns**
   - HuggingFace migration is TorchTitan-specific
   - Distributed testing patterns are your bread and butter
   - Performance profiling matters for your use case

3. **Treat as living documentation**
   - Update CLAUDE.md when patterns emerge
   - Add skills when tasks repeat
   - Remove what doesn't get used

4. **Enable team learning**
   - Skills capture institutional knowledge
   - New engineers onboard faster
   - Best practices become enforced (via hooks)

### Getting Buy-In

When proposing to your team:

1. **Start with one high-value skill**
   - Example: HF → TorchTitan migration
   - Demonstrate time savings
   - Get feedback

2. **Show, don't tell**
   - Record a demo of Claude using the skill
   - Compare before/after (with vs without)
   - Measure actual time saved

3. **Make it easy to adopt**
   - Provide setup script
   - Document in 5 minutes or less
   - Make it optional initially

4. **Iterate based on feedback**
   - Don't force adoption
   - Listen to pain points
   - Refine based on usage

### Your Next Steps

1. **Read** the official skills guide: https://platform.claude.com/docs/en/agents-and-tools/agent-skills
2. **Clone** a reference repo: `git clone https://github.com/anthropics/skills`
3. **Experiment** with a minimal CLAUDE.md for TorchTitan
4. **Create** one skill (suggest: HF migration)
5. **Test** with a real task (migrate a model)
6. **Propose** to team with demo

This is a learning journey. Start small, stay pragmatic, and let real usage guide you.

---

*Document compiled from 60+ sources including Anthropic docs, community repos, blog posts, and production examples. See references section for full citations.*
