# Setup: ZooKeeper #4846

## Project
- **Repository:** https://github.com/apache/zookeeper
- **Language:** Java
- **Issue:** https://issues.apache.org/jira/browse/ZOOKEEPER-4846

## Clone and checkout buggy version
```bash
git clone https://github.com/apache/zookeeper.git
cd zookeeper
git checkout 8532163df198466913f26141c0278dc11dbf53ab~1
```

## Build
```bash
mvn -pl zookeeper-server -am install -DskipTests -Dcheckstyle.skip -Dspotbugs.skip -Drat.skip -Dmaven.javadoc.skip -q
```
