# Setup: NATS Server #7817

## Project
- **Repository:** https://github.com/nats-io/nats-server
- **Language:** Go
- **Issue:** https://github.com/nats-io/nats-server/issues/7817

## Clone and checkout buggy version
```bash
git clone https://github.com/nats-io/nats-server.git
cd nats-server
git checkout v2.12.3
```

## Build
```bash
go build -o nats-server .
```

## Dependencies
- Go 1.22+
- `nats` CLI tool (`go install github.com/nats-io/natscli/nats@latest`)
