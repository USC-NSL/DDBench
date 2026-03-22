# Setup: ScyllaDB — Segfault on raft_topology/reload During Startup

## Project
- **Repository:** https://github.com/scylladb/scylladb
- **Language:** C++
- **Issue:** https://github.com/scylladb/scylladb/issues/27130
- **Fix PR:** https://github.com/scylladb/scylladb/pull/27410

## Option A: Docker (may not reproduce)

**Warning:** The Docker image `6.2.2` may not reliably reproduce this bug. The segfault requires hitting a narrow timing window during startup where the REST API is available but the storage service is not yet initialized. The Docker entrypoint's startup sequence may differ enough to prevent the race from triggering. Building from source (Option B) is more reliable.

```bash
docker pull scylladb/scylla:6.2.2
```

Start a single ScyllaDB node:
```bash
docker run -d --name scylla \
  -p 9042:9042 \
  -p 10000:10000 \
  scylladb/scylla:6.2.2 \
  --smp 2 \
  --memory 1G \
  --overprovisioned
```

Wait for ScyllaDB to start:
```bash
docker exec scylla nodetool status
```

The REST API is available on port 10000.

## Option B: Build from source

```bash
git clone https://github.com/scylladb/scylladb.git
cd scylladb
# Checkout parent of fix commit
git checkout e54abde3e851bbba8aca0a06085f234ea1f4b74a~1
git submodule update --init --recursive

# Build (requires specific toolchain — see HACKING.md in repo)
./configure.py --mode=dev
ninja -C build/dev scylla
```

## Prerequisites
- `curl` for REST API calls
- `cqlsh` or a CQL driver for basic connectivity verification
