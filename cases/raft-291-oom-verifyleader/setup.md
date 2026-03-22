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

## Build
```bash
go mod download
go test -c -o raft_test ./...
```
