# Setup: CockroachDB #166122

## Project
- **Repository:** https://github.com/cockroachdb/cockroach
- **Language:** Go
- **Issue:** https://github.com/cockroachdb/cockroach/issues/166122

## Clone and checkout buggy version
```bash
git clone https://github.com/cockroachdb/cockroach.git
cd cockroach
git checkout 8c90d1ad0b59f18926d3b77f9f653d942f755e36~1
git submodule update --init --recursive
```

## Build
```bash
make build
```

This requires Go 1.22+, Bazel, and various build dependencies. See CockroachDB's build documentation for full prerequisites.

## Alternative: Use a pre-built binary

Download a CockroachDB release that contains the bug (before the fix). The bug exists in versions around v24.x before the fix was backported.

```bash
# Example: download a vulnerable version
curl -L https://binaries.cockroachdb.com/cockroach-v24.3.0.linux-amd64.tgz | tar xz
cd cockroach-v24.3.0.linux-amd64
```

## Deploy: Single-node or 3-node cluster

Single node for reproduction:
```bash
cockroach start-single-node --insecure --store=/tmp/crdb-data --listen-addr=localhost:26257
```

Or 3-node cluster:
```bash
cockroach start --insecure --store=/tmp/crdb1 --listen-addr=localhost:26257 --join=localhost:26257,localhost:26258,localhost:26259
cockroach start --insecure --store=/tmp/crdb2 --listen-addr=localhost:26258 --join=localhost:26257,localhost:26258,localhost:26259
cockroach start --insecure --store=/tmp/crdb3 --listen-addr=localhost:26259 --join=localhost:26257,localhost:26258,localhost:26259
cockroach init --insecure --host=localhost:26257
```
