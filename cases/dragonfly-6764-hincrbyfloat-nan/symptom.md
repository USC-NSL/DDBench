# Symptom

Running `HINCRBYFLOAT` with `inf` as the increment on a hash field, then performing subsequent operations on that hash, causes the Dragonfly process to crash.

## Observable behavior
- The `HINCRBYFLOAT` command itself succeeds (returns `inf`).
- Subsequent operations on the hash (e.g., `HGETALL`, `HSET`) crash the process with SIGABRT.
