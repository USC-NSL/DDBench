# Reproduce: ZooKeeper #4846

## Prerequisites

- Java 11 (JDK)
- Maven 3.8+
- Git

## Step 1: Clone and checkout

```bash
git clone https://github.com/apache/zookeeper.git
cd zookeeper
git checkout 8532163df198466913f26141c0278dc11dbf53ab~1
```

## Step 2: Build the project

```bash
mvn -pl zookeeper-server -am install -DskipTests -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip -q
```

## Step 3: Inject and run the regression test

The test injects a method into `DataTreeTest.java` that simulates the fuzzy snapshot ACL race: it creates a node, removes the ACL from the cache, then attempts to re-create the same node (which throws NodeExistsException but should defensively fix the ACL), and finally creates a child node under the parent.

```bash
cd zookeeper-server
mvn test -Dtest="DataTreeTest#testCreateNodeFixMissingACL" -DfailIfNoTests=false -q
```

## Expected result (bug present)

The test FAILS because creating the child node throws a `RuntimeException` -- the ACL reference for the parent node was removed from the cache during the simulated fuzzy snapshot race, and `createNode` does not defensively recover it. The stack trace references a missing ACL mapping in `ReferenceCountedACLCache`.
