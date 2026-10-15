# Case Templates

Skeleton files for a new case. They go to three different places, so never copy this
directory wholesale: copy each file to its destination (see [How to use](#how-to-use)).

## Files

| Template | Copy to | Purpose |
|----------|---------|---------|
| `case.yaml` | `cases/<case>/case.yaml` | Declarative spec read by `bench.sh` (repo, commits, build, Docker settings) |
| one `reproduce*.sh` variant | `cases/<case>/reproduce.sh` | The oracle (exit 0 PASS / 1 FAIL / 2 ERROR); `chmod +x` |
| `symptom.md` | `cases/<case>/symptom.md` | Observable behavior only; copied into the worktree as `SYMPTOM.md` |
| `reproduce.md` | `cases/<case>/reproduce.md` | Human-readable reproduction steps and what the oracle's PASS/FAIL/ERROR mean |
| `case-README.md` | `cases/<case>/README.md` | Entry point with metadata table |
| `solution.md` | `cases-solution/<case>/solution.md` | Root cause, fix locus, diagnosis chain |
| (no template) | `cases-solution/<case>/gold.patch` | Source-only unified diff (relative to the repository root) that makes the oracle PASS; `./bench.sh validate-oracle` applies it |
| `devcontainer.json` | `.devcontainer/<case>/devcontainer.json` | VS Code dev container mirroring `./bench.sh shell` |

There is no setup template: `case.yaml` is the declarative spec and `./bench.sh setup <case>`
is the only setup entry point. Optional per-case files without a template: oracle harness
files (`inject_test.go`, `inject_test/`, ...) and `context/` (see
[../authoring-guide.md](../authoring-guide.md#authoring-context)).

## Reproduce templates

Pick the one that fits the bug type and install it as `reproduce.sh`.

| Template | Bug Type | Examples |
|----------|----------|---------|
| `reproduce.sh` | Generic skeleton (start → trigger → confirm → check) | — |
| `reproduce-go-test-inline.sh` | Go test written inline as a heredoc | etcd-20221, raft-358 |
| `reproduce-go-test-inject.sh` | Go test from the case's `inject_test.go`, run in a loop | kvrocks-2520, raft-581 |
| `reproduce-go-race-loop.sh` | Go data race (`-race` detector, loop) | nats-7707, raft-517 |
| `reproduce-server-crash.sh` | Server crash (start → trigger → liveness check) | dragonfly-6856 |
| `reproduce-server-correctness.sh` | Data correctness (two nodes → baseline → trigger → read back) | kvrocks-2214 |

For JVM, Erlang and Rust oracles, start from `reproduce.sh` and copy the verdict helpers of a
real case: JUnit/surefire XML in `cases/zookeeper-4643-sync-epoch-ordering/reproduce.sh`,
Common Test `suite.log` in `cases/ra-439-election-livelock/reproduce.sh`, libtest status lines
in `cases/raft-rs-345-readindex-config-change/reproduce.sh`.

## Oracle conventions (all reproduce templates)

Full contract: [../case-anatomy.md](../case-anatomy.md#3-reproducesh).

- Every template starts with the standard prelude (after its header comment). Keep it
  verbatim: it re-runs the oracle through `./bench.sh reproduce` when started on the host,
  and defines `WORK_DIR`, `CASE_DIR`, `RUN_DIR`, `pass`/`fail`/`error` and `rebuild_worktree`.
- Exit codes: `0` = `PASS:`, `1` = `FAIL:`, `2` = `ERROR:`. FAIL also covers a worktree that
  does not build and code under test that does not start or never reaches the baseline
  state. ERROR is only for the oracle's own machinery (trigger not established, harness
  file missing, no test result and no compile error to explain it).
- Register the `cleanup` trap, then call `rebuild_worktree` before running anything else; a failed `REBUILD.sh` is FAIL.
- Inject oracle tests fresh under `DDBenchOracle*` names (Go: `TestDDBenchOracle...` in
  `zz_ddbench_oracle_test.go`) and remove them in the `EXIT` trap, together with anything
  compiled or reported from them.
- Decide from structured output for the exact oracle test (`go test -json` events,
  JUnit XML, Common Test `suite.log`, libtest status lines), never from free text.
- Scratch files go in `$RUN_DIR`; harness files are read from `$CASE_DIR` (`/bench`).
- Confirm the trigger took effect before the verdict. No `sudo`; prefer process-level faults.
- Scoring runs offline: nothing may be downloaded at reproduce time.

## Placeholders

| Placeholder | Example | Where |
|-------------|---------|-------|
| `CASE_NAME` | `etcd-20221-watch-restore-revision` | `case.yaml`, `*.md`, `devcontainer.json` |
| `<case-name>` | `etcd-20221-watch-restore-revision` | `reproduce*.sh` only: their prelude uses a shell variable called `CASE_NAME`, so never run a blanket `sed s/CASE_NAME/...` over them |
| `PROJECT` | `etcd` | `case.yaml` (lowercase, = `docker/<project>.Dockerfile`), headings, `devcontainer.json` |
| `CASE_UID` | `printf %s <case> \| sha256sum \| cut -c1-12` | `devcontainer.json` (same as `./bench.sh info <case> uid`) |
| `ORG` / `REPO` | `etcd-io` / `etcd` | GitHub URLs |
| `ISSUE`, `PR_NUMBER` | `20221` | Issue and PR numbers |
| `FIX_COMMIT_HASH` | `9fb8c368...` (40 hex chars) | `case.yaml`, `solution.md` |
| `BUILD_COMMAND` | `make build` | `case.yaml` |
| `BINARY_PATH` | `bin/etcd` | `case.yaml`, server templates (relative to the worktree) |
| `LANGUAGE` | `Go` | `case-README.md` |
| `GO_MODULE_ROOT` | `server` | Go templates: directory holding `go.mod`, relative to the worktree (`.` for the root) |
| `GO_PACKAGE_DIR` | `storage/mvcc` | Go templates: package under test, relative to `GO_MODULE_ROOT` |
| `TODO_GO_PACKAGE_NAME` | `mvcc` | `reproduce-go-test-inline.sh`: package clause of the injected test |
| `ORACLE_TEST_NAME` | `TestDDBenchOracleWatchRestoreFutureRevision` | Go templates; must start with `TestDDBenchOracle` |
| `TEST_ITERATIONS`, `RACE_ITERATIONS` | `5` | Loop counts |
| `TODO_PORT`, `TODO_PORT1`, `TODO_PORT2` | `16614` | Convention: `1<issue#>` |
| `TODO_EXTENSIONS` | `golang.go` | `devcontainer.json`: VS Code extensions for the language |

Every other `TODO...` marks text to write.

## How to use

```bash
CASE=<project>-<issue#>-<slug>        # e.g. raft-358-negative-log-range
PROJECT=<project>                     # must match docker/<project>.Dockerfile
VARIANT=reproduce-server-crash.sh     # the reproduce template that fits (table above)
T=mining-protocol/templates

# 1. Case files: only these go into cases/<case>/
mkdir -p "cases/$CASE"
cp "$T/case.yaml" "$T/symptom.md" "$T/reproduce.md" "cases/$CASE/"
cp "$T/case-README.md" "cases/$CASE/README.md"
cp "$T/$VARIANT" "cases/$CASE/reproduce.sh"
chmod +x "cases/$CASE/reproduce.sh"

# 2. Solution files, outside cases/ (never mounted into any container)
mkdir -p "cases-solution/$CASE"
cp "$T/solution.md" "cases-solution/$CASE/solution.md"
#    ...and write cases-solution/$CASE/gold.patch (see ../case-anatomy.md)

# 3. Dev container config: once case.yaml is filled in, generate it (same layout as
#    devcontainer.json here, plus the case's caps/seccomp and the project's extensions;
#    add the project to EXTENSIONS in the script if it is new)
python3 scripts/generate_devcontainers.py

# 4. Case name and project. Not CASE_NAME in reproduce.sh: its prelude uses a shell
#    variable of that name, so the reproduce templates write the case name as <case-name>.
sed -i -e "s/CASE_NAME/$CASE/g" -e "s/PROJECT/$PROJECT/g" \
    "cases/$CASE"/*.md "cases/$CASE/case.yaml" "cases-solution/$CASE/solution.md"
sed -i "s/<case-name>/$CASE/g" "cases/$CASE/reproduce.sh"

# 5. List what is left to fill in
grep -rnE 'TODO|ORG|REPO|ISSUE|PR_NUMBER|FIX_COMMIT_HASH|BUILD_COMMAND|BINARY_PATH|LANGUAGE|GO_[A-Z_]+|ORACLE_TEST_NAME|_ITERATIONS' \
    "cases/$CASE" "cases-solution/$CASE"
```

Or use `/newcase` (scaffolding only) or `/mine` (end to end), which do the same.
