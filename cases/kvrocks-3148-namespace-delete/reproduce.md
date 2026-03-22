# Reproduce: Kvrocks #3148

## Step 1: Start Kvrocks
```bash
./build/kvrocks --port 6666 --dir /tmp/kvrocks-test --log-dir /tmp/kvrocks-test/logs
```

## Step 2: Create two namespaces with different tokens
Connect with the default admin credentials:
```bash
redis-cli -p 6666

# Add two namespaces
NAMESPACE ADD ns1 token1
NAMESPACE ADD ns2 token2

# Verify both exist
NAMESPACE GET *
```

## Step 3: Set ns1's token to ns2's token
```bash
redis-cli -p 6666 NAMESPACE SET ns1 token2
```

## Step 4: Check namespace list
```bash
redis-cli -p 6666 NAMESPACE GET *
```

## Expected result (bug present)
`ns2` has been deleted from the namespace list. Only `ns1` (now with `token2`) and the default namespace remain. `ns2` and any data associated with it are lost.

## Expected result (fixed)
The `NAMESPACE SET ns1 token2` command should return an error indicating that `token2` is already in use by another namespace.
