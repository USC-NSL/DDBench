# Crash Output

Obtained by running `./build-dbg/dragonfly --port 16379 --logtostderr --proactor_threads 1 --dbfilename="" --cluster_mode=yes --cluster_node_id=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa` and then `redis-cli -p 16379 DFLYCLUSTER FLUSHSLOTS 0 16384` against the buggy build.

## Output

```
*** SIGABRT received at time=1775216871 on cpu 0 ***
PC: @     0x70fa3504fb2c  (unknown)  pthread_kill
    @     0x594bfe87c873         64  absl::lts_20250512::WriteFailureInfo()
    @     0x594bfe87caf7         96  absl::lts_20250512::AbslFailureSignalHandler()
    @     0x70fa34ff6330       3520  (unknown)
    @     0x70fa34ff627e         32  raise
    @     0x70fa34fd98ff        192  abort
    @     0x594bfe822a19        176  google::DumpStackTraceAndExit()
    @     0x594bfe8195ed         16  google::LogMessage::Fail()
    @     0x594bfe819533        160  google::LogMessage::SendToLog()
    @     0x594bfe818ce6         80  google::LogMessage::Flush()
    @     0x594bfe81cc92         32  google::LogMessageFatal::~LogMessageFatal()
    @     0x594bfd812be5        176  MainInitGuard::MainInitGuard()::{lambda()#1}::operator()()
    @     0x594bfd812cf4         16  MainInitGuard::MainInitGuard()::{lambda()#1}::_FUN()
    @     0x70fa353970da         16  (unknown)
    @     0x70fa35381a55         16  std::terminate()
    @     0x70fa35397391         48  __cxa_throw
    @     0x70fa353854a0        832  std::__throw_out_of_range_fmt()
    @     0x594bfdc6c1e0         48  std::bitset<>::_M_check()
    @     0x594bfdc696b3         48  std::bitset<>::set()
    @     0x594bfdc67a75         96  dfly::cluster::SlotSet::Set()
    @     0x594bfdcacae1         64  dfly::cluster::SlotSet::SlotSet()
    @     0x594bfe1c4461        112  dfly::DbSlice::FlushSlots()
    @     0x594bfdc89c6a         64  dfly::cluster::(anonymous namespace)::DeleteSlots()::{lambda()#1}::operator()<>()
    @     0x594bfdc92c4d         32  util::ProactorPool::AwaitFiberOnAll<>()::{lambda()#1}::operator()()
    @     0x594bfdca53fc         48  std::__invoke_impl<>()
    @     0x594bfdca3855         48  std::__invoke<>()
    @     0x594bfdca235a         48  std::__apply_impl<>()
    @     0x594bfdca2398         48  std::apply<>()
    @     0x594bfdca2432        112  util::fb2::detail::WorkerFiberImpl<>::run_()

Error: Server closed the connection
Process exited with code 134 (SIGABRT).
```
