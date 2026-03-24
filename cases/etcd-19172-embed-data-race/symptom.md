# Symptom

A data race is detected between `Etcd.Close()` and `Etcd.errHandler()` when running the embedded etcd integration tests with the race detector enabled. The race occurs on an unsynchronized field access: one goroutine writes the field in `Close()` while another goroutine reads it in `errHandler()`.

The test `TestEmbedEtcd` in `tests/integration/embed/` fails intermittently with a `WARNING: DATA RACE` message when run with `-race`.
