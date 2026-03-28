# Setup: hashicorp/raft — Data Race Between runCandidate() and appendEntries()

## Project
- **Repository:** https://github.com/hashicorp/raft
- **Language:** Go
- **Issue:** https://github.com/hashicorp/raft/issues/517
- **Fix PR:** https://github.com/hashicorp/raft/pull/570

## Build from source

```bash
git clone https://github.com/hashicorp/raft.git
cd raft
# Checkout parent of fix commit to get the buggy version
git checkout 49bd61b66666fa76cb23fa81897e350f6e9b75de~1
```

## Create a test program

Create a directory for the test:
```bash
mkdir -p /tmp/raft-race-test
cd /tmp/raft-race-test
go mod init raft-race-test
```

Add the buggy version of raft as a dependency:
```bash
go mod edit -replace github.com/hashicorp/raft=/path/to/raft
go mod tidy
```

Build with the race detector:
```bash
go build -race -o raft-race-test .
```

## Prerequisites
- Go 1.21+
- The test program creates an in-memory 3-node Raft cluster, so no external services are needed.
