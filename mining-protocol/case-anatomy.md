# Case Anatomy

Every case produces files in three locations. All files are mandatory unless marked optional.

```
cases/<project>-<issue#>-<slug>/
├── case.yaml          # Declarative spec: drives bench.sh setup / reproduce / reset
├── reproduce.sh       # Executable oracle: exit 0 PASS / 1 FAIL / 2 ERROR (bench.sh containers only)
├── symptom.md         # Observable behavior only; copied into the worktree as SYMPTOM.md
├── README.md          # Entry point linking the other files
├── reproduce.md       # Human-readable step-by-step reproduction + what PASS/FAIL mean
├── context/           # Optional: observational debug context (context-augmented condition)
└── <harness files>    # Optional: oracle inputs read from /bench, e.g. inject_test.go,
                       #   inject_test/, test_main.go, test_*.cc

cases-solution/<project>-<issue#>-<slug>/
├── solution.md        # Root cause, fix locus, diagnosis chain (kept out of cases/)
└── gold.patch         # Source-only fix; bench.sh validate-oracle applies it

.devcontainer/<project>-<issue#>-<slug>/
└── devcontainer.json  # Generated from mining-protocol/templates/devcontainer.json
```

There is no per-case setup script or setup document. `case.yaml` is the declarative spec and
`./bench.sh setup <case>` is the only setup entry point. Everything runs in Docker; there is
no host mode.

## How bench.sh uses these files

