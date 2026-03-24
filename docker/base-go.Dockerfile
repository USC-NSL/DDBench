FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates curl wget make gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*

# Install Go from official tarball (apt golang-go is often outdated)
ARG GO_VERSION=1.23.6
RUN ARCH=$(dpkg --print-architecture) && \
    curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:/root/go/bin:${PATH}"

# Install Delve (Go debugger)
RUN go install github.com/go-delve/delve/cmd/dlv@latest

WORKDIR /workspace
