# Distributed Systems Bug Benchmark Suite

A benchmark suite of real-world bugs from open-source distributed systems, each with automated scripts to reproduce the bug from source. Designed for evaluating debugging tools, program analysis techniques, and automated repair systems.

## Quick Start (Docker, recommended)

Requires Docker. Each case runs in an isolated container — no host pollution.

```bash
# 1. Set up a case (builds Docker image, clones repo, compiles)
./bench.sh setup dragonfly-6856-flushslots-oob    # ~5 min

# 2. Reproduce the bug
./bench.sh reproduce dragonfly-6856-flushslots-oob
# Output: FAIL: Bug is present — process crashed (exit code 134, SIGABRT)

# 3. Interactive debug shell (gdb, source code, everything inside container)
./bench.sh shell dragonfly-6856-flushslots-oob

# 4. Reset source to original buggy state after experimenting
./bench.sh reset dragonfly-6856-flushslots-oob

# 5. Clean up
./bench.sh clean dragonfly-6856-flushslots-oob    # remove this case
./bench.sh clean-all                                # remove everything
```

### VS Code Workflow

For a full IDE experience with editor, IntelliSense, and graphical debugger:

```bash
# 1. Run setup from host terminal first
./bench.sh setup dragonfly-6856-flushslots-oob

# 2. Open VS Code → Ctrl+Shift+P → "Dev Containers: Reopen in Container"
#    Pick "Bug Bench - dragonfly-6856-flushslots-oob" from the list

# 3. In VS Code's integrated terminal, reproduce the bug:
bash /bench/reproduce.sh
```

Each of the 31 verified cases has its own devcontainer config. VS Code opens directly into the case's source tree with C++ or Go extensions pre-installed.

> **Remote-SSH users**: If VS Code fails to download its server binary (503 error), add `"remote.SSH.localServerDownload": "off"` to your VS Code settings.

### Inside the Container

The container has two mount points:

| Path | Contents | Writable? |
|------|----------|-----------|
| `/workspace/worktrees/<case>/` | **Project source code** — the actual repo (e.g., Dragonfly) checked out at the buggy commit, with built binaries. This is where you edit, build, and debug. | Yes |
| `/bench/` | **Case scripts** — reproduce.sh, case.yaml, documentation for this specific case. | No (read-only) |

Regardless of how you entered the container (VS Code or `bench.sh shell`), the commands are the same:

```bash
bash /bench/reproduce.sh                            # reproduce the bug
cd build-dbg && ninja dragonfly                     # rebuild after editing (Dragonfly example)
```

### Host-Only Workflow (no Docker)

If Docker is not available, the scripts fall back to building directly on the host:

```bash
cd cases/dragonfly-6856-flushslots-oob/
./setup.sh       # installs deps via apt-get, clones, builds on host
./reproduce.sh   # triggers the bug
```

The workspace defaults to `$HOME/bug-bench/<case-name>/`. Override with `BENCH_WORKSPACE=/your/path`.

## What's in a Case

Each case folder contains:

```
cases/<project>-<issue#>-<slug>/
├── case.yaml        # Declarative metadata (project, commit, build command, Docker caps)
├── setup.sh         # Automated: clone, checkout buggy commit, install deps, build
├── reproduce.sh     # Automated: start system, trigger bug, report PASS/FAIL
├── README.md        # Quick start, prerequisites, what to expect
├── symptom.md       # Observable behavior and error messages
├── setup.md         # Detailed setup documentation
├── reproduce.md     # Step-by-step reproduction procedure
└── verification.md  # Pass/fail verification criteria
```

- `setup.sh` and `reproduce.sh` are the executable entry points — everything else is documentation.
- `reproduce.sh` exits with code 1 and prints `FAIL` when the bug is present, code 0 and `PASS` when the bug is fixed.
- Solutions are in `cases-solution/<case-name>/solution.md` — consult only after attempting diagnosis.

## bench.sh Commands

| Command | Description |
|---------|-------------|
| `bench.sh setup <case>` | Build Docker image, clone repo, checkout buggy commit, compile |
| `bench.sh reproduce <case>` | Run reproduce.sh inside container, prints PASS/FAIL |
| `bench.sh shell <case>` | Interactive shell inside container (gdb, source, tools) |
| `bench.sh reset <case>` | Revert all source changes to original buggy commit |
| `bench.sh clean <case>` | Remove worktree for a case |
| `bench.sh clean-all` | Remove all Docker volumes, images, and artifacts |

