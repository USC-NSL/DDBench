# Symptom

Using the `DUMP` command on a key that holds a CMS (Count-Min Sketch) data structure causes a fatal crash:
```
FATAL: Unknown encoding 0 for type 17
```

The crash occurs in `rdb_save.cc:206` because the `RdbObjectType` serialization function does not handle the CMS type (type 17). Any operation that triggers RDB serialization of a CMS key (DUMP, BGSAVE, replication) will crash.
