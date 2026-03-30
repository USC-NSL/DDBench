FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Java 17, Git, and build tools for Kafka (Scala/Java, Gradle)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates curl \
    openjdk-17-jdk \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-17-openjdk-amd64

WORKDIR /workspace
