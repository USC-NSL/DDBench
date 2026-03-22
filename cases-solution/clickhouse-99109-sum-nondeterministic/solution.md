# Solution: ClickHouse #99109

## Fix
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/99109

## Root cause

Floating-point addition is not associative. When `max_threads > 1`, ClickHouse partitions the data across threads, each thread computes a partial sum, and then the partial sums are merged. Different thread counts produce different partitioning, leading to different summation orders, which yields slightly different results due to floating-point rounding.

For example, `(a + b) + c` does not necessarily equal `a + (b + c)` for Float64 values. With `max_threads = 1`, all values are summed sequentially in insertion order. With `max_threads = 8`, values are partitioned into 8 groups, summed independently, and then the 8 partial sums are added together.

## Fix description

This is fundamentally a floating-point arithmetic limitation. Possible mitigations:

1. **Use compensated (Kahan) summation:** ClickHouse could implement Kahan summation or pairwise summation in the `sum()` aggregate function for Float64, which would greatly reduce (but not eliminate) the sensitivity to summation order.

2. **Use `sumKahan()` aggregate function** (if available) instead of `sum()`:
   ```sql
   SELECT key, sumKahan(value) FROM float_sum_test GROUP BY key;
   ```

3. **Force single-threaded execution** for reproducibility:
   ```sql
   SET max_threads = 1;
   ```

4. **Use Decimal types** instead of Float64 for exact arithmetic:
   ```sql
   SELECT key, sum(toDecimal64(value, 18)) FROM float_sum_test GROUP BY key;
   ```

5. **Round results** to an acceptable precision:
   ```sql
   SELECT key, round(sum(value), 10) FROM float_sum_test GROUP BY key;
   ```

## How to verify
After applying compensated summation or using `sumKahan()`, verify that the same query with different `max_threads` values produces identical results.
