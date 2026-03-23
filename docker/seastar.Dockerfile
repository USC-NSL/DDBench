FROM bug-bench/base-cpp

# Seastar has a large dependency set. We bake in the essentials that
# install-dependencies.sh would install, so the image is ready to build.
# The full list comes from seastar/install-dependencies.sh for Ubuntu 24.04.
RUN apt-get update && apt-get install -y --no-install-recommends \
    libaio-dev systemtap-sdt-dev \
    libtool pkg-config \
    libboost-all-dev \
    libfmt-dev \
    libsctp-dev \
    ragel \
    libhwloc-dev \
    libnuma-dev \
    libpciaccess-dev \
    libcrypto++-dev \
    libxml2-dev \
    xfslibs-dev \
    libgnutls28-dev \
    liblz4-dev \
    libprotobuf-dev protobuf-compiler \
    libsystemd-dev \
    stow \
    libyaml-cpp-dev \
    libp11-kit-dev \
    valgrind \
    libunistring-dev \
    && rm -rf /var/lib/apt/lists/*
