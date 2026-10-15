# Code Investigation

## What was searched
The symptom describes committed data disappearing after a follower that had been offline rejoins, synchronizes without errors, and is later elected leader: other stale followers that then sync from it end up missing committed transactions. Read how a follower applies the proposals and commits it receives from the leader during synchronization (`Learner.syncWithLeader()`).

## What was found
```
$ cat -n zookeeper-server/src/main/java/org/apache/zookeeper/server/quorum/Learner.java | sed -n '625,716p'
   625	                readPacket(qp);
   626	                switch (qp.getType()) {
   627	                case Leader.PROPOSAL:
   628	                    PacketInFlight pif = new PacketInFlight();
   629	                    logEntry = SerializeUtils.deserializeTxn(qp.getData());
   630	                    pif.hdr = logEntry.getHeader();
   631	                    pif.rec = logEntry.getTxn();
   632	                    pif.digest = logEntry.getDigest();
   633	                    if (pif.hdr.getZxid() != lastQueued + 1) {
   634	                        LOG.warn(
   635	                            "Got zxid 0x{} expected 0x{}",
   636	                            Long.toHexString(pif.hdr.getZxid()),
   637	                            Long.toHexString(lastQueued + 1));
   638	                    }
   639	                    lastQueued = pif.hdr.getZxid();
   640	
   641	                    if (pif.hdr.getType() == OpCode.reconfig) {
   642	                        SetDataTxn setDataTxn = (SetDataTxn) pif.rec;
   643	                        QuorumVerifier qv = self.configFromString(new String(setDataTxn.getData(), UTF_8));
   644	                        self.setLastSeenQuorumVerifier(qv, true);
   645	                    }
   646	
   647	                    packetsNotLogged.add(pif);
   648	                    break;
   649	                case Leader.COMMIT:
   650	                case Leader.COMMITANDACTIVATE:
   651	                    pif = packetsNotLogged.peekFirst();
   652	                    if (pif.hdr.getZxid() == qp.getZxid() && qp.getType() == Leader.COMMITANDACTIVATE) {
   653	                        QuorumVerifier qv = self.configFromString(new String(((SetDataTxn) pif.rec).getData(), UTF_8));
   654	                        boolean majorChange = self.processReconfig(
   655	                            qv,
   656	                            ByteBuffer.wrap(qp.getData()).getLong(), qp.getZxid(),
   657	                            true);
   658	                        if (majorChange) {
   659	                            throw new Exception("changes proposed in reconfig");
   660	                        }
   661	                    }
   662	                    if (!writeToTxnLog) {
   663	                        if (pif.hdr.getZxid() != qp.getZxid()) {
   664	                            LOG.warn(
   665	                                "Committing 0x{}, but next proposal is 0x{}",
   666	                                Long.toHexString(qp.getZxid()),
   667	                                Long.toHexString(pif.hdr.getZxid()));
   668	                        } else {
   669	                            zk.processTxn(pif.hdr, pif.rec);
   670	                            packetsNotLogged.remove();
   671	                        }
   672	                    } else {
   673	                        packetsCommitted.add(qp.getZxid());
   674	                    }
   675	                    break;
   676	                case Leader.INFORM:
   677	                case Leader.INFORMANDACTIVATE:
   678	                    PacketInFlight packet = new PacketInFlight();
   679	
   680	                    if (qp.getType() == Leader.INFORMANDACTIVATE) {
   681	                        ByteBuffer buffer = ByteBuffer.wrap(qp.getData());
   682	                        long suggestedLeaderId = buffer.getLong();
   683	                        byte[] remainingdata = new byte[buffer.remaining()];
   684	                        buffer.get(remainingdata);
   685	                        logEntry = SerializeUtils.deserializeTxn(remainingdata);
   686	                        packet.hdr = logEntry.getHeader();
   687	                        packet.rec = logEntry.getTxn();
   688	                        packet.digest = logEntry.getDigest();
   689	                        QuorumVerifier qv = self.configFromString(new String(((SetDataTxn) packet.rec).getData(), UTF_8));
   690	                        boolean majorChange = self.processReconfig(qv, suggestedLeaderId, qp.getZxid(), true);
   691	                        if (majorChange) {
   692	                            throw new Exception("changes proposed in reconfig");
   693	                        }
   694	                    } else {
   695	                        logEntry = SerializeUtils.deserializeTxn(qp.getData());
   696	                        packet.rec = logEntry.getTxn();
   697	                        packet.hdr = logEntry.getHeader();
   698	                        packet.digest = logEntry.getDigest();
   699	                        // Log warning message if txn comes out-of-order
   700	                        if (packet.hdr.getZxid() != lastQueued + 1) {
   701	                            LOG.warn(
   702	                                "Got zxid 0x{} expected 0x{}",
   703	                                Long.toHexString(packet.hdr.getZxid()),
   704	                                Long.toHexString(lastQueued + 1));
   705	                        }
   706	                        lastQueued = packet.hdr.getZxid();
   707	                    }
   708	                    if (!writeToTxnLog) {
   709	                        // Apply to db directly if we haven't taken the snapshot
   710	                        zk.processTxn(packet.hdr, packet.rec);
   711	                    } else {
   712	                        packetsNotLogged.add(packet);
   713	                        packetsCommitted.add(qp.getZxid());
   714	                    }
   715	
   716	                    break;
```

## Developer hypothesis
Worth checking what state a follower builds while applying the transactions it receives during synchronization, and whether that state is complete enough for the follower to later act as the leader that synchronizes other stale followers.
