# Symptom

Calling MONITOR twice inside a MULTI/EXEC block causes `ChangeMonitor` to add the connection twice, triggering an assertion failure:
```
Check failed: cc_
```
The process crashes with SIGABRT.
