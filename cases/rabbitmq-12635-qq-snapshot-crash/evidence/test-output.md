# Test Output

Obtained by running `make -C deps/rabbit ct-quorum_queue t=cluster_size_3:gh_12635` against the buggy build in a 3-node RabbitMQ cluster.

## Output

```
Common Test starting

TEST INFO: 1 test(s), 1 case(s) in 1 suite(s)

== quorum_queue_SUITE ==
  * [clustered]
    * [cluster_size_3]
      gh_12635 (00:00.623)

quorum_queue_SUITE > clustered > cluster_size_3 > gh_12635
    #1. {error,{test_case_failed,"unexpected DOWN"}}

Updating logs/index.html ... done
Updating logs/all_runs.html ... done

make: *** [ct-quorum_queue] Error 1
```
