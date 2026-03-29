# Setup: hashicorp/raft — Pre-Vote Refreshes Last-Contact

## Project
- **Repository:** https://github.com/hashicorp/raft
- **Language:** Go
- **PR:** https://github.com/hashicorp/raft/pull/609
- **Fix commit:** `42d34464b2d203e389e11ed6d43db698792c0604`

## Build from source

```bash
git clone https://github.com/hashicorp/raft.git
cd raft
# Checkout parent of fix commit to get the buggy version
git checkout 42d34464b2d203e389e11ed6d43db698792c0604~1
```

## Download dependencies

```bash
go mod download
```

## Inject the test

Copy the test file into the raft source directory:
```bash
cp /path/to/inject_test.go ./prevote_contact_bug_test.go
```

The test must be in `package raft` because it accesses internal APIs (`localID`, `localAddr`, `getRPCHeader`, `getCurrentTerm`, `getLastIndex`, `processHeartbeat`, `SetHeartbeatHandler`). It also requires `NetworkTransport` (TCP) for the heartbeat fast-path that allows intercepting heartbeats independently from other RPCs.

## Prerequisites
- Go 1.21+
- The test creates an in-memory 3-node Raft cluster with TCP transport, so no external services are needed.
