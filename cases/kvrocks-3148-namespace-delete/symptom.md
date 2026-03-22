# Symptom: Kvrocks #3148

Using `NAMESPACE SET` to change a namespace's token to a token that is currently used by another namespace causes the other namespace to be silently deleted. For example, if `ns1` has `token1` and `ns2` has `token2`, running `NAMESPACE SET ns1 token2` will delete `ns2` from the namespace list entirely.

This is a data loss bug: the second namespace and all its associated data become inaccessible.
