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

1. `./bench.sh setup <case-name>` → if fails, phase = `setup`
2. `./bench.sh reproduce <case-name>` → if exits non-zero without `FAIL:`, phase = `reproduce`; if `FAIL:` present, Direction 1 verified — continue to oracle
3. Oracle check per `/verify-oracle` Direction 2 → if fails, phase = `oracle`

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
| **A7** | `worktree already exists` | Stale state | Run `./bench.sh clean <case-name>` and retry |

**A6 is the most common.** Read the full build error. Sub-causes: missing cmake flag, wrong Go version (check go.mod), missing C++ dependency, wrong build directory.

---

#### Category B: REPRODUCE failures (exits non-zero WITHOUT `FAIL:`)

| Type | Pattern | Diagnosis | Fix |
|---|---|---|---|
| **B1** | `cannot find package`, `undefined:` | inject_test.go API mismatch | Read source at buggy commit, fix imports/types |
| **B2** | `Binary not found` | Wrong binary path | Check `build.binary` in case.yaml, `find` actual path |
| **B3** | `address already in use` | Port conflict | Add `pkill` cleanup at script start |
| **B4** | `command not found` | Missing tool | Add to Dockerfile or install in reproduce.sh. `sudo: command not found` → drop `sudo` (images ship none; `bench.sh reproduce` already runs as root) and prefer faults that need no root |
| **B5** | `syntax error`, `unbound variable` | Script error | Run `bash -n reproduce.sh`, fix syntax |
| **B6** | Exit 124 / hangs | Timeout | Increase timeout, check for deadlock |
| **B7** | `panic:` in test harness | Test crashes | Fix test setup — likely nil deref from missing helper |

**Category B errors can hide behind a `FAIL:` verdict.** If a trigger step errors and the script carries on, it may still print FAIL. Treat any error in the trigger path as Category B, even when the verdict is FAIL. Make the script exit 2 (`ERROR:`) on a failed trigger.

**B1 is the second most common overall.** The injected test uses APIs from the fix commit that don't exist at the buggy commit. Always read the relevant source at the buggy commit (via `docker run`) before editing inject_test.go.

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

#### Category D: ORACLE — fix commit FAILS (should PASS)

See also: `/verify-oracle` for full oracle soundness validation.

| Type | Pattern | Diagnosis | Fix |
|---|---|---|---|
| **D1** | Compile error after checkout | Fix has different deps | Check `git diff <buggy>..<fix> -- CMakeLists.txt go.mod Makefile` |
| **D2** | Test fails for different reason | Test too broad | Narrow assertion to exact bug behavior only |
| **D3** | `undefined:` in test | API changed between commits | Use only APIs that exist on BOTH commits |
| **D4** | `DATA RACE` in test code | Test has own race | Fix synchronization in test itself |
| **D5** | Still shows buggy behavior | Wrong fix commit | Re-read PR, check if fix is in a different commit |
| **D6** | Missing symbols after checkout | Submodule drift | Add `git submodule update --init --recursive` after checkout |
| **D7** | `reference is not a tree` / unknown revision for the fix commit | Containment truncates the case repo to buggy ancestry, so the fix commit isn't there | Apply the fix diff from the project cache volume to a scratch copy of the case volume (`/verify-oracle` Step 3) |
| **D8** | Fixed build FAILs only because detection is slower than the observation window | Window tuned to buggy timing, too tight for the fix's timeout | Widen the window well beyond the fix's timeout (e.g. 3× it) so alternative fixes also pass |

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
Failure Type: <A1-A7|B1-B7|C1-C4|D1-D6>
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
- `/verify-oracle` — runs both-direction oracle check (detects Categories C, D)
- `mining-protocol/authoring-guide.md` Phase 3 — Dockerfile creation guidance
- `mining-protocol/case-anatomy.md` Section 7 — reproduce.sh conventions
