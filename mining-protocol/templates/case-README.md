# PROJECT #ISSUE: TODO Short Bug Title

| Field | Value |
|-------|-------|
| Project | [PROJECT](https://github.com/ORG/REPO) |
| Issue | [#ISSUE](https://github.com/ORG/REPO/issues/ISSUE) |
| Language | LANGUAGE |
| Category | TODO: Crash / Data race / Deadlock / Resource leak / Data loss / Logic error / Performance (detail) |

## Bug Summary

TODO: 2-3 sentences on the trigger and its observable impact. Describe what is observed, not the root-cause mechanism or the fix.

## Quick Start

```bash
# From the repository root
./bench.sh setup CASE_NAME       # image, truncated case repository, build, dependency warm-up
./bench.sh reproduce CASE_NAME   # run the oracle: exit 0 PASS, 1 FAIL, 2 ERROR
./bench.sh shell CASE_NAME       # interactive shell in /workspace/src; rerun with: bash /bench/reproduce.sh
```

## What to Expect

**When the bug is present (FAIL):**
TODO: What reproduce.sh reports on the buggy commit.

**When the bug is fixed (PASS):**
TODO: What reproduce.sh reports once the bug is fixed.

## Detailed Documentation

- [`symptom.md`](symptom.md): observable behavior and error messages
- [`reproduce.md`](reproduce.md): step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh): the oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