Same-project cases share a single git clone via Docker volumes (e.g., 14 Dragonfly cases share one ~2GB volume instead of ~28GB of separate clones).

## Verified Cases (31)

All cases build from source on Ubuntu 24.04 and reliably reproduce the described bug.

| Project | Language | Cases | Bug Types |
|---------|----------|-------|-----------|
| Dragonfly | C++ | 14 | Crashes (SIGABRT, SIGFPE), replication failure, pipeline stall |
| NATS Server | Go | 5 | Subscription leak, message loss, filter bugs, perf regression |
| Kvrocks | C++ | 4 | Crash, data loss, protocol violation, unbounded WAL growth |
| etcd | Go | 3 | Data race, linearizability violation, stale cluster state |
| Raft (hashicorp) | Go | 2 | Shutdown deadlock, invalid log compaction range |
| ClickHouse | C++ | 1 | Keeper disconnects client on addWatch |
| RocksDB | C++ | 1 | DB::Close() hangs with stalled writes |
| Seastar | C++ | 1 | Cross-shard realloc assertion crash |

See [`index.md`](index.md) for the full list with links and descriptions.

## Repository Structure

```
.
├── README.md                          # This file
├── bench.sh                           # Central orchestrator for Docker-based isolation
├── docker/                            # Dockerfiles (layered: base → project)
│   ├── base-cpp.Dockerfile            # Ubuntu 24.04 + cmake + ninja + gdb + lldb
│   ├── base-go.Dockerfile             # Ubuntu 24.04 + Go + dlv debugger
│   ├── dragonfly.Dockerfile           # base-cpp + Dragonfly build deps
│   ├── kvrocks.Dockerfile             # base-cpp + iptables
│   ├── clickhouse.Dockerfile          # base-cpp + clang-23 + rust + JRE
│   ├── rocksdb.Dockerfile             # base-cpp + compression libs
│   ├── seastar.Dockerfile             # base-cpp + Seastar deps
│   ├── etcd.Dockerfile                # base-go
│   ├── nats.Dockerfile                # base-go
│   └── raft.Dockerfile                # base-go
├── .devcontainer/                     # VS Code devcontainer configs (one per case)
│   ├── dragonfly-6856-flushslots-oob/
│   │   └── devcontainer.json
│   └── ...                            # 31 configs total
├── index.md                           # Master index of all 31 verified cases
├── cases/                             # Bug cases (problem only, no solution)
│   ├── dragonfly-6856-flushslots-oob/
│   │   ├── case.yaml                  # Declarative case metadata
│   │   ├── setup.sh                   # Docker wrapper + host fallback
│   │   ├── reproduce.sh               # Docker wrapper + host fallback
│   │   └── ...
│   └── ...                            # 31 verified cases
├── cases-solution/                    # Solutions (root cause + fix)
│   └── ...
└── CLAUDE.md                          # AI assistant instructions
```

## Prerequisites

### Docker workflow (recommended)
- **Docker** 19.03+
- No sudo, no apt-get, no host pollution

### Host-only workflow (fallback)
- **Ubuntu 24.04** (tested) or compatible Linux
- **Git** 2.40+
- **Build tools**: `build-essential`, `cmake`, `ninja-build` (installed automatically by `setup.sh`)
- **Go 1.22+** for Go-based cases (etcd, NATS, Raft)
- **Clang 23** for ClickHouse (installed automatically by `setup.sh` from LLVM nightly)
- **sudo access** for `apt-get install` (dependency installation) and `iptables` (one Kvrocks case)

## Bug Categories

The cases cover these distributed systems failure modes:

- **Crashes**: SIGABRT, SIGFPE, SIGSEGV from assertion failures, division by zero, out-of-bounds access
- **Deadlocks**: Shutdown/snapshot race conditions
- **Data loss**: Silent deletion, message loss, stale cache
- **Protocol violations**: Double responses, incompatible API behavior
- **Performance regressions**: Pipeline stalls, unbounded resource growth
- **Linearizability violations**: Cache returning stale data

## Intended Use

1. **Debugger evaluation**: Can your tool diagnose the root cause from the symptom?
2. **Automated repair**: Can your system generate a correct fix?
3. **Program analysis**: Can your tool detect the bug pattern statically?
4. **Education**: Real-world examples of distributed systems failure modes.

The `cases/` directory contains the problem only. The `cases-solution/` directory contains the answer. Use them separately to avoid leaking solutions during evaluation.
