FROM elixir:1.17-otp-26

ENV DEBIAN_FRONTEND=noninteractive

# RabbitMQ 4.0 requires Erlang/OTP 26+ and Elixir.
# The base image provides OTP 26, Elixir 1.17, make, gcc, git, python3.
# Install additional build/test dependencies needed by the RabbitMQ build system.
RUN apt-get update && apt-get install -y --no-install-recommends \
    xsltproc xmlto zip unzip rsync curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace
