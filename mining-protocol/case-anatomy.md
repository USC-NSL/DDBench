# Case Anatomy

Every case produces files in three locations. All files are mandatory unless marked optional.

```
cases/<project>-<issue#>-<slug>/
├── case.yaml          # Machine-readable metadata (drives bench.sh + Docker)
├── symptom.md         # What the bug looks like to an observer
├── reproduce.md       # Human-readable step-by-step reproduction
├── verification.md    # Automated pass/fail logic (embedded in reproduce.sh)
├── setup.md           # Human-readable build instructions
├── setup.sh           # Executable: clone + build (Docker-first, host fallback)
├── reproduce.sh       # Executable: trigger bug + report PASS/FAIL
└── README.md          # Entry point linking all other files

cases-solution/<project>-<issue#>-<slug>/
└── solution.md        # Root cause + fix (isolated to prevent answer leakage)

.devcontainer/<project>-<issue#>-<slug>/
└── devcontainer.json  # VS Code remote container config
```

---

## 1. case.yaml

Machine-readable metadata consumed by `bench.sh` and Docker tooling. Parsed by a pure-bash YAML parser (no `yq` dependency), so keep the format simple.

```yaml
name: <project>-<issue#>-<slug>
project: <project>                          # lowercase, matches Dockerfile name
repo: https://github.com/<org>/<repo>.git
buggy_commit: "<fix-commit-hash>~1"         # quoted, parent of fix commit
submodules: <true|false>
build:
  command: "<shell command to build>"       # empty string "" if no build needed
  binary: <relative-path-to-binary>         # empty string "" if test-only case
docker:
  caps: []                                  # extra Docker capabilities, e.g., [NET_ADMIN]
  min_cpus: 1                               # minimum CPU cores needed
```

**Rules:**
- `buggy_commit` must use the `~1` suffix convention — the parent of the fix commit
- `buggy_commit` must be quoted (YAML string, not interpreted as tilde expansion)
- `build.command` supports multi-line via YAML block scalar (`|`) for complex builds
- `build.binary` is relative to the worktree root
- `docker.caps` is an inline YAML list; use `[]` for none
- All keys are required; use empty strings for optional values

---

## 2. symptom.md

Describes the bug from the perspective of someone who encounters it, without revealing the root cause.

```markdown
# Symptom

<1-3 sentence summary of the bug's observable effect.>

## Observable behavior
- <Bullet list of specific symptoms: crash signal, error message, data anomaly, etc.>
- <Include what works correctly as contrast, if helpful.>
```

**Rules:**
- Do NOT include root cause analysis or fix hints
- Do NOT include code snippets from the fix
- Use concrete, observable language: "process crashes with SIGABRT", "subscription count grows monotonically", "test fails with DATA RACE"
- This file is provided to agents/humans as the starting point for debugging

---

## 3. reproduce.md

Human-readable step-by-step instructions to trigger the bug manually. Written for someone sitting at a terminal.

```markdown
# Reproduce: <Project> #<Issue>

## Prerequisites (optional)
<External dependencies beyond the base Docker image, if any.>

## Step 1: <Action>
```bash
<command>
```

## Step 2: <Action>
```bash
<command>
```

## Expected result (bug present)
<What happens when the bug is triggered — crash, wrong output, hang, etc.>
```

**Rules:**
- Number every step
- Include full commands (not abbreviated)
- Specify ports, flags, and config inline — no "see other doc" references
- End with "Expected result (bug present)" clearly stating the failure
- For Go test-based cases, show the `go test` command and expected failure output
- For server-based cases, show startup command + trigger commands

---

## 4. verification.md

Contains the automated verification logic as a bash script block, plus human-readable pass/fail criteria.

```markdown
# Verification: <Project> #<Issue>

```bash
<Executable bash snippet that starts service, triggers bug, checks outcome.>
```

- **FAIL:** <Condition when bug is present — crash, wrong output, timeout>
- **PASS:** <Condition when bug is fixed — process survives, test passes, correct output>
```

**Rules:**
- The bash block should be a self-contained excerpt of the logic in `reproduce.sh`
- Clearly define what constitutes PASS vs FAIL
- Include the specific signal or exit code where applicable (e.g., "SIGABRT=134")

