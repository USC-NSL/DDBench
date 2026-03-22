# Symptom: ClickHouse #98079

## Description

When a Java ZooKeeper client (specifically Apache Curator with CuratorCache) connects to ClickHouse Keeper and sends an `addWatch` request, the Keeper immediately disconnects the client. This breaks CuratorCache functionality, which relies on persistent/recursive watches via the `addWatch` API.

## Observable behavior

- Java ZooKeeper clients using CuratorCache connect to ClickHouse Keeper successfully but get disconnected shortly after.
- The Curator client logs show repeated connection/disconnection cycles.
- Keeper logs may show errors about unrecognized or improperly handled request types.
- The `addWatch` opcode (from ZooKeeper 3.6+) is not properly handled by the Keeper protocol implementation.
- Standard watches (set via `getData`, `exists`, `getChildren`) work correctly — only `addWatch` (persistent/recursive watches) causes the disconnect.
- Native ClickHouse ZooKeeper client (which does not use `addWatch`) works fine.
- Apache ZooKeeper server handles the same Java client without issues.

## Impact

Any Java application using Apache Curator's CuratorCache (a common pattern for service discovery and configuration management) cannot use ClickHouse Keeper as a ZooKeeper replacement. This limits Keeper's compatibility with the ZooKeeper ecosystem.
