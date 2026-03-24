# Symptom

Running the `DEBUG POPULATE` command with a `val_size` of 0 causes the
Dragonfly process to crash immediately.

## Observable behavior
- Process receives SIGFPE (floating-point exception) and terminates.
- The crash is instant upon command execution.
