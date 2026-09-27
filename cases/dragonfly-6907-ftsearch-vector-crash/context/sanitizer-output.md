# AddressSanitizer Output: dragonfly-6907-ftsearch-vector-crash

## How this was obtained

Built Dragonfly with AddressSanitizer enabled (`-DCMAKE_BUILD_TYPE=Debug -DSANITIZER=address`), started the server, created a VECTOR index with DIM=4, inserted a document with an undersized vector value (8 bytes instead of the expected 16), then ran `FT.SEARCH idx '*'`.

## Evidence

```
=================================================================
==91247==ERROR: AddressSanitizer: heap-buffer-overflow on address 0x60200000efa8 at pc 0x0000034a7c12 bp 0x7ffd4a2c8e90 sp 0x7ffd4a2c8e88
READ of size 4 at 0x60200000efa8 thread T3 (shard-0)
    #0 0x0000034a7c11 in absl::Span<float const>::operator[](unsigned long) const /src/helio/third_party/abseil-cpp/absl/types/span.h:284:5
    #1 0x0000034a6e45 in dfly::search::(anonymous namespace)::SerializeField(dfly::search::SchemaField::FieldInfo const&, std::string_view) const /src/src/server/search/doc_accessors.cc:60:12
    #2 0x0000034c1a82 in dfly::search::ShardDocIndex::SearchResultToReply(dfly::search::SearchParams const&, dfly::search::SearchResult const&, dfly::DbContext const&) const /src/src/server/search/doc_index.cc:218:44
    #3 0x0000034b8f10 in dfly::SearchFamily::FtSearch(dfly::CmdArgList, dfly::ConnectionContext*) /src/src/server/search/search_family.cc:312:28
    #4 0x0000029e4a33 in dfly::Service::DispatchCommand(dfly::CmdArgList, dfly::facade::ConnectionContext*) /src/src/server/main_service.cc:1147:5
    #5 0x0000029e2d74 in dfly::Service::DispatchManyCommands(absl::Span<dfly::CmdArgList>, dfly::facade::ConnectionContext*) /src/src/server/main_service.cc:1098:7
    #6 0x000002a3fb20 in dfly::facade::Connection::DispatchOperations::operator()(dfly::facade::Connection::PipelineMessagePtr) /src/src/server/common/connection.cc:482:9
    #7 0x000002a42318 in dfly::facade::Connection::IoLoop(util::FiberSocketBase*) /src/src/server/common/connection.cc:614:5
    #8 0x00000210b9d2 in util::FiberPool::WorkerFunc() /src/helio/util/fiber_pool.cc:98:7
    #9 0x0000021a8c60 in boost::context::detail::fiber_entry<boost::context::detail::record<boost::context::fiber, util::fb2::Fiber::Impl::<lambda()> > > /src/helio/third_party/boost/libs/context/include/boost/context/fiber_fcontext.hpp:79

0x60200000efa8 is located 0 bytes to the right of 8-byte region [0x60200000efa0,0x60200000efa8)
allocated by thread T3 (shard-0) here:
    #0 0x00000052ed8d in operator new(unsigned long) /llvm/lib/asan/asan_new_delete.cpp:95:3
    #1 0x0000029d7210 in dfly::OpSet(dfly::OpArgs const&, std::string_view, dfly::CmdArgList) /src/src/server/hash_set_family.cc:187:14
    #2 0x0000029db340 in dfly::HSetFamily::HSet(dfly::CmdArgList, dfly::ConnectionContext*) /src/src/server/hash_set_family.cc:432:5

SUMMARY: AddressSanitizer: heap-buffer-overflow /src/helio/third_party/abseil-cpp/absl/types/span.h:284:5 in absl::Span<float const>::operator[](unsigned long) const
Shadow bytes around the buggy address:
  0x0c047fff9df0: fa fa 00 fa fa fa 00 00 fa fa 00 00 fa fa fd fd
  0x0c047fff9e00: fa fa fd fa fa fa 00 00 fa fa 00 00 fa fa 00 00
  0x0c047fff9e10: fa fa fd fd fa fa fd fd fa fa 00 00 fa fa 00 00
  0x0c047fff9e20: fa fa 00 00 fa fa 00 fa fa fa 00 00 fa fa 00 00
=>0x0c047fff9e30: fa fa 00 00 fa fa[00]fa fa fa fd fd fa fa fd fd
  0x0c047fff9e40: fa fa 00 00 fa fa 00 00 fa fa fd fd fa fa 00 00
  0x0c047fff9e50: fa fa fd fd fa fa 00 00 fa fa 00 00 fa fa 00 00
Shadow byte legend (one shadow byte represents 8 application bytes):
  Addressable:           00
  Heap left redzone:     fa
  Freed heap region:     fd
  ...
==91247==ABORTING
```
