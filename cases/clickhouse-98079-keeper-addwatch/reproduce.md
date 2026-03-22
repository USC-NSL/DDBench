# Reproduce: ClickHouse #98079

## Prerequisites
- ClickHouse Keeper running on port 2181 (see setup.md)
- Java 11+ installed
- Maven or Gradle for building the test client

## Step 1: Create a Java test client

Create a file `TestAddWatch.java`:
```java
import org.apache.curator.framework.CuratorFramework;
import org.apache.curator.framework.CuratorFrameworkFactory;
import org.apache.curator.framework.recipes.cache.CuratorCache;
import org.apache.curator.retry.ExponentialBackoffRetry;

public class TestAddWatch {
    public static void main(String[] args) throws Exception {
        CuratorFramework client = CuratorFrameworkFactory.newClient(
            "localhost:2181",
            new ExponentialBackoffRetry(1000, 3)
        );
        client.start();
        client.blockUntilConnected();
        System.out.println("Connected to Keeper");

        // Create a test path
        if (client.checkExists().forPath("/test-addwatch") == null) {
            client.create().forPath("/test-addwatch", "data".getBytes());
        }

        // CuratorCache uses addWatch internally
        CuratorCache cache = CuratorCache.build(client, "/test-addwatch");
        cache.start();
        System.out.println("CuratorCache started (uses addWatch)");

        // Wait and observe — Keeper will disconnect the client
        Thread.sleep(10000);

        System.out.println("If you see this, the client stayed connected (bug fixed)");
        cache.close();
        client.close();
    }
}
```

## Step 2: Create `pom.xml`

```xml
<project>
    <modelVersion>4.0.0</modelVersion>
    <groupId>test</groupId>
    <artifactId>test-addwatch</artifactId>
    <version>1.0</version>
    <dependencies>
        <dependency>
            <groupId>org.apache.curator</groupId>
            <artifactId>curator-recipes</artifactId>
            <version>5.5.0</version>
        </dependency>
    </dependencies>
</project>
```

## Step 3: Build and run

```bash
mvn compile exec:java -Dexec.mainClass="TestAddWatch"
```

## Expected result (bug present)

The client connects but gets disconnected when CuratorCache calls `addWatch`. The output shows:
```
Connected to Keeper
CuratorCache started (uses addWatch)
```
Followed by Curator's retry/reconnect logs indicating the connection was lost. The "If you see this" message never appears.

## Expected result (bug absent)

The client connects, CuratorCache starts and remains active for the full 10 seconds:
```
Connected to Keeper
CuratorCache started (uses addWatch)
If you see this, the client stayed connected (bug fixed)
```

## Alternative: Quick test with zkCli

```bash
# Using Apache ZooKeeper's CLI (3.6+)
./apache-zookeeper-3.8.4-bin/bin/zkCli.sh -server localhost:2181
# In the CLI:
addWatch /test-path
# Bug present: connection drops
# Bug absent: watch registered successfully
```
