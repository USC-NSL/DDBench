# Symptom

## Description

Calling the REST API endpoint `POST /storage_service/raft_topology/reload` during or shortly after ScyllaDB node startup causes the process to crash with a segfault (SIGSEGV). The crash occurs because the REST API is set up and accepting requests before the storage service is fully initialized.

## Observable behavior

- During ScyllaDB startup, the REST API becomes available on port 10000 before the storage service has finished initializing.
- A `POST` request to `/storage_service/raft_topology/reload` during this window crashes the ScyllaDB process.
- The crash log shows a null pointer dereference (SIGSEGV, signal 11).
- The stack trace points to the storage service handler for the raft_topology/reload endpoint trying to access an uninitialized member.
- Normal startup (without the API call) succeeds without issues.
- After full startup is complete, the same API call works correctly.

## Impact

Any monitoring or orchestration system that polls the REST API during startup can trigger this crash. In Kubernetes environments where liveness probes or init containers hit the REST API, this can cause a crash loop preventing the node from ever fully starting.
