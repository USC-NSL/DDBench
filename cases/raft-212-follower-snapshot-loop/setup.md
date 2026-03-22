# Setup: hashicorp/raft #212

## Project
- **Repository:** https://github.com/hashicorp/raft
- **Language:** Go
- **Issue:** https://github.com/hashicorp/raft/issues/212

## Clone and checkout buggy version
```bash
git clone https://github.com/hashicorp/raft.git
cd raft
git checkout 37d2320db05ca622195063977ff5d4fbe0cd8ed8~1
```

## Build test binary
```bash
go test -c -o raft_test ./...
```

## Dependencies
```bash
go mod download
```

## Test environment
This bug requires a 3-node Raft cluster. You can use the in-memory transport provided by the library for testing:

```go
// Use inmem transport for testing
_, transport1 := raft.NewInmemTransport("")
_, transport2 := raft.NewInmemTransport("")
_, transport3 := raft.NewInmemTransport("")
```

Or use the TCP transport for a more realistic reproduction.
