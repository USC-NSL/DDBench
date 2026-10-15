# Code Investigation

## What was searched
The symptom describes entries written concurrently with a fence request succeeding instead of being rejected with `LedgerFencedException`. Searched for where the bookie obtains the per-ledger handle that both the write path and the fence path operate on (`HandleFactoryImpl`), and where fence state is kept (`LedgerDescriptor`).

## What was found
```
$ cat -n bookkeeper-server/src/main/java/org/apache/bookkeeper/bookie/HandleFactoryImpl.java | sed -n '30,95p'
    30	
    31	class HandleFactoryImpl implements HandleFactory, LedgerDeletionListener {
    32	    private final ConcurrentLongHashMap<LedgerDescriptor> ledgers;
    33	    private final ConcurrentLongHashMap<LedgerDescriptor> readOnlyLedgers;
    34	
    35	    /**
    36	     * Once the ledger was marked "fenced" before, the ledger was accessed by multi clients. One client is calling
    37	     * "delete" now, and other clients may call "write" continuously later. We mark these ledgers can not be written
    38	     * anymore. And maintains the state for 7 days is safety.
    39	     */
    40	    private final Cache<Long, Boolean> recentlyFencedAndDeletedLedgers = CacheBuilder.newBuilder()
    41	            .expireAfterAccess(Duration.ofDays(7)).build();
    42	
    43	    final LedgerStorage ledgerStorage;
    44	
    45	    HandleFactoryImpl(LedgerStorage ledgerStorage) {
    46	        this.ledgerStorage = ledgerStorage;
    47	        this.ledgers = ConcurrentLongHashMap.<LedgerDescriptor>newBuilder().build();
    48	        this.readOnlyLedgers = ConcurrentLongHashMap.<LedgerDescriptor>newBuilder().build();
    49	
    50	        ledgerStorage.registerLedgerDeletionListener(this);
    51	    }
    52	
    53	    @Override
    54	    public LedgerDescriptor getHandle(final long ledgerId, final byte[] masterKey, boolean journalReplay)
    55	            throws IOException, BookieException {
    56	        LedgerDescriptor handle = ledgers.get(ledgerId);
    57	
    58	        if (handle == null) {
    59	            if (!journalReplay && recentlyFencedAndDeletedLedgers.getIfPresent(ledgerId) != null) {
    60	                throw BookieException.create(BookieException.Code.LedgerFencedAndDeletedException);
    61	            }
    62	            handle = LedgerDescriptor.create(masterKey, ledgerId, ledgerStorage);
    63	            ledgers.putIfAbsent(ledgerId, handle);
    64	        }
    65	
    66	        handle.checkAccess(masterKey);
    67	        return handle;
    68	    }
    69	
    70	    @Override
    71	    public LedgerDescriptor getReadOnlyHandle(final long ledgerId) throws IOException, Bookie.NoLedgerException {
    72	        LedgerDescriptor handle = readOnlyLedgers.get(ledgerId);
    73	
    74	        if (handle == null) {
    75	            handle = LedgerDescriptor.createReadOnly(ledgerId, ledgerStorage);
    76	            readOnlyLedgers.putIfAbsent(ledgerId, handle);
    77	        }
    78	
    79	        return handle;
    80	    }
    81	
    82	    private void markIfConflictWritingOccurs(long ledgerId) {
    83	        LedgerDescriptor ledgerDescriptor = ledgers.get(ledgerId);
    84	        try {
    85	            if (ledgerDescriptor != null && ledgerDescriptor.isFenced()) {
    86	                recentlyFencedAndDeletedLedgers.put(ledgerId, true);
    87	            }
    88	        } catch (IOException | BookieException ex) {
    89	            // The ledger is in limbo state.
    90	            recentlyFencedAndDeletedLedgers.put(ledgerId, true);
    91	        }
    92	    }
    93	
    94	    @Override
    95	    public void ledgerDeleted(long ledgerId) {
```

```
$ grep -n 'fenced\|setFenced\|isFenced' bookkeeper-server/src/main/java/org/apache/bookkeeper/bookie/LedgerDescriptor.java
67:    abstract boolean setFenced() throws IOException;
68:    abstract boolean isFenced() throws IOException, BookieException;
70:     * When we fence a ledger, we need to first set ledger to fenced state in memory and
```

## Developer hypothesis
Fence checks and writes both go through the handle returned by `HandleFactoryImpl`. Worth checking how handle lookup and creation behave when a fence request and a write for the same ledger arrive at the bookie concurrently.
