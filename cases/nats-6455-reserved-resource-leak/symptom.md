# Symptom

A NATS JetStream server with clustered R3 streams progressively reports growing reserved disk usage until it claims the disk is full, even though no new streams are being created.

Server logs show repeated errors about sequence mismatches followed by stream state resets in a tight loop.

After repeated reset cycles visible in the logs, the server eventually refuses to create new streams with resource-exceeded errors, even though the actual disk has ample free space.

Setting the affected stream to R1, restarting the servers, and returning it to R3 temporarily resolves the issue.

## Observable indicators

- The server's reported reserved storage grows over time without any new streams being created
- Server eventually refuses new stream creation with resource-exceeded errors
- The problem correlates with the frequency of stream state reset log entries
