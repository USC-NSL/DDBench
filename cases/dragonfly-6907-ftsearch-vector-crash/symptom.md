# Symptom: Dragonfly #6907

Running FT.SEARCH on a search index when documents have wrong-sized VECTOR or NUMERIC field values causes a crash at `doc_accessors.cc:60` due to out-of-bounds memory access.