---

## 5. setup.md

Human-readable build instructions for someone who wants to understand the build process (not executed by automation).

```markdown
# Setup: <Project> #<Issue>

## Project
- **Repository:** <GitHub URL (without .git)>
- **Language:** <C++|Go|Rust|etc.>
- **Issue:** <GitHub issue URL>

## Clone and checkout buggy version
```bash
git clone [--recurse-submodules] <repo-url>
cd <repo>
git checkout <buggy-commit>
[git submodule update --init --recursive]
```

## Build
```bash
<build command>
```

## Deploy (optional, for clustered services)
<Config files and startup commands for multi-node setups.>
```

---

## 6. setup.sh

Executable script that clones, checks out the buggy commit, and builds the project. Uses Docker-first with host fallback.

```bash
#!/usr/bin/env bash
# Setup script for <case-name>
# Clones the repository, checks out the buggy commit, and builds the project.
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" setup "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -euo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/<case-name>"
BUGGY_COMMIT="<fix-commit>~1"
REPO_URL="<repo-url>"

echo "=== Setting up <case-name> ==="

# Install dependencies
echo "Installing build dependencies..."
sudo DEBIAN_FRONTEND=noninteractive apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y <packages>

# Check prerequisites
for cmd in git <other-required-tools>; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd is required but not installed."
        exit 1
    fi
done

# Clone
if [ ! -d "$WORK_DIR" ]; then
    echo "Cloning repository..."
    git clone [--recurse-submodules] "$REPO_URL" "$WORK_DIR"
fi

cd "$WORK_DIR"

# Checkout buggy commit
echo "Checking out buggy commit..."
git checkout $BUGGY_COMMIT 2>/dev/null || git checkout $(git rev-parse $BUGGY_COMMIT)
[git submodule update --init --recursive]

# Build
if [ ! -f "$WORK_DIR/<binary-path>" ]; then
    echo "Building (this may take several minutes)..."
    <build-commands>
else
    echo "Binary already exists, skipping build."
fi

echo ""
echo "=== Setup complete ==="
echo "Binary: $WORK_DIR/<binary-path>"
```

**Rules:**
- The Docker preamble (lines 3-9) is identical across all cases — copy verbatim
- Host fallback uses `set -euo pipefail`
- Install dependencies via `apt-get` (Ubuntu 24.04 assumed)
- Skip clone/build if artifacts already exist (idempotent)
- Print status messages for each phase

---

## 7. reproduce.sh

Executable script that triggers the bug and reports PASS/FAIL. Uses Docker-first with host fallback.

```bash
#!/usr/bin/env bash
# Reproduction and verification script for <case-name>
# <Brief description of what it does.>
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
fi
# ── Host fallback (no Docker) ──
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="${BENCH_WORKSPACE:-$HOME/bug-bench}/<case-name>"
BINARY="$WORK_DIR/<binary-path>"
PORT=<unique-port>

# ── Rebuild if source changed ──
[ -f "$WORK_DIR/REBUILD.sh" ] && bash "$WORK_DIR/REBUILD.sh"

# Verify setup
if [ ! -x "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY. Run ./setup.sh first."
    exit 1
fi

echo "=== Reproducing <case-name> ==="

cleanup() {
    # Kill processes, remove temp files
}
trap cleanup EXIT

# <Trigger the bug>
# <Check outcome>

if <bug-is-fixed-condition>; then
    echo "PASS: Bug is fixed — <description>"
    exit 0
else
    echo "FAIL: Bug is present — <description>"
    exit 1
fi
```

**Rules:**
- The Docker preamble (lines 3-9) is identical across all cases
- Host fallback uses `set -uo pipefail` (not `-e`, to allow controlled failure detection)
- Always check for binary existence before proceeding
- Always define a `cleanup` function with `trap cleanup EXIT`
- Kill leftover processes from previous runs before starting
- Port numbers: use `1<issue#>` convention (e.g., issue 6614 → port 16614)
- Final output MUST be exactly `PASS: ...` or `FAIL: ...` with corresponding exit code
- For Go test-based cases: extract the regression test from the fix commit, inject it into the buggy codebase, run it
- For server-based cases: start server, trigger via client, check if process survived or produced correct output
- For race/flaky cases: loop N times, count failures, report aggregate

