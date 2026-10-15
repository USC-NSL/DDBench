# hashicorp/raft PR#581: Leadership Transfer Fails with Concurrent Writes

| Field | Value |
|-------|-------|
| Project | [hashicorp/raft](https://github.com/hashicorp/raft) |
| Issue | [PR#581](https://github.com/hashicorp/raft/pull/581) |
| Language | Go |
| Category | Logic error (leadership transfer race) |

## Bug Summary

Leadership transfer to a specific follower intermittently fails when write operations are being applied concurrently. After the transfer is initiated, the current leader continues accepting writes during a brief window, which advances its log beyond what the target has replicated. This causes the target to lose the subsequent election because other nodes with more up-to-date logs reject its vote requests.

## Quick Start

```bash
# from the repository root
./bench.sh setup raft-581-transfer-write-race        # build image + case repository, warm caches
./bench.sh reproduce raft-581-transfer-write-race    # FAIL (exit 1) while the bug is present
./bench.sh shell raft-581-transfer-write-race        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/raft` image; see the top-level README).

## Build Notes

- No build step. The oracle injects `inject_test.go` into package `raft` and runs it; the cluster is in-process, so no external services are needed.

## What to Expect

**When the bug is present (FAIL):**
Multiple leadership transfers out of 30 fail. The designated transfer target does not become the new leader; instead, a different node wins the election or the transfer times out.

**When the bug is fixed (PASS):**
Nearly all leadership transfers succeed, with the designated target reliably becoming the new leader despite concurrent write load.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) -- The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
