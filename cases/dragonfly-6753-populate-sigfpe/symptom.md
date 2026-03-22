# Symptom: Dragonfly #6753

Running the `DEBUG POPULATE` command with a `val_size` of 0 causes the
Dragonfly process to receive a SIGFPE (floating-point exception / division
by zero) signal and crash immediately.

## Observable behavior
- Process receives SIGFPE and terminates.
- Stack trace points to `DoPopulateBatch()` in `DebugCmd`.
- The crash is instant upon command execution.
