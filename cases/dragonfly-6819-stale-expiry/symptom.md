# Symptom

When a key is first set with an expiry (e.g., `SET key val EX 60`) and then overwritten without an expiry (e.g., `SET key val2`), the process crashes when the original expiry time arrives.

## Observable behavior
- The crash occurs after the original TTL duration has elapsed, not at the time of the overwrite.
- The process terminates with SIGABRT.
- The key that was overwritten without expiry should persist indefinitely, but the server crashes instead.
