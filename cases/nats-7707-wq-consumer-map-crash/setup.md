# Setup: NATS #7707

## Project
- **Repository:** https://github.com/nats-io/nats-server
- **Language:** Go
- **Issue:** https://github.com/nats-io/nats-server/issues/7707

## Clone and checkout buggy version
```bash
git clone https://github.com/nats-io/nats-server.git
cd nats-server
git checkout 3a90a2d087b792c10d4cbed27f3cc5ef0fb77571~1
```

## Build
```bash
go build -o nats-server .
```

## Configuration

No special configuration is required. The reproduction uses a single-node server with JetStream enabled and in-memory storage. The test creates its own embedded server instance.
