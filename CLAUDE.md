# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A benchmark suite of 62 verified real-world bug cases from open-source distributed systems. Each case has automated scripts (`setup.sh` + `reproduce.sh`) that build from source and reliably reproduce the bug. Cases run in isolated Docker containers via `bench.sh`, with a host-only fallback for environments without Docker.

## Repository structure

- `bench.sh` — Central orchestrator (setup, reproduce, shell, agent, reset, clean)
- `docker/` — Layered Dockerfiles (base-cpp, base-go → per-project images)
- `addons/` — Runtime tool injection scripts (AI agents, debuggers, profilers)
  - `addons/examples/` — Shipped addon scripts (claude-code, aider, codex, gdb-dashboard, rr)
  - `addons/*.sh` — User custom addon scripts (gitignored)
- `.devcontainer/` — Per-case VS Code devcontainer configs (59 total)
- `cases/<project>-<issue#>-<slug>/` — Bug case files
  - `case.yaml` — Declarative metadata (project, commit, build cmd, Docker caps)
  - `setup.sh` — Docker wrapper with host fallback
  - `reproduce.sh` — Docker wrapper with host fallback
  - `README.md` — Quick start guide
  - `symptom.md` — Observable behavior and error messages
  - `reproduce.md` — Step-by-step reproduction procedure
  - `verification.md` — Pass/fail verification criteria
- `cases-solution/<project>-<issue#>-<slug>/solution.md` — Root cause + fix (do not consult during evaluation)
- `index.md` — Master index of all 62 verified cases

## Working with cases (Docker, recommended)

```bash
./bench.sh setup <case-name>                    # build image, clone, checkout, compile
./bench.sh reproduce <case-name>                # run reproduce.sh in container → PASS/FAIL
./bench.sh shell <case-name> [--addon <name>]   # interactive shell (with optional addons)
./bench.sh agent <case-name> --addon <name>     # launch AI agent inside container
./bench.sh reset <case-name>                    # revert source to original buggy commit
./bench.sh clean <case-name>                    # remove worktree for this case
./bench.sh clean-all                            # remove all Docker artifacts
```

Same-project cases share a single git clone via Docker volumes.

### Working with addons

Addons inject tools (AI agents, debuggers) into containers at runtime without modifying base images. Installed tools are cached in a persistent Docker volume (`bug-bench-tools`).

```bash
# Launch Claude Code against a bug case
./bench.sh agent <case-name> --addon claude-code

# Shell with multiple tools
./bench.sh shell <case-name> --addon claude-code --addon custom-gdb-dashboard

# Non-interactive agent with prompt
./bench.sh agent <case-name> --addon aider --prompt "Read SYMPTOM.md and fix the bug"
```

Available addons: `claude-code`, `aider`, `codex`, `mini-swe-agent`, `custom-gdb-dashboard`, `rr-debugger`. See `addons/README.md` for writing custom addons.

API keys (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`) are forwarded from host. Agent configs (`~/.claude/`) mounted read-only.

### Container mount layout

| Path | Contents | Writable? |
|------|----------|-----------|
| `/workspace/worktrees/<case>/` | Project source code at the buggy commit, with built binaries. Edit/build/debug here. | Yes |
| `/bench/` | Case scripts (reproduce.sh, case.yaml, docs). Same path in both VS Code and `bench.sh shell`. | No |

Reproduce a bug: `bash /bench/reproduce.sh` (works the same regardless of entry method).

## Working with cases (host fallback, no Docker)

```bash
cd cases/<case-name>/
./setup.sh       # installs deps via apt-get, clones, builds on host
./reproduce.sh   # triggers bug → PASS/FAIL
```

- Workspace defaults to `$HOME/bug-bench/`, override with `BENCH_WORKSPACE=/path`
- Requires Ubuntu 24.04, sudo access for apt-get

## Covered projects (62 verified cases)

| Project | Language | Cases |
|---------|----------|-------|
| Dragonfly | C++ | 14 |
| NATS Server | Go | 9 |
| Kvrocks | C++ | 8 |
| etcd | Go | 7 |
| Raft (hashicorp) | Go | 6 |
| Consul | Go | 3 |
| ZooKeeper | Java | 3 |
| Kafka | Scala/Java | 3 |
| BookKeeper | Java | 2 |
| raft-rs (TiKV) | Rust | 2 |
| ClickHouse | C++ | 1 |
| RocksDB | C++ | 1 |
| Seastar | C++ | 1 |
| RabbitMQ | Erlang | 1 |
| Ra | Erlang | 1 |

## No build/test commands for this repo itself

This is a benchmark suite — there's no code to build or test at the repo level. Each case is self-contained with its own build system.
