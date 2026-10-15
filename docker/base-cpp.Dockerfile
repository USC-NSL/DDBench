FROM ubuntu:24.04@sha256:534baea6a22c03a63003dbc8dbe78fe34bc0d7e595d9a9dc9834884ff530eb55

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential cmake ninja-build git ca-certificates \
    gdb lldb \
    redis-tools python3 netcat-openbsd curl wget \
    && rm -rf /var/lib/apt/lists/*

# Default working directory for source code
WORKDIR /workspace
