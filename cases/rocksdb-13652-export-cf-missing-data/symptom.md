# Symptom: RocksDB #13652

`Checkpoint::ExportColumnFamily` occasionally misses committed data. After exporting a column family and importing it into another database, some keys that were successfully committed (and confirmed via `Get()` on the source database) are missing from the exported data.

The missing data is specifically from the memtable — data that has been committed but not yet flushed to SST files. The export operation has a race condition where committed data in the active memtable may not be included in the export.

The issue is intermittent:
- Data that has been flushed to SST files is always correctly exported
- Data in the memtable at the time of export is sometimes missing
- The probability of missing data increases under concurrent write load

This is a data integrity issue: the export claims to succeed (returns OK status) but produces an incomplete snapshot of the column family.
