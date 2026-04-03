# Symptom

Using the `DUMP` command on a key that holds a probabilistic data structure causes a fatal crash.

## Observable behavior
- Any operation that reads or transfers the key -- such as `DUMP`, `BGSAVE`, or replication -- crashes the process.
- The error message references an unknown encoding for an unrecognized type.
