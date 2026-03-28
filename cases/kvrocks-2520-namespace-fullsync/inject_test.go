package namespace

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"
	"github.com/stretchr/testify/require"

	"github.com/apache/kvrocks/tests/gocase/util"
)

func TestNamespaceReplicateWithFullSync(t *testing.T) {
	config := map[string]string{
		"rocksdb.write_buffer_size":       "4",
		"rocksdb.target_file_size_base":   "16",
		"rocksdb.max_write_buffer_number": "1",
		"rocksdb.wal_ttl_seconds":         "0",
		"rocksdb.wal_size_limit_mb":       "0",
		"repl-namespace-enabled":          "yes",
		"requirepass":                     "123",
		"masterauth":                      "123",
	}
	master := util.StartServer(t, config)
	defer master.Close()
	masterClient := master.NewClientWithOption(&redis.Options{Password: "123"})
	defer func() { require.NoError(t, masterClient.Close()) }()

	slave := util.StartServer(t, config)
	defer slave.Close()
	slaveClient := slave.NewClientWithOption(&redis.Options{Password: "123"})
	defer func() { require.NoError(t, slaveClient.Close()) }()

	ctx := context.Background()
	value := strings.Repeat("a", 128*1024)
	for i := 0; i < 1024; i++ {
		require.NoError(t, masterClient.Set(ctx, fmt.Sprintf("key%d", i), value, 0).Err())
	}
	require.NoError(t, masterClient.Do(ctx, "NAMESPACE", "ADD", "foo", "bar").Err())

	util.SlaveOf(t, slaveClient, master)
	util.WaitForOffsetSync(t, masterClient, slaveClient, 60*time.Second)

	// Namespaces should be replicated after the full sync
	token, err := slaveClient.Do(ctx, "NAMESPACE", "GET", "foo").Result()
	require.NoError(t, err)
	require.EqualValues(t, "bar", token)
}