### Reproduction Strategies (by bug type)

| Bug Type | Strategy | Example |
|----------|----------|---------|
| Server crash | Start server → send trigger → check `kill -0 $PID` | dragonfly-6614 |
| Go test failure | Extract test from fix commit → run on buggy code | nats-7718 |
| Data race | Run test with `-race` flag, N iterations | etcd-19172 |
| Deadlock | Run test program with `timeout` wrapper, N iterations | raft-268 |
| Data loss | Write data → trigger condition → verify data exists | kvrocks-3148 |
| Resource leak | Run workload → measure metric → check threshold | nats-7718 |

---

## 8. README.md

Entry point for the case. Links to all other files.

```markdown
# <Project> #<Issue>: <Short Bug Title>

| Field | Value |
|-------|-------|
| Project | [<Project>](<project-github-url>) |
| Issue | [#<Issue>](<issue-url>) |
| Language | <C++|Go> |
| Category | <Crash|Data race|Deadlock|Resource leak|Data loss|Logic error|Performance> (<detail>) |

## Bug Summary

<2-3 sentences describing the bug, its trigger, and its impact. May include root cause at a high level.>

## Quick Start

```bash
# 1. Set up the codebase (clone, checkout buggy commit, build)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- <Required tools, e.g., Git, C++ compiler, Go 1.22+, redis-cli>

## What to Expect

**When the bug is present (FAIL):**
<What the user will see when reproduce.sh runs on the buggy commit.>

**When the bug is fixed (PASS):**
<What the user will see after applying the fix.>

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
```

---

## 9. solution.md (in cases-solution/)

Isolated from the case directory to prevent answer leakage during evaluation.

```markdown
# Solution: <Project> #<Issue>

## Fix
- **PR:** <GitHub PR URL>
- **Commit:** `<fix-commit-hash>`

## Root cause
<2-3 sentences explaining WHY the bug happens at a code level.>

## Fix description
<1-2 paragraphs explaining WHAT the fix changes.>

## Key files (optional)
- `path/to/file` -- what was changed and why

## How to apply
```bash
git checkout <fix-commit>
[git submodule update --init --recursive]
<build command>
```

## How to verify (optional)
<Reference to verification.md or additional verification steps.>
```

---

## 10. devcontainer.json (in .devcontainer/)

VS Code Dev Container configuration for the case.

```json
{
  "name": "Bug Bench - <case-name>",
  "build": {
    "dockerfile": "../../docker/<project>.Dockerfile"
  },
  "runArgs": [
    "--cap-add=SYS_PTRACE"
  ],
  "mounts": [
    "source=bug-bench-<project>-src,target=/workspace,type=volume",
    "source=${localWorkspaceFolder}/cases/<case-name>,target=/bench,type=bind,readonly"
  ],
  "workspaceFolder": "/workspace/worktrees/<case-name>",
  "postCreateCommand": "mkdir -p ~/bug-bench && ln -sfn /workspace/worktrees/<case-name> ~/bug-bench/<case-name>",
  "customizations": {
    "vscode": {
      "extensions": [<language-specific-extensions>]
    }
  }
}
```

**Extensions by language:**
- C++: `["ms-vscode.cpptools", "ms-vscode.cmake-tools"]`
- Go: `["golang.go"]`

---

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Case folder | `<project>-<issue#>-<slug>` | `dragonfly-6614-monitor-multiexec` |
| Slug | lowercase, hyphen-separated, 2-4 words | `monitor-multiexec`, `embed-data-race` |
| Port (host fallback) | `1<issue#>` | `16614`, `17718` |
| Docker volume | `bug-bench-<project>-src` | `bug-bench-dragonfly-src` |
| Docker image | `bug-bench/<project>` | `bug-bench/dragonfly` |
| Worktree path | `/workspace/worktrees/<case-name>` | `/workspace/worktrees/dragonfly-6614-monitor-multiexec` |
