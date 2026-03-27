# Selection Criteria

A bug must satisfy **all** of the following to qualify for the benchmark.

## Mandatory Requirements

### 1. Real-world origin
The bug must come from a public GitHub issue or PR in an actively maintained open-source distributed system. No synthetic or contrived bugs.

### 2. Fixed upstream
A merged fix must exist. The fix commit is used to derive the buggy commit (`fix_commit~1`) and, for Go projects, to extract regression tests.

### 3. Deterministic reproduction
The bug must be reproducible with >90% reliability in an automated script. Flaky races are acceptable only if the script runs enough iterations to hit the failure consistently (e.g., 20-50 loop iterations with a per-run timeout).

### 4. Self-contained reproduction
The reproduction must require **only**:
- The project's own source code at the buggy commit
- Standard build tools available in the project's base Docker image
- Lightweight client tools (redis-cli, curl, netcat, python3) already in base images

It must **not** require:
- External services (cloud APIs, remote databases, third-party servers)
- Proprietary tooling or licenses
- Hardware-specific features (GPU, FPGA, specific NIC)
- Multi-host networking (everything runs on localhost)

### 5. Observable verdict
The script must produce a binary PASS/FAIL outcome via exit code:
- `exit 1` = FAIL (bug present)
- `exit 0` = PASS (bug fixed)

### 6. Reasonable build time
The project must build from source within ~30 minutes on a 4-core machine. Projects with multi-hour builds (e.g., Chromium) are excluded.

## Preferred Characteristics

These are not mandatory but make stronger benchmark cases:

- **Crash or assertion failure** — unambiguous failure signal (SIGABRT, SIGSEGV, SIGFPE)
- **Data correctness bug** — silent data loss, corruption, or wrong results
- **Concurrency bug** — race condition, deadlock, or livelock
- **Single root cause** — the fix is localized (ideally < 50 lines changed)
- **Non-trivial to diagnose** — requires understanding of system internals, not just a typo fix
- **Diverse project coverage** — prefer cases from underrepresented projects

## Bug Categories (observed in current suite)

| Category | Example | Signal |
|----------|---------|--------|
| Crash (assertion) | SIGABRT from failed `CHECK` | Exit code 134 |
| Crash (memory) | SIGSEGV, SIGFPE, OOB access | Exit code 139, 136 |
| Data race | Go `-race` detector fires | "DATA RACE" in stderr |
| Deadlock | Operation hangs forever | Timeout exit code 124 |
| Resource leak | Subscriptions/memory grow unbounded | Metric exceeds threshold |
| Data loss | Records silently disappear | Missing expected output |
| Logic error | Wrong behavior under specific input | Assertion on output |
| Performance regression | Throughput drops >20% | Benchmark comparison |

## Exclusions

- Bugs that only manifest in production-scale deployments (thousands of nodes)
- Security vulnerabilities that require responsible disclosure
- Bugs in test infrastructure only (not in the system under test)
- Configuration-only issues (wrong defaults, missing docs)
- Bugs that require >1 hour of build time
