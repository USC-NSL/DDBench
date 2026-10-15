# /diagnose-case — Case Failure Diagnosis and Auto-Fix

Diagnose why a case's setup, reproduce, or oracle verification failed. Classify the failure, identify root cause, and apply fixes iteratively until the case passes.

Can be invoked standalone or is used internally by `/mine` during its verification loops (Phases 4-5).

## Usage

```
/diagnose-case <case-name>                          # auto-detect failure phase
/diagnose-case <case-name> --phase setup            # diagnose setup failure only
/diagnose-case <case-name> --phase reproduce        # diagnose reproduce failure only
/diagnose-case <case-name> --phase oracle            # diagnose oracle failure only
/diagnose-case <case-name> --report-only             # diagnose but do not modify files
```

## Procedure

### Step 1: Detect failure phase

If `--phase` not specified, run each phase and stop at the first failure. Capture the **last 50 lines** of output from the failing phase.

1. `./bench.sh setup <case-name>` → if fails, phase = `setup` (a setup that fails in its warm-up step, `warm-up failed: the oracle exited 2`, is a `reproduce` problem: see A8)
2. `./bench.sh reproduce <case-name>` → if it exits 2 (`ERROR:`) or without a verdict, phase = `reproduce`; if it exits 1 with `FAIL:`, Direction 1 verified — continue to oracle
3. `./bench.sh validate-oracle <case-name> --runs 3` (`/verify-oracle` Direction 2) → if not SOUND, phase = `oracle`

Exit-code contract of every reproduce.sh: 0 = PASS (bug fixed), 1 = FAIL (bug present, or the worktree does not build / the code under test does not start), 2 = ERROR (oracle or infrastructure problem; inconclusive).

### Step 2: Classify the failure

---

#### Category A: SETUP failures

| Type | Pattern | Diagnosis | Fix |
|---|---|---|---|
| **A1** | `Dockerfile not found` | No Docker image | Create Dockerfile per `mining-protocol/authoring-guide.md` Phase 3 |
| **A2** | `docker build` / `apt-get` error | Broken Dockerfile | Read error, fix deps or package names |
| **A3** | `repository not found` | Wrong repo URL | Verify `repo` in case.yaml |
| **A4** | `reference is not a tree` | Bad commit hash | Check solution.md commit, verify `~1` suffix, confirm 40-char hash |
| **A5** | `No url found for submodule` | Submodules not configured | Set `submodules: true` in case.yaml |
| **A6** | Compiler/make/cmake/go errors | Build command wrong | Read error, fix `build.command` in case.yaml or add deps to Dockerfile |
| **A7** | `set up by an older bench.sh`, stale or half-created volumes | Stale state | Run `./bench.sh clean <case-name>` and retry (`./bench.sh legacy-volumes` lists volumes of older layouts) |
| **A8** | `warm-up failed: the oracle exited 2 (ERROR)` | The oracle ERRORs on the buggy code | Diagnose as Category B: `./bench.sh setup <case-name> --no-warm`, then `BENCH_OFFLINE=0 ./bench.sh reproduce <case-name>` (an unwarmed cache cannot run offline) or `bash /bench/reproduce.sh` in `./bench.sh shell` |
| **A9** | `CONTAINMENT FAILURE` | The truncated case repository kept refs or extra commits | Do not use the case; check `buggy_commit`, `submodules`, and the repository's ref layout |
| **A10** | `fatal: Needed a single revision` while creating the case repository, `Cannot resolve buggy commit` at reset | The commit is not in the project cache (cache cloned before it, or a typo: see A4) | Update the cache: `docker run --rm -v bug-bench-<project>-cache:/cache bug-bench/<project> git --git-dir=/cache/repo.git fetch origin '+refs/heads/*:refs/heads/*'` |

**A6 is the most common.** Read the full build error. Sub-causes: missing cmake flag, wrong Go version (check go.mod), missing C++ dependency, wrong build directory.

---

#### Category B: REPRODUCE failures (exit 2 / `ERROR:`, or no verdict)

| Type | Pattern | Diagnosis | Fix |
|---|---|---|---|
| **B1** | `cannot find package`, `undefined:` | inject_test.go API mismatch | Read source at buggy commit, fix imports/types |
| **B2** | `Binary not found` | Wrong binary path | Check `build.binary` in case.yaml, `find` actual path |
| **B3** | `address already in use` | Port conflict | Add `pkill` cleanup at script start |
| **B4** | `command not found` | Missing tool | Add to Dockerfile or install in reproduce.sh. `sudo: command not found` → drop `sudo` (images ship none; `bench.sh reproduce` already runs as root) and prefer faults that need no root |
| **B5** | `syntax error`, `unbound variable` | Script error | Run `bash -n reproduce.sh`, fix syntax |
| **B6** | Exit 124 / hangs | Timeout | Increase timeout, check for deadlock |
| **B7** | `panic:` in test harness | Test crashes | Fix test setup — likely nil deref from missing helper |
| **B8** | `module lookup disabled by GOPROXY=off`, `--offline was specified`, `No cached version ... available for offline mode`, Maven offline resolution errors | The oracle needs a dependency the setup warm-up never fetched (scoring runs with `--network none`) | Make the build or every oracle path fetch it during setup, drop the dependency volume and re-run setup to re-warm; `docker.offline: false` only as a last resort |
| **B9** | `ERROR: run this oracle with ./bench.sh reproduce` | reproduce.sh was started outside a bench.sh container | Run it via `./bench.sh reproduce`, or `bash /bench/reproduce.sh` inside `./bench.sh shell` |

