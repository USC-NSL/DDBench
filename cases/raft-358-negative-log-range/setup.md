# Setup: hashicorp/raft #358

## Project
- **Repository:** https://github.com/hashicorp/raft
- **Language:** Go
- **Issue:** https://github.com/hashicorp/raft/issues/358

## Clone and checkout buggy version
```bash
git clone https://github.com/hashicorp/raft.git
cd raft
git checkout 7b09f38f739f486a692096c35236c7eef094e933~1
```

## Build
This is a Go library; no standalone binary to build. Tests can be run directly:
```bash
go test ./...
```

## Dependencies
- Go 1.21+
