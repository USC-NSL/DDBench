# Symptom

When a Java ZooKeeper client (Apache Curator with CuratorCache) connects to ClickHouse Keeper and sends an `addWatch` request, the Keeper disconnects the client.

## Observable behavior
- Java clients using CuratorCache get disconnected shortly after connecting.
- The client logs show repeated connection/disconnection cycles.
- Standard watches (set via `getData`, `exists`, `getChildren`) work correctly — only `addWatch` causes the disconnect.
- Native ClickHouse ZooKeeper client (which does not use `addWatch`) works fine.
- Apache ZooKeeper server handles the same Java client without issues.
