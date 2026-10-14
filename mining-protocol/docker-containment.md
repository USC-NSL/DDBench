# Docker Containment

## Why Docker Self-Containment Matters

The benchmark must produce identical results regardless of when, where, or by whom it is run. Docker containment is the mechanism that makes this possible.

### Problem: Reproducibility Across Time and Environments

Bug reproduction depends on exact versions of:
- The project source code (specific commit)
- Build toolchain (compiler version, linker, standard library)
- Runtime dependencies (shared libraries, system tools)
- Client tools used to trigger the bug (redis-cli, curl, Go test runner)

Without containment, any of these can drift. A bug that crashes on GCC 12 may silently succeed on GCC 13. A race condition that fires on kernel 5.15 may vanish on 6.8. The benchmark loses its value if results depend on the host.

### Solution: Hermetic Docker Images

Each case runs inside a Docker container built from a **deterministic, layered image**:

```
ubuntu:24.04                    ← pinned base OS
  └── bug-bench/base-cpp        ← build tools + client utilities (C++ cases)
  └── bug-bench/base-go         ← Go toolchain + debugger (Go cases)
        └── bug-bench/<project>  ← project-specific dependencies
```

The container provides:
1. **Pinned OS** — Ubuntu 24.04 across all cases
2. **Pinned toolchains** — specific compiler and Go versions baked into base images
3. **Pinned source** — `buggy_commit` resolved to exact SHA at setup time
4. **Isolated filesystem** — worktrees prevent cases from interfering with each other
5. **Isolated networking** — each container has its own loopback; no cross-case port conflicts

### What "Self-Contained" Means Concretely

A case is self-contained if the following command succeeds on any machine with Docker installed, without any prior setup, network-fetched runtime dependencies, or manual configuration:

```bash
./bench.sh setup <case-name> && ./bench.sh reproduce <case-name>
```

This means:
- All build dependencies are declared in the project Dockerfile
- The build command in `case.yaml` works inside the container without modification
- The reproduce script requires only tools present in the container image
- No external services are contacted during reproduction (GitHub is only needed for the initial clone)
- No host-specific paths, environment variables, or kernel features are assumed

---

## Docker Architecture

### Image Layering

```
┌─────────────────────────────────┐
│  bug-bench/<project>            │  Project-specific deps (libssl, boost, etc.)
├─────────────────────────────────┤
│  bug-bench/base-{cpp|go}       │  Language toolchain + common tools
├─────────────────────────────────┤
│  ubuntu:24.04                   │  Base OS
└─────────────────────────────────┘
```

**Base images** (`docker/base-cpp.Dockerfile`, `docker/base-go.Dockerfile`):
- Installed once, shared across all cases of that language
- Include: build tools, git, debuggers (gdb/dlv), client utilities (redis-cli, curl, python3, netcat)
- Go base includes a pinned Go version (currently 1.23.6)

**Project images** (`docker/<project>.Dockerfile`):
- `FROM bug-bench/base-{cpp|go}`
- Add only project-specific build dependencies
- No source code baked in — source is mounted via Docker volumes at runtime

### Volume and Worktree Strategy

```
Docker volume: bug-bench-<project>-src
└── .git/                        ← bare clone of the project repo (shared)
└── worktrees/
    ├── <case-1>/                ← detached worktree at case-1's buggy commit
    ├── <case-2>/                ← detached worktree at case-2's buggy commit
    └── ...
```

**Why volumes + worktrees instead of baking source into images:**
- Multiple cases from the same project share one clone (saves disk and clone time)
- Each case gets its own worktree at its specific buggy commit (isolation)
- Source changes (edits by agents or humans) persist across container restarts
- Rebuilds are incremental — only changed files recompile

### Container Mount Layout

| Mount Path | Source | Writable | Purpose |
|------------|--------|----------|---------|
| `/workspace/worktrees/<case>/` | Docker volume | Yes | Project source at buggy commit; edit/build/debug here |
| `/bench/` | Bind mount (cases/<case>/) | No | Case scripts, docs, case.yaml |
| `/opt/tools/` | Docker volume (bug-bench-tools) | Yes | Cached addon installations |

### Capability Management

Most cases need no extra capabilities. When a case requires elevated permissions (e.g., `NET_ADMIN` for network namespace manipulation), declare them in `case.yaml`:

```yaml
docker:
  caps: [NET_ADMIN]
```

`bench.sh` translates this to `--cap-add=NET_ADMIN` in the `docker run` command.

Prefer oracles that need no extra capabilities. Capabilities only help root processes: agents run as the non-root `bench` user, so an iptables-based oracle can't run in an agent session. Process-level faults (`SIGSTOP`, kill, a pausable TCP proxy) work for both.

`SYS_PTRACE` is always added (required for debuggers like gdb and dlv).

---

## Adding Docker Support for a New Project

### If the project's language already has a base image

Create `docker/<project>.Dockerfile`:

```dockerfile
FROM bug-bench/base-cpp
# or: FROM bug-bench/base-go

# Install project-specific build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    <dependency-1> \
    <dependency-2> \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
```

**Rules:**
- Use `--no-install-recommends` to minimize image size
- Clean apt cache (`rm -rf /var/lib/apt/lists/*`) after install
- Do NOT clone source code — it's mounted at runtime via volumes
- Do NOT run builds — builds happen at `bench.sh setup` time
- Keep the Dockerfile minimal — only what's needed to compile and run

### If the project uses a new language

1. Create `docker/base-<language>.Dockerfile` following the pattern of `base-cpp` or `base-go`
2. Include the language toolchain, debugger, and standard utilities
3. Pin the toolchain version explicitly (download tarball, not `apt-get`)
4. Then create the project Dockerfile inheriting from the new base

---

## Host Fallback Mode

When Docker is unavailable, `setup.sh` and `reproduce.sh` fall back to running directly on the host. The fallback:
- Installs dependencies via `apt-get` (requires Ubuntu 24.04 + sudo)
- Clones to `$BENCH_WORKSPACE` (default: `$HOME/bug-bench/`)
- Has no isolation — cases can interfere with each other and the host

The host fallback exists for environments where Docker cannot run (CI runners without Docker, restricted VMs). Docker mode is always preferred.

The Docker preamble in every script handles mode selection automatically:

```bash
# ── Docker mode (preferred) ──
CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
if command -v docker &>/dev/null && [ -f "$REPO_ROOT/bench.sh" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/case.yaml" ]; then
    exec "$REPO_ROOT/bench.sh" setup "$CASE_NAME"   # or: reproduce
fi
# ── Host fallback (no Docker) ──
```

This block is identical across all cases and must be copied verbatim.
