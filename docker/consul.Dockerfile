FROM bug-bench/base-go

# Consul needs jq and curl for the reproduce script (querying API with stale reads)
RUN apt-get update && apt-get install -y --no-install-recommends \
    jq \
    unzip \
    && rm -rf /var/lib/apt/lists/*
