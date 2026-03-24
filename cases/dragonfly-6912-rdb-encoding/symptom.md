# Symptom

Using the `DUMP` command on a key that holds a CMS (Count-Min Sketch) data structure causes a fatal crash:
```
FATAL: Unknown encoding 0 for type 17
```

## Observable behavior
- Any operation that triggers RDB serialization of a CMS key (DUMP, BGSAVE, replication) crashes the process.
- The error message references an unknown encoding for an unrecognized type.
