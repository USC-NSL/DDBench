# Setup: Consul #12295

## Project
- **Repository:** https://github.com/hashicorp/consul
- **Language:** Go
- **Issue:** https://github.com/hashicorp/consul/issues/12295
- **Fix PR:** https://github.com/hashicorp/consul/pull/12565

## Clone and checkout buggy version

```bash
git clone https://github.com/hashicorp/consul.git
cd consul
git checkout 24245edfcc9d56eb1033908c607f56b19f7d1360~1
```

## Build

The reproduction test runs against `./lib/routine/` and does not require the full `consul` binary. Build is optional:

```bash
go build -o bin/consul ./... 2>/dev/null || true
```

## Notes

- Go 1.17+ required (the codebase uses generics-era dependency patterns).
- No external services required; the bug is exercised via a pure Go unit test.
- Same-project cases (`consul-8377`, `consul-9772`) share the same Docker image.
