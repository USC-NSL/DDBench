# Symptom

Running `HINCRBYFLOAT` with `inf` as the increment creates a NaN or Inf value. This leaves the hash in an invalid empty state, causing a crash at `hset_family.cc:973`.
