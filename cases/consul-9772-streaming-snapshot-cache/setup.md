# Setup: Consul #9772

## Project
- **Repository:** https://github.com/hashicorp/consul
- **Language:** Go
- **PR:** https://github.com/hashicorp/consul/pull/9772

## Clone and checkout buggy version
```bash
git clone https://github.com/hashicorp/consul.git
cd consul
git checkout 363d738fd2ee1ee25ad872a63894cffa8faf9df2~1
```

## Build
```bash
go build -o bin/consul ./... 2>/dev/null || true
```

Note: A full binary build is not strictly required for this case. The bug is reproduced via a Go unit test in the `agent/consul/stream/` package, which can be compiled and run directly.

## Verify
```bash
cd agent/consul/stream
go test -run TestEventPublisher_SubscribeWithIndex0 -v -count=1 -timeout 30s ./...
```
