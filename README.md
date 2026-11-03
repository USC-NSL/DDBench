<p align="center">
  <a href="https://nsl.usc.edu/ddbench-site/">
    <img src="https://raw.githubusercontent.com/USC-NSL/ddbench-site/refs/heads/main/assets/logo/ddbench-logo-text.svg" alt="DDBench Logo" />
  </a>

  <h3 align="center">
    Evaluating Agentic Debugging Capabilities on Distributed Systems
  </h3>

  <p align="center"><strong>[&nbsp;<a href="https://nsl.usc.edu/ddbench-site/">Website for Leaderboard</a>&nbsp;]</strong></p>


  
  <p align="center">
    <a href="https://github.com/USC-NSL/DDBench/blob/main/LICENSE">
      <img src="https://img.shields.io/badge/License-Apache%202.0-blue.svg"
           alt="License: Apache 2.0" />
    </a>
  </p>
</p>


---

## 👋 Overview

DDBench is a benchmark for debugging real distributed-systems bugs. It brings together 60 reproducible bugs from 13 widely used open-source systems, spanning Go, C++, Java/Scala, Rust, and Erlang.

The project exists to make automated debugging and repair measurable in realistic settings. Each case captures a genuine historical failure, preserves the buggy state, and provides a reproducible way to determine whether a proposed fix works.

The repository contains the benchmark cases, containerized environments, scoring oracles, and tooling for running human- or agent-driven debugging experiments. Its goal is to support fair, repeatable evaluation while keeping the information available to an agent separate from the hidden evidence used for scoring.

## ✍️ Citation & license
Apache 2.0. Check [LICENSE.md](LICENSE).

If you find our work helpful, please use the following citations.

```bibtex
@inproceedings{yan2026ddbench,
  title     = {DDBench: A Benchmark for Agentic Debugging on Distributed Systems},
  author    = {Yan, Yibo and Wang, Huijuan and He, Junzhou and
               Liang, Yizhuo and Wang, Shaoyu and Sun, Huanchen and
               Park, Seo Jin},
  booktitle = {The Fortieth Annual Conference on Neural Information Processing Systems},
  year      = {2026},
  url       = {https://openreview.net/forum?id=xeI7yaisrf}
}
```

<details>
<summary>For Agents</summary>

The benchmark is designed for evaluating AI coding agents, program-analysis
tools and automated repair:

- **What the agent gets.** The agent works in a Docker container. It gets the
  buggy repository (with history truncated at the buggy commit) and
  `SYMPTOM.md`. In the context-augmented condition it also gets a short
  `context/` folder of debug observations (logs, test output, traces). It may
  build, run and edit anything in the worktree.
- **How it is scored.** `bench.sh` scores the edited worktree in a separate,
  offline container that runs the case's oracle. The result is
  **PASS** (fixed), **FAIL** (still buggy, or does not build) or
  **ERROR** (no verdict).
- **What the agent never sees.** The agent never sees the oracle
  (`cases/<case>/`), the solution (`cases-solution/<case>/`), or any upstream
  commit after the bug.

