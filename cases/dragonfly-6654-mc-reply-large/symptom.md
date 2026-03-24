# Symptom

When using the memcached protocol with meta get commands, retrieving a sufficiently large value causes the process to crash with SIGABRT.

## Observable behavior
- The crash only occurs with the memcached protocol, not with the Redis protocol.
- Small values are served correctly; only large values trigger the crash.
