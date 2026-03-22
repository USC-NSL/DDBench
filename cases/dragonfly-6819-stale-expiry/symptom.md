# Symptom: Dragonfly #6819

When a key is first set with an expiry (e.g., `SET key val EX 60`) and then overwritten without an expiry (e.g., `SET key val2`), the stale expiry entry from the first SET is not cleared. When the original expiry time arrives, the expiry cycle attempts to expire the key, leading to a crash at `db_slice.cc:1163`.

The crash occurs because the internal expiry data structure still references the key's original TTL even though the key has been overwritten with no expiry.
