# Solution: ClickHouse #75699

## Fix
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/75699
- **Fix commit:** `9334d08f0c942a7402e88f3929f3252eb032722d`

## Root cause

The `IColumn::forEachSubcolumn` method iterates over subcolumns to perform operations like cloning or modifying column data. When a Merge table wraps a Distributed table and a JOIN is performed, the query pipeline needs to transform columns from the Distributed source. During this transformation, `forEachSubcolumn` is called, but the column source node reference becomes invalid because there was no mutable version of the callback — the const version was being used where mutation was needed, leaving source node pointers in an inconsistent state.

Specifically, after the `forEachSubcolumn` call modifies the column structure, the source node stored in the column metadata points to a stale or invalid location, leading to the LOGICAL_ERROR when the JOIN executor tries to read from it.

## Fix description

The fix implicitly implements a mutable version of `IColumn::forEachSubcolumn`. This ensures that when columns are being modified (e.g., during JOIN processing on Merge-over-Distributed tables), the mutable callback properly updates source node references, keeping them valid throughout the transformation.

## Files changed

The primary change is in the ClickHouse column infrastructure:

- **`src/Columns/IColumn.h`** — Updated `forEachSubcolumn` interface to support mutable callbacks that properly handle column source node references.
- **`src/Columns/IColumn.cpp`** (and/or related column implementation files) — Implemented the mutable version of `forEachSubcolumn` so that column source nodes remain valid after subcolumn iteration and modification.

## How to apply the fix
```bash
cd ClickHouse
git checkout 9334d08f0c942a7402e88f3929f3252eb032722d
git submodule update --init --recursive
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
ninja clickhouse-server clickhouse-client
```
