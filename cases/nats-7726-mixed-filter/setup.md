# Setup: NATS Server #7726

## Project
- **Repository:** https://github.com/nats-io/nats-server
- **Language:** Go
- **Issue:** https://github.com/nats-io/nats-server/issues/7726

## Clone and checkout buggy version
```bash
git clone https://github.com/nats-io/nats-server.git
cd nats-server
git checkout 6aded805ec9625b20ee50ded3b63135d5fe3d0a8~1
```

## Build
```bash
go build -o nats-server .
```

## Dependencies
- Go 1.22+
- `nats` CLI tool (`go install github.com/nats-io/natscli/nats@latest`)
