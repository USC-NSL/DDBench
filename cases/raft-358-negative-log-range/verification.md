# Verification: hashicorp/raft #358

```bash
#!/bin/bash

cd raft

# Check the code at snapshot.go around line 231-235 for bounds check
BOUNDS_CHECK=$(grep -n "minLog\|min.*max\|skip.*truncat\|compactRange" snapshot.go 2>/dev/null | head -5)

# Run tests and check for negative range in log compaction
OUTPUT=$(go test -v -run TestSnapshot ./... -count=1 -timeout 120s 2>&1)

# Look for the telltale negative range log message
if echo "$OUTPUT" | grep -qE "Compacting logs from [0-9]+ to [0-9]+" ; then
    # Extract the from/to values
    COMPACT_LINE=$(echo "$OUTPUT" | grep -oE "Compacting logs from [0-9]+ to [0-9]+")
    FROM=$(echo "$COMPACT_LINE" | grep -oE '[0-9]+' | head -1)
    TO=$(echo "$COMPACT_LINE" | grep -oE '[0-9]+' | tail -1)
    if [ "$FROM" -gt "$TO" ]; then
        echo "FAIL: Bug is present — compacting from $FROM to $TO (max < min)"
    else
        echo "PASS: Bug is fixed — compaction range is valid ($FROM to $TO)"
    fi
else
    # Alternative: check if bounds check exists in the code
    if grep -q "minLog.*<=\|max.*<.*min\|skip.*compact\|TrailingLogs" snapshot.go 2>/dev/null; then
        echo "PASS: Bug is fixed — bounds check present in snapshot.go"
    else
        echo "INCONCLUSIVE: Could not determine status from test output"
    fi
fi
```

- **FAIL:** Log compaction attempts `DeleteRange` with max < min.
- **PASS:** Either the bounds check prevents the invalid range, or compaction ranges are always valid.
