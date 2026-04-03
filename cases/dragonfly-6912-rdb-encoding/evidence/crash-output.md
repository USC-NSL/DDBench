# Crash Output

Obtained by running `./build-dbg/dragonfly --port 16379 --logtostderr --proactor_threads 1 --dbfilename=""`, then `redis-cli -p 16379 CMS.INITBYPROB mysketch 0.001 0.01`, `redis-cli -p 16379 CMS.INCRBY mysketch item1 5 item2 10`, and `redis-cli -p 16379 DUMP mysketch` against the buggy build.

## Output

```
F20260403 11:50:10.158232    10 rdb_save.cc:206] Unknown encoding 0 for type 17
*** Check failure stack trace: ***
    @     0x5f36893e0f0d  google::LogMessage::Fail()
    @     0x5f36893e0e53  google::LogMessage::SendToLog()
    @     0x5f36893e0606  google::LogMessage::Flush()
    @     0x5f36893e45b2  google::LogMessageFatal::~LogMessageFatal()
    @     0x5f36886cb86d  dfly::RdbObjectType()
    @     0x5f36886d44d5  dfly::RdbSerializerBase::DumpValue()
    @     0x5f36886d4b42  dfly::RdbSerializerBase::DumpValue()
    @     0x5f36884c8f71  dfly::(anonymous namespace)::DumpToString()
    @     0x5f36884cb1dc  dfly::(anonymous namespace)::OpDump()
    @     0x5f36884d8c28  dfly::GenericFamily::Dump()::{lambda()#1}::operator()()
    @     0x5f36884e09f1  dfly::Transaction::ScheduleSingleHopT<>()::{lambda()#1}::operator()()
    @     0x5f36884e9a76  std::__invoke_impl<>()
    @     0x5f36884e899b  std::__invoke<>()
    @     0x5f36884e6da7  std::invoke<>()
    @     0x5f36884e4acf  absl::lts_20250512::functional_internal::InvokeObject<>()
    @     0x5f3688e6d308  absl::lts_20250512::FunctionRef<>::operator()()
    @     0x5f3688e59109  dfly::Transaction::RunCallback()
    @     0x5f3688e5e63c  dfly::Transaction::ScheduleInShard()
    @     0x5f3688e5a294  dfly::Transaction::ScheduleInternal()
    @     0x5f3688e5b9f0  dfly::Transaction::Execute()
    @     0x5f3688e5b1e7  dfly::Transaction::ScheduleSingleHop()
    @     0x5f36884e0ab6  dfly::Transaction::ScheduleSingleHopT<>()
    @     0x5f36884d8e73  dfly::GenericFamily::Dump()
*** SIGABRT received at time=1775216994 on cpu 0 ***
PC: @     0x70b2153eab2c  (unknown)  pthread_kill
    @     0x5f3689444193         64  absl::lts_20250512::WriteFailureInfo()
    @     0x5f3689444417         96  absl::lts_20250512::AbslFailureSignalHandler()
    @     0x70b215391330       3520  (unknown)
    @     0x70b21539127e         32  raise
    @     0x70b2153748ff        192  abort
    @     0x5f36893ea339        176  google::DumpStackTraceAndExit()
    @     0x5f36893e0f0d         16  google::LogMessage::Fail()
    @     0x5f36893e0e53        160  google::LogMessage::SendToLog()
    @     0x5f36893e0606         80  google::LogMessage::Flush()
    @     0x5f36893e45b2         32  google::LogMessageFatal::~LogMessageFatal()
    @     0x5f36886cb86d        160  dfly::RdbObjectType()
    @     0x5f36886d44d5        224  dfly::RdbSerializerBase::DumpValue()
    @     0x5f36886d4b42        336  dfly::RdbSerializerBase::DumpValue()
    @     0x5f36884c8f71        240  dfly::(anonymous namespace)::DumpToString()
    @     0x5f36884cb1dc        240  dfly::(anonymous namespace)::OpDump()
    @     0x5f36884d8c28        112  dfly::GenericFamily::Dump()::{lambda()#1}::operator()()
    @     0x5f36884e09f1         96  dfly::Transaction::ScheduleSingleHopT<>()::{lambda()#1}::operator()()
    @     0x5f36884e9a76         64  std::__invoke_impl<>()
    @     0x5f36884e899b         64  std::__invoke<>()
    @     0x5f36884e6da7         64  std::invoke<>()
    @     0x5f36884e4acf         96  absl::lts_20250512::functional_internal::InvokeObject<>()
    @     0x5f3688e6d308         64  absl::lts_20250512::FunctionRef<>::operator()()
    @     0x5f3688e59109        240  dfly::Transaction::RunCallback()
    @     0x5f3688e5e63c        448  dfly::Transaction::ScheduleInShard()

Error: Server closed the connection
Process exited with code 134 (SIGABRT).
```