| Command | What it does with the case |
|---------|----------------------------|
| `setup` | Builds `bug-bench/<project>`; clones the project once into the cache volume; creates the case repository truncated to the buggy commit's ancestry (aborts if the containment check fails); runs `build.command` **online**; copies `symptom.md` into the worktree as `SYMPTOM.md` and generates `REBUILD.sh` from `build.command`; runs the oracle once online to warm the dependency cache (expects FAIL; ERROR aborts setup; `--no-warm` skips it); resets the worktree. |
| `reproduce` | Runs `build.command` **offline**, then `reproduce.sh` in a fresh offline container with the case directory mounted read-only at `/bench`. Exit code = the oracle's verdict. |
| `rebuild` | Runs the worktree's `REBUILD.sh` (offline). |
| `reset` | Restores the pristine buggy worktree, fresh `SYMPTOM.md` and `REBUILD.sh`, removes oracle leftovers (`*ddbench*oracle*` files, surefire/failsafe reports, `ct_run.*`, untracked `logs/`, cargo test binaries), then rebuilds. |
| `eval` / `validate-oracle` | `reset`, optionally `git apply` a patch (`gold.patch` for `validate-oracle`), then `reproduce` N times. |
| `shell` / `agent` | Interactive containers on the same worktree; see [docker-containment.md](docker-containment.md#container-mounts). |

---

## 1. case.yaml

Declarative metadata consumed by `bench.sh` (a pure-bash parser) and by `scripts/` (a small
Python reader). Keep the format simple: exactly 2-space indentation, inline lists only
(`caps: ["NET_ADMIN"]`, never block sequences), and comments on their own lines (a trailing
`# comment` after a nested value becomes part of the value).

```yaml
name: <case-name>
project: <project>              # selects docker/<project>.Dockerfile
repo: https://github.com/ORG/REPO.git
buggy_commit: "<fix-sha>~1"     # any rev resolvable in the full clone
fix_commit: "<fix-sha>"          # upstream fix; null (with fix_commit_note) if none
resolve_time:
  date: "YYYY-MM-DD"
  source: confirmed_fix_commit_date   # or issue_close_date
  reference: "https://github.com/ORG/REPO/issues/N"
submodules: false
build:
  command: "<build command run in /workspace/src>"
  binary: <path relative to the worktree, or "">
docker:
  caps: []
  num_cpus: 10
  # seccomp_unconfined: true   # only if needed (e.g. io_uring)
  # offline: false             # last resort: give scoring containers network
```

| Key | Rules |
|-----|-------|
| `name` | Equals the case directory name. |
| `project` | Lowercase; `docker/<project>.Dockerfile` must exist. Also names the shared cache volume `bug-bench-<project>-cache`. |
| `repo` | `https://` clone URL ending in `.git`. |
| `buggy_commit` | Quoted. Any revision resolvable in the full-history clone; by convention `"<fix-sha>~1"`. `reset` resolves it from the project cache. |
| `fix_commit` | Quoted 40-char SHA of the upstream fix. When `gold.patch` is a backport or there is no upstream fix commit, set it accordingly (`null` if none) and add a top-level `fix_commit_note: "..."` explaining. |
| `resolve_time` | When the bug was resolved upstream: the later of the confirmed fix-commit date and the issue close date. `source` is `confirmed_fix_commit_date` (then `reference` is the commit SHA) or `issue_close_date` (then `reference` is the issue URL). |
| `submodules` | `true` or `false`, unquoted. With `true`, setup initializes submodules recursively. |
| `build.command` | Runs from `/workspace/src` during setup (online) and before every oracle run (offline). Multi-line builds may use a YAML block scalar (`\|`). Empty string (`""`) if nothing needs building: `REBUILD.sh` then falls back to a language compile check (`go build ./...`, `cargo build`, ...). |
| `build.binary` | Relative to the worktree root; `""` for test-only cases. |
| `docker.caps` | Extra capabilities as an inline list; `[]` for none. `SYS_PTRACE` is always added. |
| `docker.num_cpus` | CPUs the case needs. Containers get `--cpus = min(num_cpus, Docker host CPUs)`, capped further by the `BENCH_CPUS` environment variable, and `nproc` inside reports the same number. Oracles that size thread pools or tune timing from the CPU count depend on it. |
| `docker.seccomp_unconfined` | Optional; `true` only when the code needs syscalls Docker's default profile blocks (e.g. io_uring). |
| `docker.offline` | Optional; `false` gives scoring containers network access. Last resort, see [docker-containment.md](docker-containment.md#offline-scoring-and-the-dependency-cache). |

---

## 2. symptom.md

Describes the bug from the perspective of someone who encounters it — an operator, developer, or on-call engineer observing system behavior — without revealing the root cause. `bench.sh setup` copies it into the worktree as `SYMPTOM.md`: it is the agent's entry point in both evaluation conditions.

```markdown
# Symptom

<1-3 sentence summary of the bug's observable effect. Frame it as what an operator would see.>

## Observable behavior
- <Bullet list of specific symptoms: crash signal, error message, data anomaly, etc.>
- <Include what works correctly as contrast, if helpful.>
- <Describe relevant runtime/cluster context: what operation was in progress, what cluster state triggers it.>
```

**Rules:**
- Do NOT include root cause analysis or fix hints
- Do NOT include code snippets from the fix
- Do NOT name the buggy function, variable, or code path
- Do NOT link the upstream issue, PR, or fix commit, and do not point to `context/` (it exists only in the context-augmented condition, whose prompt introduces it)
- Use concrete, observable language: "process crashes with SIGABRT", "subscription count grows monotonically", "test fails with DATA RACE"
- **Describe the runtime context that triggers the bug** — this is where the runtime evidence begins. E.g., "after a leader step-down", "when a slow replica is connected", "under concurrent MULTI/EXEC from multiple clients". The symptom should make clear that understanding the distributed/runtime context is necessary, without pointing to the code.
- The symptom should convey *what kind of evidence* a debugger would need to collect (logs, cluster state, replication status, client responses) without spelling out the diagnosis
- After editing `symptom.md` of a case that is already set up, run `./bench.sh reset <case>` to refresh the worktree's `SYMPTOM.md`

### Prohibited patterns (information leakage)

The following MUST NOT appear in `symptom.md`. Cross-reference against `solution.md` when reviewing.

| Prohibited | Example (BAD) | Rewrite (GOOD) |
|------------|---------------|-----------------|
| Function/method names from the fix | "ChangeMonitor is not idempotent" | "Calling MONITOR twice crashes the process" |
| Variable or struct field names from the fix | "the `cc_` field is set twice" | "An assertion failure occurs" |
| Internal constants or magic numbers from the buggy path | "RDB encoding type 62 is unhandled" | "The replica fails with an unknown encoding error" |
| File paths pointing to the fix location | "the bug is in `server/jetstream.go`" | "The consumer stops delivering messages" |
| Fix description or strategy | "adding synchronization around the close path" | "A data race is detected during shutdown" |
| Root cause mechanism | "the waitgroup.Add is called after Wait returns" | "The test fails intermittently with a data race warning" |
| Error messages only visible in source code | "Check failed: cc_" (from a CHECK macro) | "The process crashes with an assertion failure" |
| PR/commit references to the fix | "Fixed in PR #6615" | (omit entirely) |

**Litmus test**: Read the symptom file, then read the solution. If the symptom text would let you `grep` your way to the fix location, it leaks too much.

---

## 3. reproduce.sh

The case's correctness oracle. It decides whether the bug is present in the current worktree
and reports the verdict through its exit code.

### Where it runs

Only inside bench.sh containers:

- the reproduce container started by `./bench.sh reproduce <case>` (also used by `eval`,
  `validate-oracle`, `eval-all`, harness scoring, and the setup warm-up), or
- `bash /bench/reproduce.sh` inside `./bench.sh shell <case>` or the case's devcontainer.

Started anywhere else (e.g. `cases/<case>/reproduce.sh` on the host), the prelude hands over
to `./bench.sh reproduce <case>`. In the reproduce container:

| Item | Value |
|------|-------|
| Worktree (and working directory) | `$BENCH_WORKDIR` = `/workspace/src`, read-write |
| Case directory | `/bench`, read-only (`$CASE_DIR`) |
| Dependency cache | `/deps`, via `GOMODCACHE`, `GOCACHE`, `CARGO_HOME`, `GRADLE_USER_HOME`, `MAVEN_OPTS` |
| Network | none (`--network none`; hostname `ddbench` resolves to 127.0.0.1), unless the case sets `docker.offline: false` |
| User | root (the images ship no `sudo`) |
| CPUs | `docker.num_cpus` (see above) |

`bench.sh reproduce` has already run `build.command` offline before starting the oracle; a
build failure there is reported as FAIL without running `reproduce.sh`.

### Exit codes

| Exit | Line printed last | Meaning |
|------|-------------------|---------|
| 0 | `PASS: ...` | The bug is fixed. |
| 1 | `FAIL: ...` | The bug is present, **or** the worktree does not build, **or** the code under test does not start, never reaches the baseline state, crashes, or hangs. |
| 2 | `ERROR: ...` | The oracle's own machinery failed and the verdict is inconclusive: required tool or harness file missing, trigger not established, the oracle test produced no result and no compile error explains it, a dependency download failed during the online warm-up. |

Anything the code under test does wrong is FAIL, never ERROR. Scoring records ERROR as an
infrastructure problem, separately from FAIL, so an `exit 2` caused by a broken patch would
excuse that patch. If the injected oracle test does not compile, report FAIL: a patch may
have changed an API the test uses, and `validate-oracle` catches an oracle that does not
compile against the fix. bench.sh maps any other exit code (signals, `set -e` accidents) to
ERROR; `eval` and `validate-oracle` count a run that exceeds `--timeout` as FAIL.

### The prelude

Every `reproduce.sh` starts (after its header comment, which ends with the exit-code summary)
with exactly this block. Copy it from a template; do not edit it.

```bash
# ── Runs only inside the bench.sh reproduce container (BENCH_WORKDIR is set) ──
if [ -z "${BENCH_WORKDIR:-}" ]; then
    CASE_NAME="$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)")"
    REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    [ -f "$REPO_ROOT/bench.sh" ] && exec bash "$REPO_ROOT/bench.sh" reproduce "$CASE_NAME"
    echo "ERROR: run this oracle with ./bench.sh reproduce $CASE_NAME" >&2
    exit 2
fi
set -uo pipefail

CASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$BENCH_WORKDIR"
RUN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ddbench.XXXXXX")"   # scratch space outside the worktree

pass()  { echo ""; echo "PASS: $*"; exit 0; }
fail()  { echo ""; echo "FAIL: $*"; exit 1; }
error() { echo ""; echo "ERROR: $*"; exit 2; }

# REBUILD.sh is the worktree's designated build entry point.
rebuild_worktree() {
    [ -f "$WORK_DIR/REBUILD.sh" ] || error "REBUILD.sh not found in $WORK_DIR (run setup first)"
    bash "$WORK_DIR/REBUILD.sh" || fail "the worktree does not build (REBUILD.sh exited non-zero)"
}
```

### Rules

1. **Build first.** Register the cleanup trap (rule 3), then call `rebuild_worktree` before running anything else. Every `reproduce.sh` runs the worktree's `REBUILD.sh`: it is the build entry point agents use too. A non-zero exit is FAIL.
2. **Inject oracle tests fresh, under ddbench-only names.** Test functions and classes are named `DDBenchOracle*` (Go `TestDDBenchOracle...`, Java `DDBenchOracle...Test`, Erlang/Rust `ddbench_oracle_...`), and new files `zz_ddbench_oracle_*` (Go `zz_ddbench_oracle_test.go`) or `DDBenchOracle*.java`. Nothing in the worktree, including a test an agent added, can then stand in for the oracle. When the oracle has to go into an existing file (an Erlang suite, a Rust integration-test file), save the worktree's copy in `$RUN_DIR`, inject into the pristine version (`git show HEAD:<path>`), and restore the saved copy on exit.
3. **Clean up in an `EXIT` trap.** Remove injected files and everything built or reported from them (test classes, surefire reports, Common Test logs, `.beam` files, cargo test binaries), stop every process the script started, and restore files it modified. `reset` sweeps the usual leftovers too, but the oracle must not depend on that.
4. **Decide from structured output for the exact oracle test**, never from free text the code under test could print: `go test -json` events, surefire/JUnit XML reports, Common Test `suite.log`, libtest `test <name> ... ok` lines (output capture on). A test that did not run is never a PASS. For server oracles, decide from process state and protocol replies, not from log lines. Copy the helpers from a real case: `cases/raft-358-negative-log-range/reproduce.sh` (Go), `cases/zookeeper-4643-sync-epoch-ordering/reproduce.sh` (JUnit XML), `cases/ra-439-election-livelock/reproduce.sh` (Erlang Common Test), `cases/raft-rs-345-readindex-config-change/reproduce.sh` (cargo), `cases/dragonfly-6856-flushslots-oob/reproduce.sh` (server crash).
5. **Keep scratch files in `$RUN_DIR`** (data directories, configs, logs, saved copies), never in the worktree.
6. **Read harness files from `$CASE_DIR`** (`/bench`) at run time. Builds never mount the case directory, so nothing from it ever lands in the agent-visible worktree through a build.
7. **Nothing may be downloaded at reproduce time.** Scoring runs offline against the dependency cache filled during setup. Everything the oracle needs (test-only dependencies included) must be fetched by `build.command` or by the warm-up run, on every path the oracle can take. Never hard-code cache locations (`-Dmaven.repo.local=...`, `GOPATH`, `CARGO_HOME`, `GRADLE_USER_HOME`): the environment already points them at `/deps`.
8. **Confirm the trigger took effect** before judging (fault injected, request delivered, node really down, connection really stalled); otherwise `error "trigger not established (...)"`. Never hide trigger errors with `2>/dev/null` or `|| true`.
9. **Observe the behavior the fix changes**, not a side metric of the workload, and use only options, commands and APIs that exist at the buggy commit. Make detection windows generous (well beyond the fix's own timeouts) so alternative fixes pass. Test the *correct behavior*, not merely the absence of a crash: where possible, assert on expected output (e.g. "PING returns PONG", "namespace still accessible", "subscription count stable").
10. **No `sudo`** (the images ship none and the oracle already runs as root). Prefer process-level faults (`SIGSTOP`/`SIGCONT`, kill, a pausable proxy) over `iptables`/`tc`: they need no extra capabilities and target exactly one peer.
11. **Bounded client calls** (`timeout 5 redis-cli ...`), so a hung server yields a verdict instead of a hung oracle. Treat a failed status query as unknown, never as "healthy".
12. **Observational wording.** Comments and messages describe what is observed, not the root-cause mechanism. Agents never see `/bench`; this is defense in depth.
13. Port numbers: use the `1<issue#>` convention (e.g., issue 6614 → port 16614).

### Common shell pitfalls

- **`set -e`**: never. The prelude sets `set -uo pipefail`; check exit codes explicitly.
- **Sleep-based readiness checks**: Don't `sleep 5` and hope the server is ready. Poll actively, e.g. `for i in $(seq 1 30); do timeout 2 redis-cli -p $PORT PING 2>/dev/null && break; sleep 0.2; done`, and check that the process is still alive while waiting.
- **Port conflicts**: in a long-lived shell container, a previous run may still hold the port. Kill leftovers before starting (`pkill -f "dragonfly.*--port $PORT" 2>/dev/null || true`); the `|| true` is fine here because this is not a trigger step.
- **Trap ordering**: define `cleanup()` and `trap cleanup EXIT` before starting any process.
- **Unbound variables**: with `set -u`, initialize PIDs (`SERVER_PID=""`) before the trap can reference them.

### Reproduction strategies (by bug type)

| Bug Type | Strategy | Example |
|----------|----------|---------|
| Server crash | Start server → send trigger → check `kill -0 $PID` and a PING reply | dragonfly-6614 |
| Go test failure | Adapt the fix's regression test into a `TestDDBenchOracle*` test → run it on the worktree | nats-7718 |
| Data race | Run the oracle test with `-race`, N iterations | etcd-19172 |
| Deadlock | Run the oracle test under `timeout`, N iterations | raft-268 |
| Data loss | Write data → trigger condition → verify data exists | kvrocks-3148 |
| Resource leak | Run workload → measure metric → check threshold (validate with a no-bug control run) | nats-7718 |
| Liveness / stall | Freeze a peer (`SIGSTOP`) → confirm the stall → check detection/recovery within a generous window | kvrocks-3356 |

---

## 4. reproduce.md

Human-readable step-by-step instructions to trigger the bug manually, inside `./bench.sh shell <case>` (worktree `/workspace/src`).

```markdown
# Reproduce: <Project> #<Issue>

All commands run inside `./bench.sh shell <case>`, from the worktree `/workspace/src`.

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

## Oracle verdict

`./bench.sh reproduce <case>` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): <what the oracle observes when the bug is present>. A worktree that does not build, or <the code under test> that does not start, is also FAIL.
- **PASS** (exit 0): <what the oracle requires once the bug is fixed>.
- **ERROR** (exit 2): <when the oracle cannot decide>.
```

**Rules:**
- Number every step
- Include full commands (not abbreviated)
- Specify ports, flags, and config inline — no "see other doc" references
- State "Expected result (bug present)" clearly
- End with "Oracle verdict": one or two sentences each for FAIL, PASS and ERROR, matching what `reproduce.sh` actually checks, with the specific signal or exit code where applicable (e.g., "SIGABRT=134"). Do not paste the oracle's code; `reproduce.sh` is the definition
- For Go test-based cases, show the `go test` command and expected failure output
- For server-based cases, show startup command + trigger commands
- Observational wording only (defense in depth, like reproduce.sh)

---

## 5. README.md

Entry point for the case (template: `templates/case-README.md`).

```markdown
# <Project> #<Issue>: <Short Bug Title>

| Field | Value |
|-------|-------|
| Project | [<Project>](<project-github-url>) |
| Issue | [#<Issue>](<issue-url>) |
| Language | <C++|Go|Java|Scala|Rust|Erlang> |
| Category | <Crash|Data race|Deadlock|Resource leak|Data loss|Logic error|Performance> (<detail>) |

## Bug Summary

<2-3 sentences on the trigger and its observable impact.>

## Quick Start

```bash
./bench.sh setup <case>        # image, truncated case repository, build, dependency warm-up
./bench.sh reproduce <case>    # run the oracle: exit 0 PASS, 1 FAIL, 2 ERROR
./bench.sh shell <case>        # interactive shell; rerun with: bash /bench/reproduce.sh
```

## What to Expect

**When the bug is present (FAIL):** <what reproduce.sh reports on the buggy commit>

**When the bug is fixed (PASS):** <what it reports once the bug is fixed>

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) -- The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
```

The README is never mounted into agent containers, but as defense in depth the Bug Summary describes what is observed, not the root-cause mechanism.

---

## 6. context/ (optional)

Observational debug context for the context-augmented condition: `bench.sh agent --context`
(or `harness/run_agent.sh --context`) copies it into an opaque volume and mounts it read-only
at `/workspace/src/context`. Without `--context` the agent never sees it. One markdown file
per artifact (`crash-output.md`, `race-detector.md`, `code-investigation.md`, ...). How to
write it: [authoring-guide.md](authoring-guide.md#authoring-context).

---

## 7. Oracle harness files (optional)

Files the oracle needs besides `reproduce.sh`: an injected Go test (`inject_test.go`), a
directory of Java test sources (`inject_test/`), a Go driver (`test_main.go`), a C++ test
program (`test_*.cc`). They live in the case directory, are read from `$CASE_DIR` at run time,
and are injected under `DDBenchOracle*` / `zz_ddbench_oracle_*` names. Their test functions
already carry the oracle name (e.g. `func TestDDBenchOracleNamespaceFullSync`).

---

## 8. solution.md and gold.patch (in cases-solution/)

Kept out of `cases/` so they can never be mounted into a container. `solution.md` is the
evaluation key: it documents the fix locus and the reasoning chain a correct diagnosis
follows. `gold.patch` is the reference fix the oracle must accept.

```markdown
# Solution: <Project> #<Issue>

- **Issue:** <issue URL>
- **Fix commit:** `<fix-sha>` (PR: <PR URL>)
- **Gold patch:** [`gold.patch`](gold.patch): the source-only part of the fix

## Fix locus
- **Component:** <subsystem/module name, e.g., "transaction engine", "Raft snapshot", "subscription manager">
- **Files:** <files changed in gold.patch>

## Root cause
<2-3 sentences explaining WHY the bug happens at a code level.>

## Diagnosis chain
<How would a debugger arrive at the root cause? What runtime evidence points toward the component?
What code reasoning narrows it to the specific fault? This section documents the expected
reasoning path — the interplay of runtime observation and code analysis.>

## Fix description
<1-2 paragraphs explaining WHAT the fix changes.>

## How to verify
```bash
./bench.sh validate-oracle <case> --runs 3
```
```

**Rules for solution.md:**
- The file starts with `# Solution: <Project> #<issue>` followed by the header list with the `- **Issue:**`, `- **Fix commit:**` and `- **Gold patch:**` lines.
- **Fix locus is required** — at minimum, name the component and list the files. This enables evaluation of whether a debugging tool correctly localized the fault.
- **Diagnosis chain is required** — describe the reasoning path from symptom to root cause, explicitly noting where runtime evidence and code reasoning each contribute. This is the evaluation rubric for diagnostic accuracy.

**Rules for gold.patch:**
- A unified diff relative to the repository root that applies with `git apply` to a pristine worktree at `buggy_commit`. `./bench.sh validate-oracle` and `./bench.sh eval --patch` apply it exactly that way.
- Source only: the production-code part of the upstream fix. Leave out tests, docs, changelogs and CI files; the oracle supplies its own test.
- Derived from `fix_commit` (`git diff <fix>~1 <fix> -- <source paths>`, taken from the project cache volume, since case repositories do not contain the fix). For a backport or a hand-written fix, explain in `fix_commit_note`.
- No new third-party dependencies: scoring builds offline, so a patch that needs a download cannot build.
- It must make the oracle PASS on every run: `./bench.sh validate-oracle <case> --runs 3` reports `SOUND`.

---

## 9. devcontainer.json (in .devcontainer/)

VS Code Dev Container configuration that mirrors `./bench.sh shell <case>`: the project image,
the case's worktree volume at `/workspace` (folder `/workspace/src`), its dependency volume at
`/deps`, and the case directory read-only at `/bench`. Generate it from
`mining-protocol/templates/devcontainer.json` by substituting `CASE_NAME`, `PROJECT`,
`CASE_UID` (`printf %s <case> | sha256sum | cut -c1-12`, or `./bench.sh info <case> uid`) and
`TODO_EXTENSIONS`, or regenerate all configs with `python3 scripts/generate_devcontainers.py`.
Run `./bench.sh setup <case>` first: the volumes it uses are created by setup.

---

## Naming Conventions

| Element | Convention | Example |
|---------|-----------|---------|
| Case folder | `<project>-<issue#>-<slug>` | `dragonfly-6614-monitor-multiexec` |
| Slug | lowercase, hyphen-separated, 2-4 words | `monitor-multiexec`, `embed-data-race` |
| Port | `1<issue#>` | `16614`, `17718` |
| Case uid | first 12 hex chars of sha256(case name) | `./bench.sh info <case> uid` |
| Worktree volume | `bug-bench-ws-<uid>` | |
| Dependency volume | `bug-bench-deps-<uid>` | |
| Context volume | `bug-bench-ctx-<uid>` | |
| Container | `bug-bench-<uid>` | `docker ps --filter label=ddbench.case=<case>` |
| Project cache volume | `bug-bench-<project>-cache` | `bug-bench-dragonfly-cache` |
| Docker image | `bug-bench/<project>` | `bug-bench/dragonfly` |
| Worktree path (every container) | `/workspace/src` | |
| Oracle test names | `DDBenchOracle*` / `ddbench_oracle_*`; files `zz_ddbench_oracle_*` | `TestDDBenchOracleCompactLogsRange` |
