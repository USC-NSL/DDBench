FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Install Java 11, Maven, and native build tools (needed by circe-checksum NAR plugin)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates curl wget \
    openjdk-11-jdk maven \
    build-essential gcc g++ \
    && rm -rf /var/lib/apt/lists/*

ENV JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64

WORKDIR /workspace