**Category B errors can hide behind a `FAIL:` verdict.** If a trigger step errors and the script carries on, it may still print FAIL. Treat any error in the trigger path as Category B, even when the verdict is FAIL. Make the script exit 2 (`ERROR:`) on a failed trigger. Conversely, a failure of the code under test (does not build, does not start) must be FAIL, not ERROR.

**B1 is the second most common overall.** The injected test uses APIs from the fix commit that don't exist at the buggy commit. Always read the relevant source at the buggy commit (`./bench.sh shell <case-name>`, worktree `/workspace/src`) before editing inject_test.go.

---

#### Category C: ORACLE — buggy commit PASSES (should FAIL)

See also: `/verify-oracle` for full oracle soundness validation.

| Type | Pattern | Diagnosis | Fix |
|---|---|---|---|
| **C1** | All iterations pass, no race | Race window too small | Increase iterations (5→20), add more concurrency, pre-seed data |
| **C2** | Intermittent pass/fail | Timing sensitive | Double sleep durations, use polling instead of fixed sleeps |
| **C3** | Clean pass, no hint of bug | Wrong commit | Verify: `git log --oneline <fix>~1..<fix>`, check multi-commit PRs |
| **C4** | Pass but assertion wrong | Test logic error | Re-read solution.md root cause, fix assertion |
| **C5** | Buggy FAILs, but for the wrong reason: the negative control (bug trigger removed) also FAILs, or the fix diff doesn't change the measured quantity | Oracle measures the workload/environment, not the bug (e.g. a disk-size threshold the write load alone exceeds) | Redesign: observe the behavior the fix changes (`/mine` Phase 1 + Phase 3 oracle rules); add an in-script trigger confirmation |
| **C6** | Fault injected but no effect (e.g. lag stays 0) | Fault targets the wrong path (e.g. iptables on a listening port while traffic uses the peer's ephemeral port) or silently failed | Use process-level faults (`SIGSTOP`, kill, pausable proxy) or match the real connection; assert the fault took effect |

---

#### Category D: ORACLE — gold patch FAILS (should PASS)

See also: `/verify-oracle` for full oracle soundness validation.

| Type | Pattern | Diagnosis | Fix |
|---|---|---|---|
| **D1** | Compile error after applying gold.patch | Patch incomplete, or the fix needs different deps | Check `git diff <buggy>..<fix> -- CMakeLists.txt go.mod Makefile` in the project cache; a patch that needs new third-party dependencies cannot build offline |
| **D2** | Test fails for different reason | Test too broad | Narrow assertion to exact bug behavior only |
| **D3** | `undefined:` in test | API changed between commits | Use only APIs that exist on BOTH commits |
| **D4** | `DATA RACE` in test code | Test has own race | Fix synchronization in test itself |
| **D5** | Still shows buggy behavior | Wrong fix commit, or gold.patch misses part of the fix | Re-read PR, check if fix is in a different commit; regenerate gold.patch |
| **D6** | Missing symbols after applying gold.patch | Fix changes a submodule (`git apply` cannot) | Note Direction 2 as unverified for the submodule part, or include the needed source change in gold.patch |
| **D7** | `reference is not a tree` / unknown revision for the fix commit | Containment truncates the case repo to buggy ancestry, so the fix commit isn't there | Derive gold.patch from the project cache volume (`/verify-oracle` Step 3a) |
| **D8** | Fixed build FAILs only because detection is slower than the observation window | Window tuned to buggy timing, too tight for the fix's timeout | Widen the window well beyond the fix's timeout (e.g. 3× it) so alternative fixes also pass |
| **D9** | `validate-oracle` ERROR: `gold.patch does not apply` | Patch made against another commit, or not relative to the repository root | Regenerate it as `git diff <fix>~1 <fix> -- <source paths>` and check `buggy_commit` is `<fix>~1` |

**D2 is the trickiest.** The test must be narrowed to only check the specific bug symptom, not collateral behavior.

---

### Step 3: Apply fix

Unless `--report-only`:

1. Apply the minimum change to the identified file(s)
2. Re-run the failing phase to verify
3. If same failure type recurs, escalate: read more source context, try alternative fix strategy
4. Max 3 attempts per phase

### Step 4: Report

```
=== Diagnosis Report: <case-name> ===
Phase: <setup|reproduce|oracle>
Failure Type: <A1-A10|B1-B9|C1-C6|D1-D9>
Root Cause: <1-2 sentences>
Fix Applied: <file>: <change description>
Verification: <re-run result>
Attempts: <N>/3
Status: <RESOLVED|UNRESOLVED>
```

If UNRESOLVED after 3 attempts:
```
UNRESOLVED: Manual intervention needed.
Last error: <summary>
Suggested next step: <specific action>
```

## References

- `/verify-cases` — runs setup + reproduce (detects Categories A, B)
- `/verify-oracle` — runs both-direction oracle check with `./bench.sh validate-oracle` (detects Categories C, D)
- `mining-protocol/authoring-guide.md` Phase 3 — Dockerfile creation guidance
- `mining-protocol/case-anatomy.md` Section 3 — reproduce.sh contract and conventions
