# Symptom

When a large number of keys (500k+) with TTL expire simultaneously, Dragonfly becomes completely unresponsive:

1. CPU usage spikes to 100% on one or more threads.
2. `PING` commands time out (no response for 5+ seconds).
3. All client connections appear hung during the expiry cycle.
4. The server eventually recovers after the expiry sweep completes, but during the sweep, the instance is effectively down.

This happens because the periodic key expiration routine traverses all expired entries in a tight loop without yielding back to the event loop, blocking all other operations including heartbeat and client commands.
