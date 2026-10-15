# Test Output

Obtained by running `redis-cli` commands against a Kvrocks instance: adding two namespaces with distinct tokens, then using `NAMESPACE SET` to assign a duplicate token, and checking the namespace list.

## Output

```
Adding namespace ns1 with token1...
OK
Adding namespace ns2 with token2...
OK
Current namespaces:
ns1
token1
ns2
token2
__namespace
foobared

Sending: NAMESPACE SET ns1 token2 (duplicate token)
OK

Checking namespaces after SET:
ns1
token2
__namespace
foobared
```
