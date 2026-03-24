# Symptom

After a node restart, staging SSTables (SSTables that are pending view update processing) are not discovered by the view update generator. This causes a permanent inconsistency between the base table and its materialized views.

The problem is a regression caused by reordering initialization: the view update generator is initialized before SSTables are loaded from disk. When the generator starts, it scans for staging SSTables, but none exist yet because SSTable loading has not happened. After SSTables are loaded, the generator does not re-scan, so staging SSTables are permanently ignored.

Symptoms after restart:
1. Materialized views are missing data that was in-flight during the previous shutdown
2. The inconsistency is permanent — no automatic repair occurs
3. `nodetool viewbuildstatus` may show the view as "built" even though it is missing data
4. Queries against the view return fewer rows than expected compared to the base table

This only affects cases where staging SSTables existed at shutdown time (e.g., due to a view update failure or a crash during view update processing).