| Project | Language | Cases | Bug types |
|---------|----------|------:|-----------|
| [Dragonfly](https://github.com/dragonflydb/dragonfly) | C++ | 14 | crashes (SIGABRT/SIGFPE/OOB), replication encoding, protocol replies, search |
| [NATS Server](https://github.com/nats-io/nats-server) | Go | 9 | JetStream consumer/stream state, message loss, leaks, performance |
| [Kvrocks](https://github.com/apache/kvrocks) | C++ | 8 | replication gaps/stalls, deadlock, namespaces, protocol violations |
| [etcd](https://github.com/etcd-io/etcd) | Go | 7 | watch/compaction event loss, linearizability, data race, membership |
| [hashicorp/raft](https://github.com/hashicorp/raft) | Go | 6 | shutdown deadlock, log compaction, races, liveness |
| [Consul](https://github.com/hashicorp/consul) | Go | 3 | ACL replication stall, snapshot restore, streaming cache |
| [ZooKeeper](https://github.com/apache/zookeeper) | Java | 3 | ZAB sync ordering, snapshot/ACL race, committed-log hole |
| [Kafka](https://github.com/apache/kafka) | Java/Scala | 3 | rebalance loop, delayed fetch, transactional offsets |
| [BookKeeper](https://github.com/apache/bookkeeper) | Java | 2 | fencing races during recovery |
| [raft-rs](https://github.com/tikv/raft-rs) | Rust | 2 | conf-change during campaign, ReadIndex stall |
| [RocksDB](https://github.com/facebook/rocksdb) | C++ | 1 | shutdown hang with stalled writes |
| [RabbitMQ](https://github.com/rabbitmq/rabbitmq-server) | Erlang | 1 | quorum-queue crash after snapshot install |
| [Ra](https://github.com/rabbitmq/ra) | Erlang | 1 | election livelock |

[`index.md`](index.md) lists every case with its upstream issue. Cases are
grouped into three tiers (31 / 15 / 14), described in
[`registry/tier_definitions.md`](registry/tier_definitions.md).
[`docs/oracle-validation.md`](docs/oracle-validation.md) records the soundness
check of every oracle: the buggy commit must FAIL and the gold patch must PASS,
repeatedly.

## Quick start

```bash
./bench.sh setup raft-358-negative-log-range       # image, case repository, build, cache warm-up
./bench.sh reproduce raft-358-negative-log-range   # → "FAIL: Bug is present ..." (exit 1)

./bench.sh shell raft-358-negative-log-range       # look around: source in /workspace/src
./bench.sh eval raft-358-negative-log-range --patch my-fix.diff --json result.json
./bench.sh reset raft-358-negative-log-range       # back to the pristine buggy state
```

`./bench.sh help` lists every command and option. `./bench.sh list` shows which
cases are set up.

## Prerequisites

- Linux or macOS with **Docker** 23+ (BuildKit). The daemon must be able to
  pull from Docker Hub, GitHub and the language package registries during
  `setup`.
- **bash** 4.4+ and GNU coreutils (`timeout`, `sha256sum` or `shasum`). `git`
  is not needed on the host. **Python** 3.8+ (standard library only) is needed
  for `eval-all`, the `harness/` scripts and `scripts/`.
- Images are built for x86_64. Other architectures may work but are untested.

No toolchains, `sudo` or host packages are needed: every compiler, runtime and
tool lives in the per-project images (`docker/<project>.Dockerfile`).

### Resources

Each case container is limited to `min(num_cpus, Docker CPUs)` CPUs. This is
10 for all cases except one, and can be capped further with `BENCH_CPUS=N`.
`nproc` inside the container reports the same number. The figures below were
measured on a 64-core x86_64 machine with 10 CPUs per case. "Setup" is a first
`bench.sh setup` of one case: the project clone and image are shared by the
project's cases, so later cases of the same project are faster. "Oracle run"
is one `bench.sh reproduce` (incremental rebuild + oracle) on a set-up case.

| Project (cases) | Image | Disk per case: worktree + dependency cache | First build | Oracle run: median (max) |
|-----------------|------:|-------------------------------------------:|------------:|-------------------------:|
| Dragonfly (14) | 1.0 GB | 2.3 GB + — | ~8 min | 8 s (2 min) |
| Kvrocks (8) | 1.0 GB | 4.3 GB + — | ~8 min | 2.5 min (5 min) |
| RocksDB (1) | 0.8 GB | 0.25 GB + — | ~1.5 min | 40 s |
| NATS (9) | 0.65 GB | 0.1 GB + 0.85 GB | ~35 s | 12 s (2 min) |
| etcd (7) | 0.6 GB | 0.2 GB + 1.1 GB | ~45 s | 17 s (10 min) |
| Consul (3) | 0.6 GB | 0.4 GB + 1.3 GB | ~3 min | 4 s (20 s) |
| hashicorp/raft (6) | 0.6 GB | <0.01 GB + 0.15 GB | ~15 s | 10 s (7 min) |
| Kafka (3) | 0.75 GB | 0.75 GB + 0.85 GB | ~1.5 min | 2.3 min (4 min) |
| ZooKeeper (3) | 0.95 GB | 0.25 GB + 0.15 GB | ~1.2 min | 55 s |
| BookKeeper (2) | 0.95 GB | 0.2 GB + 0.2 GB | ~1.6 min | 1.8 min |
| raft-rs (2) | 1.9 GB | 0.65 GB + 0.1 GB | ~20 s | 6 s (15 s) |
| RabbitMQ (1) | 1.7 GB | 0.35 GB + — | ~5 min | 45 s |
| Ra (1) | 0.6 GB | 0.05 GB + — | ~15 s | 35 s |

- **First build.** This column times the `build.command` alone, from a clean
  checkout with an empty dependency cache. Building the image (once per
  project, 1–5 min) and cloning the project (once per project) come on top. So
  does the warm-up oracle run that setup ends with.
- **Long oracle runs.** The longest runs are race and stall oracles that
  repeat a scenario many times, for example raft-581 and etcd-19172.
- **All cases.** All 60 cases need roughly 100 GB of volumes plus about 12 GB of
  images and caches. A full `validate-oracle --runs 3` of 57 cases took about
  1.6 h of wall-clock time with 6–9 cases in parallel (about 6 h if run
  serially).

## Commands

| Command | What it does |
|---------|--------------|
| `setup <case> [--no-warm]` | Builds the project image if it is missing or its Dockerfile changed. Clones the project once into a cache volume, creates the case repository (only the buggy commit's ancestry), runs the build, and installs `SYMPTOM.md`/`REBUILD.sh` in the worktree. It then runs the oracle once online to fill the case's dependency cache (expected: FAIL). |
| `reproduce <case>` | Runs the oracle on the current worktree. Exit 0 = PASS, 1 = FAIL, 2 = ERROR. |
| `eval <case> --patch FILE` | Resets, applies the patch (`git apply`), runs the oracle `--runs N` times, resets again. With `--json OUT`, writes the result as JSON. |
| `validate-oracle <case>` | Checks the oracle itself: buggy must FAIL `--runs N` times, `gold.patch` must PASS N times. |
| `eval-all --predictions F --out D` | Runs `eval` for a JSONL file of patches, in parallel (`--jobs`), then aggregates. |
| `shell <case> [--addon X]` | Interactive human shell. Mounts the oracle at `/bench`, so `bash /bench/reproduce.sh` works. |
| `agent <case> --addon X [...]` | Runs an AI agent in an isolated container (see below). |
| `reset <case>` | Restores the pristine buggy worktree (removes edits, commits and oracle leftovers) and rebuilds it. |
| `rebuild <case>` | Runs the worktree's `REBUILD.sh` under scoring conditions (offline). |
| `info <case> [field]` | Prints the case's opaque Docker names, image, CPUs and resolved buggy SHA. |
| `list`, `build-images`, `stop`, `clean`, `clean-all`, `legacy-volumes` | Housekeeping. `legacy-volumes` lists volumes left by older layouts. `--remove` deletes them. |

### Exit-code contract

Every oracle (`cases/<case>/reproduce.sh`) and `bench.sh reproduce` use the same
exit codes:

| Exit | Verdict | Meaning |
|-----:|---------|---------|
| 0 | PASS | the bug is fixed |
| 1 | FAIL | the bug is present, or the worktree does not build / the code under test does not start |
| 2 | ERROR | the oracle or the infrastructure could not decide (not set up, Docker error, inconclusive run) |

`eval` uses the same codes for its aggregate verdict.

## Evaluating patches

A patch is a unified diff relative to the repository root (`git diff`
format, `a/`/`b/` prefixes). It is applied with `git apply` to the
pristine buggy commit. `harness/extract_patch.sh` produces such a diff from a
worktree an agent edited.

```bash
./bench.sh eval etcd-17529-watch-compaction-loss --patch fix.diff --runs 3 --json out.json
```

- **Aggregating runs.** If any run is FAIL, the verdict is **FAIL**: one
  definite failure is conclusive. Otherwise, if any run is ERROR, the verdict
  is **ERROR**: inconclusive, so re-run it. Only all-PASS gives **PASS**.
- **Patch that does not apply.** The verdict is FAIL with
  `"patch_applied": false`, and `apply_output` holds the `git apply` message.
- **Timeout.** A run that exceeds `--timeout` (default 3600 s, including the
  rebuild) is killed and counts as FAIL (`"timed_out": true`).
- **Offline scoring.** Scoring is offline, so a patch that adds a new
  third-party dependency cannot build and therefore FAILs.

`eval --json` writes (schema `ddbench.eval/v1`):

```json
{
  "schema": "ddbench.eval/v1",
  "case": "etcd-17529-watch-compaction-loss",
  "verdict": "PASS",
  "exit_code": 0,
  "exit_codes": [0, 0, 0],
  "n_runs": 3,
  "runs": [{"run": 1, "verdict": "PASS", "exit_code": 0, "timed_out": false,
            "duration_s": 74, "summary": "PASS: ...", "log": "/path/eval-run1.log"}],
  "patch_applied": true,
  "patch_file": "fix.diff",
  "patch_sha256": "…",
  "apply_output": "",
  "error": null,
  "reset_after": true,
  "timeout_s": 3600,
  "log_dir": "…/.bench/logs/eval-…",
  "duration_s": 251,
  "started_at": "2026-10-14T12:00:00Z",
  "timestamp": "2026-10-14T12:04:11Z"
}
```

`validate-oracle --json` writes (schema `ddbench.validate-oracle/v1`):

```json
{
  "schema": "ddbench.validate-oracle/v1",
  "case": "raft-358-negative-log-range",
  "status": "SOUND",
  "runs_per_side": 3,
  "buggy": {"expected": "FAIL", "matched": 3, "errors": 0, "exit_codes": [1, 1, 1], "runs": [...]},
  "gold":  {"expected": "PASS", "patch": "cases-solution/raft-358-negative-log-range/gold.patch",
            "patch_applied": true, "matched": 3, "errors": 0, "exit_codes": [0, 0, 0], "runs": [...]},
  "detail": "buggy FAIL 3/3, gold PASS 3/3",
  "timeout_s": 3600, "log_dir": "…", "duration_s": 61,
  "started_at": "…", "timestamp": "…"
}
```

The statuses are:

| Status | Exit | Meaning |
|--------|-----:|---------|
| SOUND | 0 | buggy FAILs every run and gold PASSes every run |
| UNSOUND | 1 | buggy never FAILs, or gold never PASSes |
| FLAKY | 1 | anything in between |
| ERROR | 2 | the case is not set up, a reset failed, a run returned ERROR, or `gold.patch` does not apply |
| NO-GOLD | 3 | the case has no `gold.patch`; the buggy runs are still reported |

### Batch evaluation

```bash
./bench.sh eval-all --predictions preds.jsonl --out results/my-model --jobs 4 [--runs 1] [--setup]
```

Each line of `preds.jsonl` is one of these:

- `{"case": "<case>", "patch": "<diff text>"}`
- `{"case": "<case>", "patch_file": "<path>"}`

The SWE-bench-style keys `instance_id` and `model_patch` are accepted, and an
optional `model_name_or_path` is recorded.

The command writes `<out>/<case>/{patch.diff,result.json,eval.log,logs/}` plus
`summary.json` and `summary.md`. The summaries report PASS, FAIL and ERROR
separately. ERROR is not counted as a failure: pass rate = PASS / (PASS + FAIL).
Cases run in parallel safely, because every case has its own volumes and
container. Use `--setup` to set up missing cases first. The exit status is 2 if
any case ended in ERROR.

## Running agents

Agents are installed at runtime by addons (`addons/examples/`, pinned
versions): `claude-code`, `codex`, `aider`, `mini-swe-agent`, plus the
`custom-gdb-dashboard` and `rr-debugger` debugging aids. See
[`addons/README.md`](addons/README.md).

```bash
./bench.sh agent <case> --addon claude-code                          # interactive
./bench.sh agent <case> --addon mini-swe-agent --prompt "Fix the bug in SYMPTOM.md" \
    --config harness/configs/ddbench_prompt.yaml --output-dir out/    # non-interactive
./bench.sh agent <case> --addon mini-swe-agent --context ...          # context-augmented
```

`harness/run_agent.sh` runs mini-swe-agent over a case or a whole tier. For each
case it runs setup, reset, the agent (with a timeout), scoring and a final
reset, and writes per-case `result.json`, `patch.diff`, the trajectory and a
summary:

```bash
MSWEA_MODEL_NAME=anthropic/claude-sonnet-4-20250514 harness/run_agent.sh --surface tier1
harness/run_agent.sh --surface tier1 --model openai/gpt-4o --context
harness/run_agent.sh --surface all --dry-run
```

Results go to `results/` (gitignored) unless `--results-dir` or
`DDBENCH_RESULTS_DIR` says otherwise. Configs and prompts are documented in
[`harness/configs/README.md`](harness/configs/README.md). The scripts and the
result format are described in [`harness/README.md`](harness/README.md).

## How cases are isolated

Inside every container the source tree is at **`/workspace/src`**:

| Path | Contents | setup / reproduce | shell / devcontainer | agent |
|------|----------|:-----------------:|:--------------------:|:-----:|
| `/workspace/src` | The case repository at the buggy commit, built, plus `SYMPTOM.md` and `REBUILD.sh` | rw | rw | rw |
| `/workspace/src/context` | `cases/<case>/context/` (read-only copy) | — | with `--context` | with `--context` |
| `/bench` | `cases/<case>/` (oracle, harness files, docs) | ro (reproduce) | ro | **never** |
| `/deps` | The case's dependency cache volume | rw | rw | empty, container-local |

The design has five parts:

- **History containment.** Each case repository is created by fetching only
  the ancestry of the buggy commit from a per-project bare clone. It then
  drops all refs and remotes and prunes unreachable objects. Setup aborts
  unless the repository holds exactly the buggy commit's ancestry. The full
  clone (`bug-bench-<project>-cache`) is mounted only during setup, and
  read-only by reset to resolve the commit.
- **Opaque identity.** Case names carry the issue number, so nothing an agent
  can observe contains them: the path, environment, hostname, volume names
  (`bug-bench-ws-<uid>`, `bug-bench-ctx-<uid>`, `bug-bench-deps-<uid>`) and
  container name (`bug-bench-<uid>`) do not. Here `<uid>` is the first 12 hex
  characters of sha256(case name). `./bench.sh info <case>` maps a case to its
  objects, and the Docker label `ddbench.case` lets you find them.
- **Agent isolation.** Agent containers get neither `/bench` nor the host
  `~/.claude`. The `claude-code` addon receives only `.credentials.json` and
  `settings.json`. Agent containers have network access, so they can read
  documentation. The agent prompt forbids searching for the upstream issue or
  fix.
- **Offline scoring with per-case dependency caches.** Go modules, toolchains
  and build cache, Cargo, Gradle and Maven all use `/deps`, a per-case volume.
  Setup fills it: it builds online, then runs the oracle once online so that
  test-only dependencies are fetched too. `reproduce`, `rebuild`, `eval` and
  the rebuild in `reset` then run with `--network none`, and Go, Cargo, Gradle
  and Maven are switched to offline mode. Scoring is therefore hermetic and
  does not re-download anything. A case can opt out with
  `docker.offline: false`; none does. `BENCH_OFFLINE=0` gives scoring network
  access for debugging.
- **Threat model for the caches.** The dependency cache is written by scoring
  runs, so it can contain artifacts compiled from oracle tests and from gold
  or candidate patches (Go build cache, Gradle caches, Maven-installed project
  jars). For that reason it is never mounted into agent containers. It is also
  per case: a shared cache once let an agent read a sibling case's later
  upstream version that contained the fix. The third-party content in it is
  pinned by the buggy commit's lock files. Agents use the same
  package-manager paths (`/deps/...`), but backed by an empty directory, and
  download what they need themselves.

Images are pinned for reproducibility:

- Base images are pinned by digest (`ubuntu:24.04`, `golang:1.23.6-bookworm`,
  `elixir:1.17-otp-26`, `erlang:26-slim`).
- Rust is pinned to 1.99.0, installed by a checksum-verified rustup-init 1.29.1.
- Delve is pinned to 1.27.2 and natscli to 0.3.0, both built with go1.26.9.
- Go toolchains newer than the image's are fetched by `GOTOOLCHAIN` according
  to each case's `go.mod`, then cached per case.
- Images carry a fingerprint of their Dockerfiles and are rebuilt
  automatically when those change.
- Distribution packages (`apt-get`) are not version-pinned.

## Anatomy of a case

```
cases/<project>-<issue#>-<slug>/
├── case.yaml         # spec: project, repo, buggy_commit, fix_commit, resolve_time, build, docker
├── reproduce.sh      # oracle; runs only inside the bench.sh scoring container
├── symptom.md        # observable failure; becomes SYMPTOM.md in the worktree
├── context/          # optional debug observations (--context condition)
├── README.md, reproduce.md   # human documentation; reproduce.md ends with what PASS/FAIL mean
└── (oracle harness files, e.g. inject_test.go, test_main.go)
cases-solution/<case>/
├── solution.md       # root cause and fix (header: Issue / Fix commit / Gold patch)
└── gold.patch        # source-only fix; validate-oracle requires it to PASS
```

`case.yaml` (2-space indentation; parsed by bash):

```yaml
name: raft-358-negative-log-range
project: raft                      # selects docker/raft.Dockerfile
repo: https://github.com/hashicorp/raft.git
buggy_commit: "7b09f38f739f486a692096c35236c7eef094e933~1"
fix_commit: "7b09f38f739f486a692096c35236c7eef094e933"
resolve_time:                      # later of fix-commit date and issue close date
  date: "2019-10-01"
  source: issue_close_date
  reference: "https://github.com/hashicorp/raft/issues/358"
submodules: false
build:
  command: ""                      # run in /workspace/src; becomes REBUILD.sh
  binary: ""
docker:
  caps: []
  num_cpus: 10
```

The oracles follow common rules:

- An oracle rebuilds through the worktree's `REBUILD.sh`.
- Oracle tests are injected fresh under `DDBenchOracle*` names and removed
  afterwards.
- Verdicts are read from structured test output (`go test -json`,
  JUnit/surefire XML, Erlang CT logs, cargo test results), never from free
  text.
- Run on the host, a `reproduce.sh` delegates to `./bench.sh reproduce`.

[`mining-protocol/`](mining-protocol/README.md) explains how to author new
cases.

## Repository structure

```
.
├── README.md, CLAUDE.md, index.md
├── bench.sh                     # orchestrator (./bench.sh help)
├── harness/                     # agent runner, scoring, patch extraction, eval-all backend
│   └── configs/                 # mini-swe-agent configs (repo-only / context, tool-call / text-based)
├── docker/                      # base-cpp, base-go and per-project Dockerfiles (digest-pinned)
├── addons/                      # runtime tool injection for shell/agent
│   └── examples/                # claude-code, codex, aider, mini-swe-agent, gdb-dashboard, rr
├── cases/                       # 60 cases (problem side; never visible to agents)
├── cases-solution/              # solution.md + gold.patch per case
├── .devcontainer/               # one VS Code devcontainer per case (generated)
├── registry/                    # case_registry.json, tiers, resolve_times.json, oracle_validation.json
├── docs/
│   ├── oracle-validation.md     # oracle soundness table
│   └── mining/                  # historical candidate-mining notes
├── analysis/                    # debug-context size statistics
├── scripts/                     # registry/devcontainer generators, statistics
├── mining-protocol/             # case authoring guide, checklist, templates
└── .claude/skills/              # Claude Code skills for mining and verifying cases
```

## VS Code

Run `./bench.sh setup <case>` first. Then use "Dev Containers: Reopen in
Container" and pick "DDBench - <case>". The devcontainer uses the same image,
volumes, mounts and environment as `bench.sh shell`, so
`bash /bench/reproduce.sh` works in its terminal. Regenerate the configs with
`python3 scripts/generate_devcontainers.py`.

## Maintenance

- `python3 scripts/generate_registry.py [--resolve]` regenerates
  `registry/case_registry.json` from the `case.yaml` files.
- `python3 scripts/benchmark_stats.py` and
  `python3 scripts/context_bundle_stats.py` refresh the statistics.
- Run `./bench.sh validate-oracle <case> --runs 3` after changing an oracle,
  a Dockerfile or a build command.
- Volumes from older layouts (`bug-bench-case-<case>-src`,
  `bug-bench-<project>-src`) are no longer used. `./bench.sh legacy-volumes`
  lists them, and `--remove` deletes them.

</details>
