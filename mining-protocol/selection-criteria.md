# Selection Criteria

## Design Intent

This benchmark evaluates the ability to **diagnose** bugs in distributed systems — not merely to detect or reproduce them. A well-chosen case forces the debugger (human or AI agent) to combine two distinct modes of reasoning:

1. **Repository/code reasoning** — reading source, tracing call paths, understanding invariants, navigating module boundaries.
2. **Bounded runtime/cluster evidence** — interpreting logs, server output, cluster topology, configuration, traces, replication state, or multi-node behavior observable within the container.

Cases where either mode alone suffices are excluded: a bug you can fix by reading the stack trace tests only runtime reasoning; a bug you can fix by grepping for the function name tests only code search. The benchmark targets the intersection — cases where the debugger must *correlate* what the system does at runtime with why the code allows it.

---

A bug must satisfy **all** of the following to qualify for the benchmark.

## Mandatory Requirements

### 1. Real-world origin
The bug must come from a public GitHub issue or PR in an actively maintained open-source distributed system. No synthetic or contrived bugs.

### 2. Pinned buggy/fixed commit pair
A merged fix must exist. The fix commit is used to derive the buggy commit (`fix_commit~1`) and, for Go projects, to extract regression tests. The two commits define an unambiguous ground truth: buggy behavior on one side, correct behavior on the other.

### 3. Deterministic reproduction
The bug must be reproducible with >90% reliability in an automated script. Per-iteration flakiness (e.g., a race that fires 40% of the time) is acceptable only if the script aggregates enough iterations to produce a reliable aggregate verdict (e.g., 20-50 loop iterations with a per-run timeout). A case that sometimes *passes for wrong reasons* (e.g., timing-dependent false PASS) is not acceptable.

### 4. Oracle-backed verification
The reproduce script must embody a **correctness oracle** — a ground-truth definition of expected behavior that mechanically distinguishes correct from incorrect. This is stronger than "check if it crashed":

- The oracle must be **sound**: no false positives (buggy code passing) and no false negatives (fixed code failing).
- The oracle reports via exit code: `exit 1` = FAIL (bug present), `exit 0` = PASS (bug fixed), `exit 2` = ERROR. A broken trigger must never reach the PASS/FAIL verdict. ERROR is only for failures of the oracle's own machinery, independent of the code under test (missing tool, trigger not established, injected oracle test doesn't compile, `-run` matches nothing). Anything the code under test does wrong (doesn't build, doesn't start, never reaches the baseline state, crashes) is FAIL. Scoring counts every non-zero exit as FAIL; ERROR is a diagnostic for case authors, never an exemption.
- The oracle must observe the behavior the **fix changes**, not a side quantity the workload produces anyway. (Counter-example: kvrocks-3356 originally thresholded data-dir size after a write benchmark. That size exceeded the threshold even with no replica attached, so the oracle FAILed regardless of the bug.)
- The oracle must be validated in both directions, repeatedly: confirmed FAIL on the buggy commit (for the right reason: no trigger errors, plus a negative control for metric oracles), and confirmed PASS on the exact fix tree (hash-verified, clean build). See `/verify-oracle`.

Examples of oracles: process survival check after a crash-triggering input, assertion on query results after a data-loss trigger, race detector output after N iterations, subscription count comparison after a workload.

### 5. Self-contained reproduction
The reproduction must require **only**:
- The project's own source code at the buggy commit
- Standard build tools available in the project's base Docker image
- Lightweight client tools (redis-cli, curl, netcat, python3) already in base images

It must **not** require:
- External services (cloud APIs, remote databases, third-party servers)
- Proprietary tooling or licenses
- Hardware-specific features (GPU, FPGA, specific NIC)
- Multi-host networking (everything runs on localhost)

### 6. Clear fix locus
The bug must have a **clear component-level locus** — an identifiable subsystem, module, or layer of the system where the fault lives. Preferably, the fix is localized to a small set of files (ideally 1-3 files, < 50 lines changed). This makes it possible to evaluate whether a debugging tool correctly narrowed down the fault location.

