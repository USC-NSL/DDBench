# Symptom

When running Dragonfly in cluster mode, sending a `DFLYCLUSTER CONFIG` command
with values that cause integer overflow during parsing results in an assertion
failure and process crash.

## Observable behavior
- The Dragonfly process crashes with:
  ```
  Check failed: rb->RepliesRecorded() > replies_recorded_ (0 vs. 0) DFLYCLUSTER
  ```
- The crash occurs in `main_service.cc` in the `ReplyGuard` destructor.
- The process exits with SIGABRT.
