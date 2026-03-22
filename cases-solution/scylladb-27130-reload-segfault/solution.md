# Solution: ScyllaDB #27130

## Fix
- **Issue:** https://github.com/scylladb/scylladb/issues/27130
- **Fix PR:** https://github.com/scylladb/scylladb/pull/27410
- **Fix commit:** `e54abde3e851bbba8aca0a06085f234ea1f4b74a`

## Root cause

During ScyllaDB startup, the REST API HTTP server is set up and begins accepting connections before the storage service has finished its initialization. The `storage_service` REST handler for the `/storage_service/raft_topology/reload` endpoint dereferences a pointer to the storage service object. During the early startup phase, this object is either not yet constructed or not fully initialized, leading to a null pointer dereference (segfault).

The startup sequence is roughly:
1. HTTP server starts and binds to port 10000.
2. REST API routes are registered, including storage_service endpoints.
3. Storage service initialization begins (Raft topology setup, schema loading, etc.).
4. Storage service initialization completes.

The vulnerability window is between steps 2 and 4, during which the REST endpoints are reachable but the backing service is not ready.

## Fix description

The fix delays the setup of the `storage_service` REST API routes until after the storage service has been fully initialized. This ensures that the endpoints are not reachable during the initialization window.

Specifically:
- The REST API route registration for `storage_service` endpoints is moved from the early startup phase to after `storage_service::init()` completes.
- This guarantees that by the time any request reaches the handler, the storage service object is fully constructed and initialized.

## Files changed

- **`api/storage_service.cc`** (or equivalent REST API registration file) — Moved the registration of storage_service REST handlers to occur after the storage service is fully initialized.
- **`main.cc`** (or the startup orchestration file) — Changed the ordering of REST API setup to ensure storage_service routes are registered only after `storage_service` initialization is complete.

## How to apply the fix
```bash
cd scylladb
git checkout e54abde3e851bbba8aca0a06085f234ea1f4b74a
git submodule update --init --recursive
./configure.py --mode=dev
ninja -C build/dev scylla
```
