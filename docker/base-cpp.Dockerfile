FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build git ca-certificates \
    gdb lldb \
    redis-tools python3 netcat-openbsd curl wget \
    && rm -rf /var/lib/apt/lists/*

# Default working directory for source code
WORKDIR /workspace
