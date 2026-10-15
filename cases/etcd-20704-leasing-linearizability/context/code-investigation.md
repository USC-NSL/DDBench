# Code Investigation

## What was searched
The symptom describes reads through the leasing cache returning deleted keys, stale values, or `Version` values that never existed, under concurrent modifications. Read how the cache in `client/v3/leasing/cache.go` is read (`Get`, `notify`) and mutated (`Add`, `Update`, `Delete`), and how the write path in `client/v3/leasing/kv.go` drives those mutations.

## What was found
```
$ cat -n client/v3/leasing/cache.go | sed -n '120,238p'
   120	func (lc *leaseCache) Add(key string, resp *v3.GetResponse, op v3.Op) *v3.GetResponse {
   121		lk := &leaseKey{resp, resp.Header.Revision, closedCh}
   122		lc.mu.Lock()
   123		if lc.header == nil || lc.header.Revision < resp.Header.Revision {
   124			lc.header = resp.Header
   125		}
   126		lc.entries[key] = lk
   127		ret := lk.get(op)
   128		lc.mu.Unlock()
   129		return ret
   130	}
   131	
   132	func (lc *leaseCache) Update(key, val []byte, respHeader *v3pb.ResponseHeader) {
   133		li := lc.entries[string(key)]
   134		if li == nil {
   135			return
   136		}
   137		cacheResp := li.response
   138		if len(cacheResp.Kvs) == 0 {
   139			kv := &mvccpb.KeyValue{
   140				Key:            key,
   141				CreateRevision: respHeader.Revision,
   142			}
   143			cacheResp.Kvs = append(cacheResp.Kvs, kv)
   144			cacheResp.Count = 1
   145		}
   146		cacheResp.Kvs[0].Version++
   147		if cacheResp.Kvs[0].ModRevision < respHeader.Revision {
   148			cacheResp.Header = respHeader
   149			cacheResp.Kvs[0].ModRevision = respHeader.Revision
   150			cacheResp.Kvs[0].Value = val
   151		}
   152	}
   153	
   154	func (lc *leaseCache) Delete(key string, hdr *v3pb.ResponseHeader) {
   155		lc.mu.Lock()
   156		defer lc.mu.Unlock()
   157		lc.delete(key, hdr)
   158	}
   159	
   160	func (lc *leaseCache) delete(key string, hdr *v3pb.ResponseHeader) {
   161		if li := lc.entries[key]; li != nil && hdr.Revision >= li.response.Header.Revision {
   162			li.response.Kvs = nil
   163			li.response.Header = copyHeader(hdr)
   164		}
   165	}
   166	
   167	func (lc *leaseCache) Evict(key string) (rev int64) {
   168		lc.mu.Lock()
   169		defer lc.mu.Unlock()
   170		if li := lc.entries[key]; li != nil {
   171			rev = li.rev
   172			delete(lc.entries, key)
   173			lc.revokes[key] = time.Now()
   174		}
   175		return rev
   176	}
   177	
   178	func (lc *leaseCache) EvictRange(key, end string) {
   179		lc.mu.Lock()
   180		defer lc.mu.Unlock()
   181		for k := range lc.entries {
   182			if inRange(k, key, end) {
   183				delete(lc.entries, key)
   184				lc.revokes[key] = time.Now()
   185			}
   186		}
   187	}
   188	
   189	func isBadOp(op v3.Op) bool { return op.Rev() > 0 || len(op.RangeBytes()) > 0 }
   190	
   191	func (lc *leaseCache) Get(ctx context.Context, op v3.Op) (*v3.GetResponse, bool) {
   192		if isBadOp(op) {
   193			return nil, false
   194		}
   195		key := string(op.KeyBytes())
   196		li, wc := lc.notify(key)
   197		if li == nil {
   198			return nil, true
   199		}
   200		select {
   201		case <-wc:
   202		case <-ctx.Done():
   203			return nil, true
   204		}
   205		lc.mu.RLock()
   206		lk := *li
   207		ret := lk.get(op)
   208		lc.mu.RUnlock()
   209		return ret, true
   210	}
   211	
   212	func (lk *leaseKey) get(op v3.Op) *v3.GetResponse {
   213		resp := lk.response
   214		empty := len(resp.Kvs) == 0 || op.IsCountOnly()
   215		empty = empty || (op.MinModRev() > resp.Kvs[0].ModRevision)
   216		empty = empty || (op.MaxModRev() != 0 && op.MaxModRev() < resp.Kvs[0].ModRevision)
   217		empty = empty || (op.MinCreateRev() > resp.Kvs[0].CreateRevision)
   218		empty = empty || (op.MaxCreateRev() != 0 && op.MaxCreateRev() < resp.Kvs[0].CreateRevision)
   219	
   220		ret := copyGetResponseMetadataOnly(resp)
   221		if empty {
   222			ret.Kvs = nil
   223		} else {
   224			ret.Kvs = []*mvccpb.KeyValue{
   225				copyKeyValue(resp.Kvs[0], op.IsKeysOnly()),
   226			}
   227		}
   228		return ret
   229	}
   230	
   231	func (lc *leaseCache) notify(key string) (*leaseKey, <-chan struct{}) {
   232		lc.mu.RLock()
   233		defer lc.mu.RUnlock()
   234		if li := lc.entries[key]; li != nil {
   235			return li, li.waitc
   236		}
   237		return nil, nil
   238	}
```

```
$ cat -n client/v3/leasing/kv.go | sed -n '218,264p'
   218	func (lkv *leasingKV) tryModifyOp(ctx context.Context, op v3.Op) (*v3.TxnResponse, chan<- struct{}, error) {
   219		key := string(op.KeyBytes())
   220		wc, rev := lkv.leases.Lock(key)
   221		cmp := v3.Compare(v3.CreateRevision(lkv.pfx+key), "<", rev+1)
   222		resp, err := lkv.kv.Txn(ctx).If(cmp).Then(op).Commit()
   223		switch {
   224		case err != nil:
   225			lkv.leases.Evict(key)
   226			fallthrough
   227		case !resp.Succeeded:
   228			if wc != nil {
   229				close(wc)
   230			}
   231			return nil, nil, err
   232		}
   233		return resp, wc, nil
   234	}
   235	
   236	func (lkv *leasingKV) put(ctx context.Context, op v3.Op) (pr *v3.PutResponse, err error) {
   237		if err := lkv.waitSession(ctx); err != nil {
   238			return nil, err
   239		}
   240		for ctx.Err() == nil {
   241			resp, wc, err := lkv.tryModifyOp(ctx, op)
   242			if err != nil || wc == nil {
   243				resp, err = lkv.revoke(ctx, string(op.KeyBytes()), op)
   244			}
   245			if err != nil {
   246				return nil, err
   247			}
   248			if resp.Succeeded {
   249				lkv.leases.mu.Lock()
   250				lkv.leases.Update(op.KeyBytes(), op.ValueBytes(), resp.Header)
   251				lkv.leases.mu.Unlock()
   252				pr = (*v3.PutResponse)(resp.Responses[0].GetResponsePut())
   253				pr.Header = resp.Header
   254			}
   255			if wc != nil {
   256				close(wc)
   257			}
   258			if resp.Succeeded {
   259				return pr, nil
   260			}
   261		}
   262		return nil, ctx.Err()
   263	}
   264	
```

## Developer hypothesis
Cache readers and writers coordinate through per-key `waitc` channels together with `lc.mu`. Worth checking how these two mechanisms order cache reads against concurrent puts and deletes of the same key, and how cached revision metadata is maintained across such updates.
