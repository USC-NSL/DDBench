FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Java 11, Maven, and build tools for ZooKeeper
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates curl \
    openjdk-11-jdk maven \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64

WORKDIR /workspace
