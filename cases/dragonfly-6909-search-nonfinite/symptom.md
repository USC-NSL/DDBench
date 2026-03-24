# Symptom

Two related crashes in the search subsystem:

1. Indexing a document with a non-finite NUMERIC value (NaN, Inf, -Inf) causes a crash. There is no validation that numeric values are finite before they are used in search index operations.

2. The `KeepTopKSorted` function in the search result scoring can access out-of-bounds memory when processing search results, leading to a segfault.

Both issues are triggered during `FT.SEARCH` or related search indexing operations.
