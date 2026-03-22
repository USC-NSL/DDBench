# Verification: Dragonfly #6825

## Test procedure
1. Start Dragonfly in cluster mode (see reproduce.md for full setup).
2. Replay the crash archive.
3. Check process status:
   ```bash
   if kill -0 $PID 2>/dev/null; then
       echo "PASS: Bug is fixed — process survived overflow input"
   else
       echo "FAIL: Bug is present — process crashed"
   fi
   ```

## Verdict
- **FAIL:** Process crashes with assertion failure on overflow input.
- **PASS:** Process returns an error response and stays alive.
