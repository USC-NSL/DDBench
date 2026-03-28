# Case Templates

## Base templates (all cases)

| File | Purpose |
|------|---------|
| `case.yaml` | Machine-readable metadata |
| `setup.sh` | Clone + build (Docker preamble + host fallback) |
| `reproduce.sh` | Generic reproduce skeleton |
| `symptom.md` | Observable behavior description |
| `reproduce.md` | Human-readable reproduction steps |
| `verification.md` | PASS/FAIL criteria |
| `setup.md` | Human-readable build instructions |
| `README.md` | Entry point with metadata table |
| `solution.md` | Root cause + fix (in `cases-solution/`) |
| `devcontainer.json` | VS Code dev container config |

## Bug-type-specific reproduce templates

Choose based on bug type. These replace the generic `reproduce.sh`.

| Template | Bug Type | Examples |
|----------|----------|---------|
| `reproduce-go-test-inline.sh` | Go test (inline heredoc) | etcd-20221 |
| `reproduce-go-test-inject.sh` | Go test (external inject_test.go, with loop) | kvrocks-2520, raft-581 |
| `reproduce-go-race-loop.sh` | Go data race (`-race` detector, loop) | nats-7707, raft-517 |
| `reproduce-server-crash.sh` | Server crash (start → trigger → PID check) | dragonfly crash cases |
| `reproduce-server-correctness.sh` | Data correctness (cluster → write → verify) | kvrocks-2214 |

## Placeholders

All templates use uppercase placeholders. Replace before use:

| Placeholder | Example | Source |
|-------------|---------|--------|
| `CASE_NAME` | `etcd-20221-watch-restore-revision` | Directory name |
| `PROJECT` | `etcd` | case.yaml |
| `ORG` / `REPO` | `etcd-io` / `etcd` | GitHub URL |
| `ISSUE` | `20221` | Issue number |
| `FIX_COMMIT_HASH` | `9fb8c368...` | PR merge commit |
| `BUILD_COMMAND` | `make build` | Project build system |
| `BINARY_PATH` | `bin/etcd` | Build output |
| `LANGUAGE` | `Go` | Project language |
| `GO_PACKAGE_PATH` | `server/storage/mvcc` | Go package under test |
| `GO_MODULE_ROOT` | `server` | Directory containing go.mod |
| `TEST_FUNC_NAME` | `TestWatchRestoreFutureRevisionBug` | Injected test function |
| `TEST_FILE_NAME` | `watchable_store_restore_bug` | Test file name (without `_test.go`) |
| `RACE_ITERATIONS` | `5` | Number of `-race` runs |
| `TEST_ITERATIONS` | `5` | Number of test loop runs |
| `TODO_PORT` | `16614` | Convention: `1<issue#>` |

## How to use

```bash
# 1. Copy base templates
cp -r mining-protocol/templates/ cases/<case-name>/

# 2. Copy the right reproduce template over the generic one
cp mining-protocol/templates/reproduce-go-race-loop.sh cases/<case-name>/reproduce.sh

# 3. Replace placeholders
sed -i 's/CASE_NAME/my-case-name/g' cases/<case-name>/*

# 4. Fill in TODO sections with case-specific logic
```

Or use `/mine` which handles template selection and placeholder replacement automatically.
