# Symptom

A data race is detected when running the embedded etcd integration tests with the Go race detector enabled.

## Observable behavior
- The test `TestEmbedEtcd` in `tests/integration/embed/` fails intermittently with a `WARNING: DATA RACE` message when run with `-race`.
- The race involves concurrent access to a shared field during shutdown.
