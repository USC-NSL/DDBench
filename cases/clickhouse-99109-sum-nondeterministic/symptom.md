# Symptom

Running `SELECT key, sum(value) FROM table GROUP BY key` on a table with Float64 values produces different results depending on the `max_threads` setting.

With `max_threads = 1`, the query returns one result. With `max_threads = 8`, the same query on the same data returns a slightly different sum. The difference is small (e.g., 14th-15th decimal digit), but it is non-zero and reproducible.

This means the same deterministic query on the same data produces non-deterministic results, which can cause issues for applications that depend on exact reproducibility of aggregation results.
