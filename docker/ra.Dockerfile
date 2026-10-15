FROM erlang:26-slim@sha256:074686197a59e6681158ce50ed9d855fe35437aec574e0170c50a4faf32e7686

ENV DEBIAN_FRONTEND=noninteractive

# Ra uses erlang.mk which requires make, git, and standard build tools.
# OTP 26 provides the Erlang runtime; slim image includes make and basic utils.
RUN apt-get update && apt-get install -y --no-install-recommends \
    make gcc git curl ca-certificates python3 \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
