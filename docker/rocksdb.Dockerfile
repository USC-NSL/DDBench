FROM bug-bench/base-cpp

RUN apt-get update && apt-get install -y --no-install-recommends \
    libgflags-dev libsnappy-dev zlib1g-dev libbz2-dev \
    liblz4-dev libzstd-dev liburing-dev \
    && rm -rf /var/lib/apt/lists/*
