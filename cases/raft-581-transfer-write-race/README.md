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
# 1. Set up the codebase (clone, checkout buggy commit, build test binary)
./setup.sh

# 2. Reproduce the bug and verify
./reproduce.sh
```

## Prerequisites

- Git
- Go 1.21+

## What to Expect

**When the bug is present (FAIL):**
Multiple leadership transfers out of 30 fail. The designated transfer target does not become the new leader; instead, a different node wins the election or the transfer times out.

**When the bug is fixed (PASS):**
Nearly all leadership transfers succeed, with the designated target reliably becoming the new leader despite concurrent write load.

## Detailed Documentation

- [`symptom.md`](symptom.md) -- Observable behavior and error messages
- [`setup.md`](setup.md) -- Detailed setup instructions
- [`reproduce.md`](reproduce.md) -- Step-by-step reproduction procedure
- [`verification.md`](verification.md) -- Pass/fail verification criteria
