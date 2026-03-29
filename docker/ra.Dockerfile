FROM erlang:26-slim

ENV DEBIAN_FRONTEND=noninteractive

# Ra uses erlang.mk which requires make, git, and standard build tools.
# OTP 26 provides the Erlang runtime; slim image includes make and basic utils.
RUN apt-get update && apt-get install -y --no-install-recommends \
    make gcc git curl ca-certificates python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
