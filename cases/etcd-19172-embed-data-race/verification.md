# Verification: etcd #19172

```bash
#!/bin/bash

RACE_DETECTED=0
for i in $(seq 1 20); do
  OUTPUT=$(go test -race -run TestEmbedEtcd ./tests/integration/embed/ -count=1 2>&1)
  if echo "$OUTPUT" | grep -q "DATA RACE"; then
    RACE_DETECTED=1
    break
  fi
done

if [ "$RACE_DETECTED" -eq 1 ]; then
    echo "FAIL: Bug is present — data race detected between Close() and errHandler()"
else
    echo "PASS: Bug is fixed — no data race detected in 20 runs"
fi
```

- **FAIL:** `WARNING: DATA RACE` appears in the test output.
- **PASS:** All 20 runs complete without any race warnings.
