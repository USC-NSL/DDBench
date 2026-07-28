# Go toolchain is copied from the official image rather than extracted from the
# release tarball. Streaming the tarball into a RUN layer
# (`curl ... | tar -C /usr/local -xz`) produces a layer that is fine *within* the
# RUN step but corrupt once committed: the next layer — and `docker run` on the
# resulting image — fails with
#   runc: exec "/bin/sh": stat /bin/sh: no such file or directory
# i.e. the whole rootfs is unusable. Reproduced on Docker 28.5.1 / overlay2 /
# extfs, independent of extraction path, and not size-related (a 75 MB
# single-file layer commits fine). COPY --from avoids it entirely.
ARG GO_VERSION=1.23.6
FROM golang:${GO_VERSION}-bookworm AS gotoolchain

FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    git ca-certificates curl wget make gcc libc6-dev \
    && rm -rf /var/lib/apt/lists/*

COPY --from=gotoolchain /usr/local/go /usr/local/go
ENV PATH="/usr/local/go/bin:/root/go/bin:${PATH}"

# Install Delve (Go debugger)
RUN go install github.com/go-delve/delve/cmd/dlv@latest

WORKDIR /workspace
