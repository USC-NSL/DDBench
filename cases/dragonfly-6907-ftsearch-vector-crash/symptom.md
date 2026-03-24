# Symptom

Running `FT.SEARCH` on a search index crashes when documents contain VECTOR or NUMERIC field values with unexpected sizes.

## Observable behavior
- The Dragonfly process terminates with a segmentation fault.
- The crash is triggered by querying an index where documents have field values that don't match the expected dimensions or type.
