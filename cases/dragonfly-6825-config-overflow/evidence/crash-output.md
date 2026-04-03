# Crash Output

Obtained by running `./build-dbg/dragonfly --port 16379 --logtostderr --proactor_threads 1 --dbfilename="" --cluster_mode=yes --cluster_node_id=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa`, then sending `DFLYCLUSTER CONFIG` with a slot range end value of `1E383` followed by `CLUSTER MYID` against the buggy build.

## Output

```
F20260403 11:46:52.099848    10 main_service.cc:1622] Check failed: rb->RepliesRecorded() > replies_recorded_ (0 vs. 0) DFLYCLUSTER N6facade17RedisReplyBuilderE
*** Check failure stack trace: ***
    @     0x574f9061222d  google::LogMessage::Fail()
    @     0x574f90612173  google::LogMessage::SendToLog()
    @     0x574f90611926  google::LogMessage::Flush()
    @     0x574f906158d2  google::LogMessageFatal::~LogMessageFatal()
    @     0x574f8f843220  dfly::ReplyGuard::~ReplyGuard()
    @     0x574f8f7f4133  dfly::Service::InvokeCmd()
    @     0x574f8f7f30ca  dfly::Service::DispatchCommand()
    @     0x574f903249f5  facade::Connection::ParseRedis()::{lambda()#1}::operator()()
    @     0x574f90334e98  std::__invoke_impl<>()
    @     0x574f9033438d  std::__invoke<>()
    @     0x574f9033372c  std::invoke<>()
    @     0x574f9033281a  absl::lts_20250512::functional_internal::InvokeObject<>()
    @     0x574f90338ee8  absl::lts_20250512::FunctionRef<>::operator()()
    @     0x574f903248a5  facade::Connection::DispatchSingle()
    @     0x574f90325060  facade::Connection::ParseRedis()
    @     0x574f903230e3  facade::Connection::ConnectionFlow()
    @     0x574f90320d0a  facade::Connection::HandleRequests()
    @     0x574f90538225  util::ListenerInterface::RunSingleConnection()
*** SIGABRT received at time=1775216795 on cpu 0 ***
PC: @     0x7383746f8b2c  (unknown)  pthread_kill
    @     0x574f906754b3         64  absl::lts_20250512::WriteFailureInfo()
    @     0x574f90675737         96  absl::lts_20250512::AbslFailureSignalHandler()
    @     0x73837469f330       3504  (unknown)
    @     0x73837469f27e         32  raise
    @     0x7383746828ff        192  abort
    @     0x574f9061b659        176  google::DumpStackTraceAndExit()
    @     0x574f9061222d         16  google::LogMessage::Fail()
    @     0x574f90612173        160  google::LogMessage::SendToLog()
    @     0x574f90611926         80  google::LogMessage::Flush()
    @     0x574f906158d2         32  google::LogMessageFatal::~LogMessageFatal()
    @     0x574f8f843220        192  dfly::ReplyGuard::~ReplyGuard()
    @     0x574f8f7f4133        512  dfly::Service::InvokeCmd()
    @     0x574f8f7f30ca        496  dfly::Service::DispatchCommand()
    @     0x574f903249f5        128  facade::Connection::ParseRedis()::{lambda()#1}::operator()()
    @     0x574f90334e98         32  std::__invoke_impl<>()
    @     0x574f9033438d         32  std::__invoke<>()
    @     0x574f9033372c         32  std::invoke<>()
    @     0x574f9033281a         48  absl::lts_20250512::functional_internal::InvokeObject<>()
    @     0x574f90338ee8         32  absl::lts_20250512::FunctionRef<>::operator()()
    @     0x574f903248a5        288  facade::Connection::DispatchSingle()
    @     0x574f90325060        240  facade::Connection::ParseRedis()
    @     0x574f903230e3        352  facade::Connection::ConnectionFlow()
    @     0x574f90320d0a        640  facade::Connection::HandleRequests()
    @     0x574f90538225        288  util::ListenerInterface::RunSingleConnection()

Process exited with code 134 (SIGABRT).
```
