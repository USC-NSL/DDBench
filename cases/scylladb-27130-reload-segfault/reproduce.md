# Reproduce: ScyllaDB #27130

## Prerequisites
- Docker installed (see setup.md)
- `curl` available

## Step 1: Prepare the crash-trigger script

Create a script that rapidly calls the REST API endpoint during startup:
```bash
cat > trigger.sh <<'SCRIPT'
#!/bin/bash
# Continuously hit the raft_topology/reload endpoint
while true; do
    curl -s -X POST http://localhost:10000/storage_service/raft_topology/reload 2>/dev/null
    sleep 0.1
done
SCRIPT
chmod +x trigger.sh
```

## Step 2: Start the trigger script in background

```bash
./trigger.sh &
TRIGGER_PID=$!
```

## Step 3: Start ScyllaDB

```bash
docker rm -f scylla 2>/dev/null
docker run --name scylla --network host \
  scylladb/scylla:6.2.2 \
  --smp 2 \
  --memory 1G \
  --overprovisioned
```

## Step 4: Observe the crash

The ScyllaDB container will exit shortly after starting, before fully initializing. The container exits with a non-zero code due to SIGSEGV.

```bash
# Check exit status
docker inspect scylla --format='{{.State.ExitCode}}'
# Expected: 139 (128 + 11 for SIGSEGV)
```

Check logs for the segfault:
```bash
docker logs scylla 2>&1 | grep -i "segfault\|signal\|SIGSEGV" | tail -5
```

## Step 5: Stop the trigger script

```bash
kill $TRIGGER_PID 2>/dev/null
```

## Expected result (bug present)

ScyllaDB crashes with SIGSEGV during startup when the REST API endpoint is called before the storage service is ready.

## Expected result (bug absent)

ScyllaDB either:
1. Returns an error response (e.g., HTTP 503 Service Unavailable) to the premature API call, or
2. Does not expose the REST endpoint until the storage service is fully initialized.

The node completes startup successfully regardless of the API calls.

## Notes
- The timing window is during startup, after the REST API is bound but before the storage service is fully initialized.
- Running the trigger script continuously increases the likelihood of hitting the exact window.
- The crash may not happen on the very first attempt if startup is very fast; multiple restart cycles may be needed.
