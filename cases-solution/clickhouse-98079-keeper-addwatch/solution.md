# Solution: ClickHouse #98079

## Fix
- **Issue:** https://github.com/ClickHouse/ClickHouse/issues/98079
- **Fix PR:** https://github.com/ClickHouse/ClickHouse/pull/98499
- **Fix commit:** `3515972fbc064f7b62c963c8e25969053a6a38c2`

## Root cause

ClickHouse Keeper implements a subset of the ZooKeeper protocol to act as a drop-in replacement. However, the `addWatch` request type (opcode), introduced in ZooKeeper 3.6 for persistent and recursive watches, was not implemented in Keeper's protocol handler. When a Java ZooKeeper client (e.g., Apache Curator with CuratorCache) sends an `addWatch` request, Keeper's request dispatcher does not recognize the opcode and treats it as a protocol error, causing it to disconnect the client.

The `addWatch` API is used by CuratorCache (the successor to the deprecated PathChildrenCache and TreeCache) to set persistent watches that survive triggered events without needing to be re-registered.

## Fix description

The fix adds proper handling of the `addWatch` request in Keeper's protocol implementation. This includes:

1. Recognizing the `addWatch` opcode in the request dispatcher.
2. Implementing the persistent/recursive watch registration logic.
3. Ensuring watch events are properly delivered to clients that registered via `addWatch`.
4. Supporting both `PERSISTENT` and `PERSISTENT_RECURSIVE` watch modes as defined in the ZooKeeper protocol.

## Files changed

- **`src/Coordination/KeeperStorage.cpp`** — Added handling for the `addWatch` request type, implementing persistent watch registration in the watch manager.
- **`src/Coordination/KeeperServer.cpp`** (or protocol handler) — Added the `addWatch` opcode to the request dispatcher so it is recognized as a valid request.
- **`src/Coordination/ZooKeeperDataReader.cpp`** (or response handler) — Added proper response serialization for `addWatch` responses.

## How to apply the fix
```bash
cd ClickHouse
git checkout 3515972fbc064f7b62c963c8e25969053a6a38c2
git submodule update --init --recursive
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Debug
ninja clickhouse-keeper
```
