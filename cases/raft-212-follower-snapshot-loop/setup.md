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

## Go version requirement

**This commit predates Go modules (2017).** It requires Go 1.16 or earlier with `GOPATH`-based builds, or `GO111MODULE=off` with manual dependency installation. With Go 1.17+, the standard `go build` / `go test` commands will fail because there is no `go.mod` file.

To build with a modern Go toolchain, set up a GOPATH workspace:
```bash
export GO111MODULE=off
export GOPATH=/tmp/gopath
mkdir -p $GOPATH/src/github.com/hashicorp
ln -sf $(pwd) $GOPATH/src/github.com/hashicorp/raft
cd $GOPATH/src/github.com/hashicorp/raft
# Manually clone dependencies into GOPATH:
git clone https://github.com/armon/go-metrics $GOPATH/src/github.com/armon/go-metrics
git clone https://github.com/hashicorp/go-msgpack $GOPATH/src/github.com/hashicorp/go-msgpack
go test -c -o raft_test
```

Alternatively, use Go 1.16 via a version manager (e.g., `goenv`, `gvm`, or download from https://go.dev/dl/).

## Build test binary (Go <= 1.16 only)
```bash
go test -c -o raft_test ./...
```

## Dependencies (Go <= 1.16 only)
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
