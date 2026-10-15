# hashicorp/raft #609: Pre-Vote Refreshes Last-Contact, Blocking New Elections

| Field | Value |
|-------|-------|
| Project | [hashicorp/raft](https://github.com/hashicorp/raft) |
| PR | [#609](https://github.com/hashicorp/raft/pull/609) |
| Language | Go |
| Category | Protocol Logic Error / Liveness Violation |

## Bug Summary

When a follower grants a pre-vote request, it incorrectly calls `setLastContact()`, updating the "last contact with leader" timestamp. Pre-vote is not a heartbeat from a leader, so this is wrong. If pre-vote requests keep arriving (e.g., from a misconfigured node with a low election timeout), followers never time out their election timer and cannot transition to candidate state. The cluster becomes unable to elect a new leader even after the real leader stops sending heartbeats.

## Quick Start

```bash
# from the repository root
./bench.sh setup raft-609-prevote-contact-liveness        # build image + case repository, warm caches
./bench.sh reproduce raft-609-prevote-contact-liveness    # FAIL (exit 1) while the bug is present
./bench.sh shell raft-609-prevote-contact-liveness        # explore: source at /workspace/src, oracle at /bench/reproduce.sh
```

## Prerequisites

Docker (all toolchains are in the `bug-bench/raft` image; see the top-level README).

## Build Notes

- No build step. The oracle injects `inject_test.go` into package `raft` (it uses package-internal APIs) and runs it with `INTEG_TESTS=1`: a 3-node cluster over the TCP transport on localhost, no external services.

## What to Expect

**When the bug is present (FAIL):**
The test creates a 3-node cluster, spams followers with pre-vote requests, and blocks real leader heartbeats. Followers cannot time out because pre-votes keep refreshing `lastContact`. No new leader is elected. The test reports FAIL.

**When the bug is fixed (PASS):**
Pre-vote requests no longer refresh `lastContact`. Followers time out normally after the real leader's heartbeats are blocked, transition to candidates, and elect a new leader. The test reports PASS.

## Detailed Documentation

- [`symptom.md`](symptom.md) — Observable behavior and error messages
- [`reproduce.md`](reproduce.md) — Step-by-step reproduction procedure and what PASS/FAIL mean
- [`reproduce.sh`](reproduce.sh) — The oracle (exit 0 PASS, 1 FAIL, 2 ERROR)
