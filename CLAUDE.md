# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A benchmark suite of 31 verified real-world bug cases from open-source distributed systems. Each case has automated scripts (`setup.sh` + `reproduce.sh`) that build from source and reliably reproduce the bug. Cases run in isolated Docker containers via `bench.sh`, with a host-only fallback for environments without Docker.

## Repository structure

- `bench.sh` — Central orchestrator (setup, reproduce, shell, reset, clean)
- `docker/` — Layered Dockerfiles (base-cpp, base-go → per-project images)
- `.devcontainer/` — Per-case VS Code devcontainer configs (31 total)
- `cases/<project>-<issue#>-<slug>/` — Bug case files
  - `case.yaml` — Declarative metadata (project, commit, build cmd, Docker caps)
  - `setup.sh` — Docker wrapper with host fallback
  - `reproduce.sh` — Docker wrapper with host fallback
  - `README.md` — Quick start guide
  - `symptom.md` — Observable behavior and error messages
  - `reproduce.md` — Step-by-step reproduction procedure
  - `verification.md` — Pass/fail verification criteria
- `cases-solution/<project>-<issue#>-<slug>/solution.md` — Root cause + fix (do not consult during evaluation)
- `index.md` — Master index of all 31 verified cases

## Working with cases (Docker, recommended)

```bash
./bench.sh setup <case-name>       # build image, clone, checkout, compile
./bench.sh reproduce <case-name>   # run reproduce.sh in container → PASS/FAIL
./bench.sh shell <case-name>       # interactive shell (gdb, source, tools)
./bench.sh reset <case-name>       # revert source to original buggy commit
./bench.sh clean <case-name>       # remove worktree for this case
./bench.sh clean-all               # remove all Docker artifacts
```

Same-project cases share a single git clone via Docker volumes.

## Working with cases (host fallback, no Docker)

```bash
cd cases/<case-name>/
./setup.sh       # installs deps via apt-get, clones, builds on host
./reproduce.sh   # triggers bug → PASS/FAIL
```

- Workspace defaults to `$HOME/bug-bench/`, override with `BENCH_WORKSPACE=/path`
- Requires Ubuntu 24.04, sudo access for apt-get

## Covered projects (31 verified cases)

| Project | Language | Cases |
|---------|----------|-------|
| Dragonfly | C++ | 14 |
| NATS Server | Go | 5 |
| Kvrocks | C++ | 4 |
| etcd | Go | 3 |
| Raft (hashicorp) | Go | 2 |
| ClickHouse | C++ | 1 |
| RocksDB | C++ | 1 |
| Seastar | C++ | 1 |

## No build/test commands for this repo itself

This is a benchmark suite — there's no code to build or test at the repo level. Each case is self-contained with its own build system.
