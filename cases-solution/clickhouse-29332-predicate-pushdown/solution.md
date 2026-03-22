# Solution: ClickHouse #29332

## Fix
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/29332

## Root cause

The `enable_optimize_predicate_expression` optimizer pass pushes WHERE predicates down into subqueries to improve performance. However, it does not check whether the predicate itself contains a reference to a Distributed table (via an IN subquery). When a predicate like `WHERE id IN (SELECT id FROM distributed_table)` is pushed down into the inner query of another Distributed table, it creates a double-distributed subquery pattern.

With `distributed_product_mode = 'deny'`, this is explicitly forbidden and raises an error. With other modes, the pushdown changes the query semantics by altering which shard the IN subquery runs on.

The optimizer's predicate pushdown logic in `PredicateExpressionsOptimizer` does not inspect the predicate for Distributed table references before deciding to push it down.

## Fix description

The fix modifies the predicate pushdown logic to skip predicates that contain subqueries referencing Distributed tables. Before pushing a predicate down, the optimizer now checks whether the predicate's AST subtree contains any table references that resolve to Distributed engine tables. If so, the predicate is left in place at the outer query level.

## Files changed

- **`src/Interpreters/PredicateExpressionsOptimizer.cpp`** (or equivalent predicate pushdown implementation) — Added a check to detect distributed table references in predicate subexpressions. When a predicate contains an IN/JOIN subquery that references a Distributed table, it is excluded from pushdown.

## Workaround (without code fix)

Disable predicate pushdown for affected queries:
```sql
SET enable_optimize_predicate_expression = 0;
```

Or use `distributed_product_mode = 'global'` instead of `'deny'`:
```sql
SET distributed_product_mode = 'global';
```
