FROM bug-bench/base-cpp

# Dragonfly build dependencies beyond the base C++ toolchain
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl-dev \
    libunwind-dev \
    libboost-fiber-dev \
    autoconf automake libtool \
    bison flex \
    && rm -rf /var/lib/apt/lists/*
