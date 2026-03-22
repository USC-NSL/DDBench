# Setup: hashicorp/raft #291

## Project
- **Repository:** https://github.com/hashicorp/raft
- **Language:** Go
- **Issue:** https://github.com/hashicorp/raft/issues/291

## Clone and checkout buggy version
```bash
git clone https://github.com/hashicorp/raft.git
cd raft
git checkout da92cfe76e0c1c9b94bbc9d884ec4b2b3b90b699~1
```

## Go version requirement

**This commit predates Go modules.** It requires Go 1.16 or earlier with `GOPATH`-based builds. With Go 1.17+, the standard `go build` / `go test` commands will fail because there is no `go.mod` file.

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

## Build (Go <= 1.16 only)
```bash
go mod download
go test -c -o raft_test ./...
```
