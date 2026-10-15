# Reproduce: Kvrocks #3148

## Step 1: Create a config file with a password

Namespace commands require authentication. Create a minimal config:
```bash
cat > /tmp/kvrocks-test.conf <<'EOF'
bind 0.0.0.0
port 6666
dir /tmp/kvrocks-test
log-dir /tmp/kvrocks-test/logs
requirepass foobared
EOF
```

## Step 2: Start Kvrocks
```bash
mkdir -p /tmp/kvrocks-test/logs
./build/kvrocks -c /tmp/kvrocks-test.conf
```

## Step 3: Create two namespaces with different tokens
Connect with admin credentials (`-a` flag for the password):
```bash
redis-cli -p 6666 -a foobared

# Add two namespaces
NAMESPACE ADD ns1 token1
NAMESPACE ADD ns2 token2

# Verify both exist
NAMESPACE GET *
```

## Step 4: Set ns1's token to ns2's token
```bash
redis-cli -p 6666 -a foobared NAMESPACE SET ns1 token2
```

## Step 5: Check namespace list
```bash
redis-cli -p 6666 -a foobared NAMESPACE GET *
```

## Expected result (bug present)
`ns2` has been deleted from the namespace list. Only `ns1` (now with `token2`) and the default namespace remain. `ns2` and any data associated with it are lost.

## Expected result (fixed)
The `NAMESPACE SET ns1 token2` command should return an error indicating that `token2` is already in use by another namespace.

## Oracle verdict

`./bench.sh reproduce kvrocks-3148-namespace-delete` rebuilds the worktree and runs the oracle (`reproduce.sh`):

- **FAIL** (exit 1): after `NAMESPACE ADD ns1 token1`, `NAMESPACE ADD ns2 token2` and `NAMESPACE SET ns1 token2`, `NAMESPACE GET *` no longer lists `ns2` (or the `NAMESPACE GET` call fails). A worktree that does not build, Kvrocks that does not answer `PING` within 30 s of starting, or a `NAMESPACE ADD` that does not return `OK`, is also FAIL.
- **PASS** (exit 0): `NAMESPACE GET *` still lists `ns2` after the token change (whether `NAMESPACE SET` itself succeeds or is rejected is not checked).
- **ERROR** (exit 2): `REBUILD.sh` or the built `build/kvrocks` binary is missing (the case is not set up).
