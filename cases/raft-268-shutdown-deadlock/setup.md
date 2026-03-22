# Setup: hashicorp/raft — Shutdown() Deadlocks with Concurrent takeSnapshot()

## Project
- **Repository:** https://github.com/hashicorp/raft
- **Language:** Go
- **Issue:** https://github.com/hashicorp/raft/issues/268
- **Fix PR:** https://github.com/hashicorp/raft/pull/390

## Build from source

```bash
git clone https://github.com/hashicorp/raft.git
cd raft
# Checkout parent of fix commit to get the buggy version
git checkout 2e997410f28efe8106fc606d21cb655be1b05dee~1
```

## Create a test program

Create a directory for the test:
```bash
mkdir -p /tmp/raft-deadlock-test
cd /tmp/raft-deadlock-test
go mod init raft-deadlock-test
```

Add the buggy version of raft as a dependency:
```bash
go mod edit -replace github.com/hashicorp/raft=/path/to/raft
go mod tidy
```

## Prerequisites
- Go 1.21+
- The test program creates an in-memory Raft cluster, so no external services are needed.