Cases where the fix is scattered across many components with no clear center of gravity are poor benchmark candidates — they test breadth of refactoring, not depth of diagnosis.

### 7. Dual-reasoning requirement
Diagnosis must **materially require both**:

- **Code/repository reasoning**: understanding source-level invariants, data structures, control flow, module interactions — things learned by reading the codebase.
- **Runtime or cluster evidence**: interpreting observable system behavior — logs, error messages, server output, cluster topology, configuration state, replication status, traces, or multi-node interactions.

"Materially requires both" means:
- Code-only analysis is insufficient — you cannot identify the root cause by static reading alone (e.g., the bug involves a subtle interaction that only manifests under specific runtime conditions).
- Runtime-only analysis is insufficient — you cannot derive the fix from observable symptoms alone (e.g., the crash log points to a symptom site but the root cause is elsewhere).
- The debugger must correlate runtime evidence ("consumer stops delivering after leader step-down") with code reasoning ("the filter subject state isn't persisted through the Raft snapshot") to converge on the fix.

### 8. Not solvable from issue text alone
The GitHub issue description must not contain enough information to derive the fix without examining code and runtime behavior. Issues that say "function X is broken, change line Y" are trivially solvable and bypass the diagnostic process this benchmark is designed to evaluate.

### 9. Reasonable build time
The project must build from source within ~30 minutes on a 4-core machine. Projects with multi-hour builds (e.g., Chromium) are excluded.

## Preferred Characteristics

These are not mandatory but make stronger benchmark cases:

- **Crash or assertion failure** — unambiguous failure signal (SIGABRT, SIGSEGV, SIGFPE)
- **Data correctness bug** — silent data loss, corruption, or wrong results
- **Concurrency bug** — race condition, deadlock, or livelock
- **Non-trivial to diagnose** — requires understanding of system internals, not just a typo fix
- **Distributed-system-native mechanism** — the bug arises from replication, consensus, sharding, leader election, distributed transactions, or multi-client coordination (even if reproduced on a single process)
- **Diverse project coverage** — prefer cases from underrepresented projects

## Bug Categories (observed in current suite)

| Category | Example | Signal | Typical runtime evidence |
|----------|---------|--------|--------------------------|
| Crash (assertion) | SIGABRT from failed `CHECK` | Exit code 134 | Stack trace, assertion message |
| Crash (memory) | SIGSEGV, SIGFPE, OOB access | Exit code 139, 136 | Signal, core dump |
| Data race | Go `-race` detector fires | "DATA RACE" in stderr | Race detector report with goroutine stacks |
| Deadlock | Operation hangs forever | Timeout exit code 124 | Hung goroutines, lock contention |
| Resource leak | Subscriptions/memory grow unbounded | Metric exceeds a threshold that a no-bug control stays well under | Monitoring endpoint, `/varz` |
| Liveness / stall | A component waits forever on a stuck peer | Peer frozen (e.g. `SIGSTOP`), stall confirmed, no recovery within a generous window | Thread dump, replication status |
| Data loss | Records silently disappear | Missing expected output | Query results, namespace state |
| Logic error | Wrong behavior under specific input | Assertion on output | Client response, server logs |
| Replication failure | Replica can't sync or diverges | Error log, retry loop | RDB encoding errors, WAL state |
| Performance regression | Throughput drops >20% | Benchmark comparison | Timing measurements |

## Exclusions

- **Shallow bugs** — where the fix is obvious from the error message or stack trace alone (e.g., a null pointer dereference where the trace points directly to the missing check)
- **Purely local bugs** — faults in non-distributed code paths with no distributed-system implications (standalone utility functions, string formatting, UI rendering)
- **Solvable from issue text** — the GitHub issue already describes the root cause and fix location with enough detail to patch without investigation
- **Unreliably flaky** — cannot achieve >90% aggregate failure rate even with iteration loops; or passes for wrong reasons (timing-dependent false PASS)
- Bugs that only manifest in production-scale deployments (thousands of nodes)
- Security vulnerabilities that require responsible disclosure
- Bugs in test infrastructure only (not in the system under test)
- Configuration-only issues (wrong defaults, missing docs)
- Bugs that require >1 hour of build time
