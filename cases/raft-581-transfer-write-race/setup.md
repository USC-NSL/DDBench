# Setup: hashicorp/raft — Leadership Transfer Fails with Concurrent Writes

## Project
- **Repository:** https://github.com/hashicorp/raft
- **Language:** Go
- **Fix PR:** https://github.com/hashicorp/raft/pull/581

## Build from source

```bash
git clone https://github.com/hashicorp/raft.git
cd raft
# Checkout parent of fix commit to get the buggy version
git checkout 62eaa1c192d4c09c90caa5e227177eb9205a6267~1
```

## Create a test program

Create a directory for the test:
```bash
mkdir -p /tmp/raft-transfer-test
cd /tmp/raft-transfer-test
go mod init raft-transfer-test
```

Add the buggy version of raft as a dependency:
```bash
go mod edit -replace github.com/hashicorp/raft=/path/to/raft
go mod tidy
```

Build the test binary:
```bash
go build -o raft-transfer-test .
```

## Prerequisites
- Go 1.21+
- The test program creates an in-memory 7-node Raft cluster, so no external services are needed.
