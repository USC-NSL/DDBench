# Setup: ZooKeeper #4643

## Project
- **Repository:** https://github.com/apache/zookeeper
- **Language:** Java
- **Issue:** https://issues.apache.org/jira/browse/ZOOKEEPER-4643

## Clone and checkout buggy version
```bash
git clone https://github.com/apache/zookeeper.git
cd zookeeper
git checkout 9fcb805fa1bb37b1f64ceb3bc5d7ccf349971bb7~1
```

## Build
```bash
mvn -pl zookeeper-server -am install -DskipTests -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip -q
```
