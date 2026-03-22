# Solution: Redpanda #15118

## Fix
- **PR:** https://github.com/redpanda-data/redpanda/pull/15414
- **Commit:** `6cd0e7054aada957dc28b6826b6f4f77ea6eb40e`

## Root cause
When a Kafka client connection fails authentication (i.e., `do_authenticate` returns an error), the connection handler exits early without properly stopping the broker object associated with that connection. The broker has in-flight futures (e.g., for reading from the connection socket) that reference the broker's internal state. When the handler exits without stopping the broker:

1. The broker object is destroyed (goes out of scope or is freed)
2. The in-flight futures eventually complete (or fail)
3. They reference destroyed memory, triggering Seastar's exceptional future assertion

This is a classic resource lifetime issue in asynchronous code: the owner of the resource (broker) is destroyed while background tasks still hold references to it.

## Fix description
Stop the broker when `do_authenticate` fails, before exiting the connection handler. This ensures all in-flight futures associated with the broker are properly cancelled and completed before the broker is destroyed.

The fix is in the Kafka connection handler code, specifically in the error path of `do_authenticate`. Before returning/exiting on auth failure, call `broker.stop()` (or equivalent) and wait for it to complete.

Key file: `src/v/kafka/server/connection_context.cc` (or similar — the file handling Kafka connection lifecycle).

## How to apply
```bash
git checkout 6cd0e7054aada957dc28b6826b6f4f77ea6eb40e
git submodule update --init --recursive
# Build following setup.md instructions
```
