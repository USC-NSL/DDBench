# Symptom: Redpanda #25769

## Description

The Kafka `ListOffsets` API returns incorrect offsets when querying by timestamp on topics that contain compressed record batches. The API is supposed to return the offset of the first record with a timestamp greater than or equal to the requested timestamp, but it returns wrong offsets for compressed data.

## Observable behavior

- Producing records with compression enabled (gzip, snappy, lz4, or zstd) and then calling `ListOffsets` with a specific timestamp returns an offset that does not correspond to the first record at or after that timestamp.
- The same operation with uncompressed records returns the correct offset.
- The incorrect offset may point to the beginning of a batch rather than the specific record within the batch that matches the timestamp.
- This affects any consumer that uses timestamp-based seeking (e.g., `consumer.offsetsForTimes()` in the Java Kafka client).
- The `ListOffsets` response itself does not indicate an error — it returns a valid-looking offset, but the offset is wrong.

## Impact

Applications relying on timestamp-based offset lookup (common for replaying events from a specific point in time, or for consumer lag monitoring based on timestamps) get incorrect results when data is compressed. This can cause consumers to skip records or re-process records they have already seen.
