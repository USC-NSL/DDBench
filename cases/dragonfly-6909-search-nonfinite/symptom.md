# Symptom

Two related crashes in the search subsystem:

1. Indexing a document with a non-finite NUMERIC value (NaN, Inf, -Inf) causes a crash.

2. Running `FT.SEARCH` queries can crash with a segmentation fault when processing certain search results.

## Observable behavior
- Both crashes are triggered during `FT.SEARCH` or related search indexing operations.
- The process terminates with SIGABRT or SIGSEGV.
