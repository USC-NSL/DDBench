# Setup: ZooKeeper #4925

## Project
- **Repository:** https://github.com/apache/zookeeper
- **Language:** Java
- **Issue:** https://issues.apache.org/jira/browse/ZOOKEEPER-4925

## Clone and checkout buggy version
```bash
git clone https://github.com/apache/zookeeper.git
cd zookeeper
git checkout e5dd60bf0512ccc1e090d99410a8da48623219da~1
```

## Build
```bash
mvn -pl zookeeper-server -am install -DskipTests -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip -q
```
