# Setup: NATS #7852

## Project
- **Repository:** https://github.com/nats-io/nats-server
- **Language:** Go
- **Issue:** https://github.com/nats-io/nats-server/issues/7852
- **Fix PR:** https://github.com/nats-io/nats-server/pull/7856

## Clone and checkout buggy version
```bash
git clone https://github.com/nats-io/nats-server.git
cd nats-server
# Checkout the commit just before the fix
git checkout 66e9bbc7f8684dd1b31c54ef686924e0841f9846~1
```

## Build
```bash
# Requires Go 1.22+
go build -o nats-server .
```

## Dependencies for benchmarking
```bash
# Install nats CLI tool
go install github.com/nats-io/natscli/nats@latest

# Install nats Go client for custom benchmarks
go get github.com/nats-io/nats.go@latest
```

## Server setup
Start a NATS server with JetStream enabled:
```bash
# Create config file
cat > /tmp/nats-bench.conf <<EOF
listen: 127.0.0.1:4222
jetstream {
  store_dir: /tmp/nats-bench-data
  max_mem: 1G
  max_file: 10G
}
EOF

./nats-server -c /tmp/nats-bench.conf &
```
