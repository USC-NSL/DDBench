# Symptom

Running `FT.SEARCH` on a search index crashes when documents contain certain VECTOR or NUMERIC field values.

## Observable behavior
- The Dragonfly process terminates with a segmentation fault.
- The crash is triggered by querying an index that contains documents with certain field values I think.

