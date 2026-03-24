# Symptom

Sending `EVALSHA "" 0` (empty SHA) to Dragonfly causes an assertion failure:
```
Check failed: !eval_args.sha.empty()
```
The process crashes with SIGABRT.
