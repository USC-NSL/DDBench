# Test Output

Obtained by running `cd client/v3 && go test -race -v -timeout 120s -count=1 ./leasing/...` against the buggy build.

## Output

```
?   	go.etcd.io/etcd/client/v3/leasing	[no test files]
```

The leasing package has no test files at all, so there is zero test coverage for the cache's concurrent access patterns.
