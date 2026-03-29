# Setup: hashicorp/raft -- LogCache Caches on StoreLogs Error

## Project
- **Repository:** https://github.com/hashicorp/raft
- **Language:** Go
- **Issue:** https://github.com/hashicorp/raft/issues/429
- **Fix PR:** https://github.com/hashicorp/raft/pull/460
- **Fix commit:** `f810f43d71b4a051a0c0e16e003f0a55456dd0fb`

## Build from source

```bash
git clone https://github.com/hashicorp/raft.git
cd raft
# Checkout parent of fix commit to get the buggy version
git checkout f810f43d71b4a051a0c0e16e003f0a55456dd0fb~1
```

## Download dependencies

```bash
go mod download
```

## Inject the test

Copy the test file into the raft source directory:
```bash
cp /path/to/inject_test.go ./logcache_store_order_bug_test.go
```

The test must be in `package raft` because it accesses internal types (`LogStore` interface, `LogCache`, `Log`, `ErrLogNotFound`, `NewInmemStore`, `NewLogCache`).

## Prerequisites
- Go 1.15+ (the buggy commit predates Go module changes; any Go version with module support works)
- The test creates only in-memory data structures, no external services needed.
