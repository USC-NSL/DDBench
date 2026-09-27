# Crash Output

Obtained by running `./build-dbg/dragonfly --port 16379 --logtostderr --proactor_threads 1 --dbfilename="" --cluster_mode=yes --cluster_node_id=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` and then `redis-cli -p 16379 DFLYCLUSTER CONFIG '[{"slot_ranges":[{"start":0,"end":1E383}],"master":{"id":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","ip":"127.0.0.1","port":16379},"replicas":[]}]'` followed by `redis-cli -p 16379 CLUSTER MYID` against the buggy build.

## Output

```
E20260407 23:17:41.134198     9 main_service.cc:1675] Internal error, system probably unstable : Cannot convert to integer
F20260407 23:17:41.134316     9 main_service.cc:1622] Check failed: rb->RepliesRecorded() > replies_recorded_ (0 vs. 0) DFLYCLUSTER N6facade17RedisReplyBuilderE
*** Check failure stack trace: ***
    @     0x576e510aa22d  google::LogMessage::Fail()
    @     0x576e510aa173  google::LogMessage::SendToLog()
    @     0x576e510a9926  google::LogMessage::Flush()
    @     0x576e510ad8d2  google::LogMessageFatal::~LogMessageFatal()
    @     0x576e502db220  dfly::ReplyGuard::~ReplyGuard()
    @     0x576e5028c133  dfly::Service::InvokeCmd()
    @     0x576e5028b0ca  dfly::Service::DispatchCommand()
    @     0x576e50dbc9f5  facade::Connection::ParseRedis()::{lambda()#1}::operator()()
    @     0x576e50dcce98  std::__invoke_impl<>()
    @     0x576e50dcc38d  std::__invoke<>()
    @     0x576e50dcb72c  std::invoke<>()
    @     0x576e50dca81a  absl::lts_20250512::functional_internal::InvokeObject<>()
    @     0x576e50dd0ee8  absl::lts_20250512::FunctionRef<>::operator()()
    @     0x576e50dbc8a5  facade::Connection::DispatchSingle()
    @     0x576e50dbd060  facade::Connection::ParseRedis()
    @     0x576e50dbb0e3  facade::Connection::ConnectionFlow()
    @     0x576e50db8d0a  facade::Connection::HandleRequests()
    @     0x576e50fd0225  util::ListenerInterface::RunSingleConnection()
*** SIGABRT received at time=1775603861 on cpu 0 ***
PC: @     0x732ca3bceb2c  (unknown)  pthread_kill
    @     0x576e5110d4b3         64  absl::lts_20250512::WriteFailureInfo()
    @     0x576e5110d737         96  absl::lts_20250512::AbslFailureSignalHandler()
    @     0x732ca3b75330       1520  (unknown)
    @     0x732ca3b7527e         32  raise
    @     0x732ca3b588ff        192  abort
    @     0x576e510b3659        176  google::DumpStackTraceAndExit()
    @     0x576e510aa22d         16  google::LogMessage::Fail()
    @     0x576e510aa173        160  google::LogMessage::SendToLog()
    @     0x576e510a9926         80  google::LogMessage::Flush()
    @     0x576e510ad8d2         32  google::LogMessageFatal::~LogMessageFatal()
    @     0x576e502db220        192  dfly::ReplyGuard::~ReplyGuard()
    @     0x576e5028c133        512  dfly::Service::InvokeCmd()
    @     0x576e5028b0ca        496  dfly::Service::DispatchCommand()
    @     0x576e50dbc9f5        128  facade::Connection::ParseRedis()::{lambda()#1}::operator()()
    @     0x576e50dcce98         32  std::__invoke_impl<>()
    @     0x576e50dcc38d         32  std::__invoke<>()
    @     0x576e50dcb72c         32  std::invoke<>()
    @     0x576e50dca81a         48  absl::lts_20250512::functional_internal::InvokeObject<>()
    @     0x576e50dd0ee8         32  absl::lts_20250512::FunctionRef<>::operator()()
    @     0x576e50dbc8a5        288  facade::Connection::DispatchSingle()
    @     0x576e50dbd060        240  facade::Connection::ParseRedis()
    @     0x576e50dbb0e3        352  facade::Connection::ConnectionFlow()
    @     0x576e50db8d0a        640  facade::Connection::HandleRequests()
    @     0x576e50fd0225        288  util::ListenerInterface::RunSingleConnection()

Error: Server closed the connection
Process exited with code 134 (SIGABRT).
```
