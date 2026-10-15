/*
 * DDBench oracle for kafka-15784-txn-offset-atomicity.
 *
 * A single-broker group coordinator runs on a real ReplicaManager and a real
 * __consumer_offsets log (one partition, replication factor 1). Only the
 * transaction coordinator is simulated: the broker's verification requests
 * (transaction.partition.verification.enable=true) are held by the test and
 * answered "the partition is in the transaction" when the test decides.
 *
 * A transactional producer commits offset 10 for its consumer group, and an
 * administrative or coordinator event happens while that offset commit is still
 * being processed. The producer then completes its transaction: it commits when
 * the offset commit was acknowledged, retries retriable errors, and aborts on any
 * other error. Afterwards the offset served by the live coordinator must equal the
 * offset a new coordinator serves after reloading __consumer_offsets (failover),
 * and an acknowledged and committed offset must be the one served.
 *
 * Only public coordinator entry points are used (the request handlers that
 * KafkaApis calls), so the test does not depend on how the broker organises the
 * verification, validation and append steps internally.
 */
package kafka.coordinator.group

import java.io.File
import java.nio.file.Files
import java.util.{OptionalInt, Properties}
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.atomic.{AtomicInteger, AtomicReference}

import kafka.common.OffsetAndMetadata
import kafka.log.LogManager
import kafka.server.{AddPartitionsToTxnManager, AlterPartitionManager, BrokerTopicStats, KafkaConfig, KafkaRequestHandler, MetadataCache, QuotaFactory, ReplicaManager, RequestLocal}
import kafka.server.QuotaFactory.QuotaManagers
import kafka.server.metadata.ConfigRepository
import org.apache.kafka.common.{Node, TopicIdPartition, TopicPartition, Uuid}
import org.apache.kafka.common.config.ConfigResource
import org.apache.kafka.common.internals.Topic
import org.apache.kafka.common.message.LeaderAndIsrRequestData.LeaderAndIsrPartitionState
import org.apache.kafka.common.metrics.Metrics
import org.apache.kafka.common.protocol.{ApiKeys, Errors}
import org.apache.kafka.common.record.{ControlRecordType, EndTransactionMarker, MemoryRecords}
import org.apache.kafka.common.requests.{JoinGroupRequest, LeaderAndIsrRequest, TransactionResult}
import org.apache.kafka.common.utils.{Time, Utils}
import org.apache.kafka.server.util.KafkaScheduler
import org.apache.kafka.storage.internals.log.{AppendOrigin, LogDirFailureChannel}
import org.junit.jupiter.api.Assertions.{assertEquals, assertTrue, fail}
import org.junit.jupiter.api.{AfterEach, BeforeEach, Test, Timeout}
import org.mockito.Mockito.{mock, withSettings}
import org.mockito.invocation.InvocationOnMock
import org.mockito.stubbing.Answer

import scala.jdk.CollectionConverters._

@Timeout(300)
class DDBenchOracleTxnOffsetCommitTest {

  private val time = Time.SYSTEM
  private val brokerId = 0
  private val groupId = "ddbench-oracle-group"
  private val transactionalId = "ddbench-oracle-txn"
  private val producerId = 4242L
  private val producerEpoch: Short = 0
  private val committedOffset = 10L
  private val inputPartition = new TopicIdPartition(Uuid.randomUuid(), 0, "ddbench-oracle-input")
  private val offsetsPartition = new TopicPartition(Topic.GROUP_METADATA_TOPIC_NAME, 0)
  private val waitMs = 60000L

  // Retriable TxnOffsetCommit errors: the producer retries the same request.
  private val retriableErrors = Set(Errors.COORDINATOR_NOT_AVAILABLE, Errors.NOT_COORDINATOR,
    Errors.COORDINATOR_LOAD_IN_PROGRESS, Errors.CONCURRENT_TRANSACTIONS, Errors.UNKNOWN_TOPIC_OR_PARTITION,
    Errors.NOT_ENOUGH_REPLICAS, Errors.REQUEST_TIMED_OUT)

  private var logDir: File = _
  private var metrics: Metrics = _
  private var scheduler: KafkaScheduler = _
  private var quotaManagers: QuotaManagers = _
  private var logManager: LogManager = _
  private var replicaManager: ReplicaManager = _
  private var coordinators: List[(GroupCoordinator, Metrics)] = Nil

  // Verification requests the broker sent to the (simulated) transaction coordinator.
  private val verificationRequests = new AtomicInteger(0)
  private val pendingVerifications = new ConcurrentLinkedQueue[Map[TopicPartition, Errors] => Unit]()

  @BeforeEach
  def setUp(): Unit = {
    KafkaRequestHandler.setBypassThreadCheck(true)
    logDir = Files.createTempDirectory("ddbench-oracle-kafka-").toFile

    val props = new Properties()
    props.put("broker.id", brokerId.toString)
    props.put("zookeeper.connect", "127.0.0.1:1") // never contacted
    props.put("log.dirs", logDir.getAbsolutePath)
    props.put("offsets.topic.num.partitions", "1")
    props.put("offsets.topic.replication.factor", "1")
    props.put("transaction.partition.verification.enable", "true")
    props.put("group.initial.rebalance.delay.ms", "0")
    val config = KafkaConfig.fromProps(props)

    metrics = new Metrics()
    scheduler = new KafkaScheduler(1, true, "ddbench-oracle-scheduler-")
    scheduler.startup()
    val configRepository = new ConfigRepository {
      override def config(configResource: ConfigResource): Properties = new Properties()
    }
    val logDirFailureChannel = new LogDirFailureChannel(1)
    logManager = LogManager(config, Seq.empty, configRepository, scheduler, time, new BrokerTopicStats,
      logDirFailureChannel, true)
    quotaManagers = QuotaFactory.instantiate(config, metrics, time, "")

    // The simulated transaction coordinator: verification requests are queued and
    // answered by the test (see answerVerifications).
    val txnVerifier = mock(classOf[AddPartitionsToTxnManager], withSettings().defaultAnswer(new Answer[AnyRef] {
      override def answer(invocation: InvocationOnMock): AnyRef = {
        if (invocation.getMethod.getName == "verifyTransaction") {
          verificationRequests.incrementAndGet()
          // The completion callback (a Seq of partitions is a Function1 too, so skip collections).
          val callback = invocation.getArguments.reverse.collectFirst {
            case f: Function1[_, _] if !f.isInstanceOf[scala.collection.Iterable[_]] =>
              f.asInstanceOf[Map[TopicPartition, Errors] => Unit]
          }.getOrElse(throw new IllegalStateException("verifyTransaction was called without a callback"))
          pendingVerifications.add(callback)
          null
        } else {
          org.mockito.Mockito.RETURNS_DEFAULTS.answer(invocation)
        }
      }
    }))

    val metadataCache = mock(classOf[MetadataCache])
    replicaManager = new ReplicaManager(
      config = config,
      metrics = metrics,
      time = time,
      scheduler = scheduler,
      logManager = logManager,
      quotaManagers = quotaManagers,
      metadataCache = metadataCache,
      logDirFailureChannel = logDirFailureChannel,
      alterPartitionManager = mock(classOf[AlterPartitionManager]),
      addPartitionsToTxnManager = Some(txnVerifier))

    // This broker is the only replica and the leader of __consumer_offsets-0.
    val partitionState = new LeaderAndIsrPartitionState()
      .setTopicName(offsetsPartition.topic)
      .setPartitionIndex(offsetsPartition.partition)
      .setControllerEpoch(0)
      .setLeader(brokerId)
      .setLeaderEpoch(0)
      .setIsr(List[Integer](brokerId).asJava)
      .setPartitionEpoch(0)
      .setReplicas(List[Integer](brokerId).asJava)
      .setIsNew(true)
    val leaderAndIsr = new LeaderAndIsrRequest.Builder(ApiKeys.LEADER_AND_ISR.latestVersion, 0, 0, 0L,
      List(partitionState).asJava, Map(offsetsPartition.topic -> Uuid.randomUuid()).asJava,
      List(new Node(brokerId, "localhost", 9092)).asJava).build()
    replicaManager.becomeLeaderOrFollower(0, leaderAndIsr, (_, _) => ())
    assertTrue(replicaManager.onlinePartition(offsetsPartition).isDefined,
      "setup: __consumer_offsets-0 is not online on the broker")
  }

  @AfterEach
  def tearDown(): Unit = {
    coordinators.foreach { case (coordinator, coordinatorMetrics) =>
      quietly(coordinator.shutdown())
      quietly(coordinatorMetrics.close())
    }
    coordinators = Nil
    if (replicaManager != null) quietly(replicaManager.shutdown(checkpointHW = false))
    if (logManager != null) quietly(logManager.shutdown())
    if (quotaManagers != null) quietly(quotaManagers.shutdown())
    if (scheduler != null) quietly(scheduler.shutdown())
    if (metrics != null) quietly(metrics.close())
    if (logDir != null) quietly(Utils.delete(logDir))
    KafkaRequestHandler.setBypassThreadCheck(false)
  }

  /** Baseline: no concurrent event. */
  @Test
  def testDDBenchOracleTxnOffsetCommitBaseline(): Unit = {
    val coordinator = startCoordinator(epoch = 0)
    val firstResponse = sendTxnOffsetCommit(coordinator)
    val error = finishTxnOffsetCommit(coordinator, firstResponse)
    assertEquals(Errors.NONE, error, "a plain transactional offset commit was not acknowledged")
    completeTransactionAndCompare(coordinator, error, "no concurrent event")
  }

  /** The (empty) group is deleted while the transactional offset commit is in progress. */
  @Test
  def testDDBenchOracleGroupDeletedDuringTxnOffsetCommit(): Unit = {
    val coordinator = startCoordinator(epoch = 0)
    val firstResponse = sendTxnOffsetCommit(coordinator)
    requireInProgress(firstResponse)

    val deleteResult = coordinator.handleDeleteGroups(Set(groupId))
    println(s"DDBench oracle: DeleteGroups during the offset commit returned $deleteResult")

    val error = finishTxnOffsetCommit(coordinator, firstResponse)
    completeTransactionAndCompare(coordinator, error, "the group was deleted while the offset commit was in progress")
  }

  /** The coordinator unloads and reloads __consumer_offsets-0 while the transactional offset commit is in progress. */
  @Test
  def testDDBenchOracleCoordinatorReloadDuringTxnOffsetCommit(): Unit = {
    val coordinator = startCoordinator(epoch = 0)
    val firstResponse = sendTxnOffsetCommit(coordinator)
    requireInProgress(firstResponse)

    coordinator.onResignation(offsetsPartition.partition, OptionalInt.of(1))
    awaitCoordinatorStatus(coordinator, Errors.NOT_COORDINATOR)
    coordinator.onElection(offsetsPartition.partition, 2)
    awaitCoordinatorStatus(coordinator, Errors.NONE)

    val error = finishTxnOffsetCommit(coordinator, firstResponse)
    completeTransactionAndCompare(coordinator, error,
      "the coordinator unloaded and reloaded the offsets partition while the offset commit was in progress")
  }

  // ── helpers ──

  private def quietly(action: => Unit): Unit = {
    try action catch { case _: Throwable => () }
  }

  private def startCoordinator(epoch: Int): GroupCoordinator = {
    val coordinatorMetrics = new Metrics()
    val coordinator = GroupCoordinator(replicaManager.config, replicaManager, time, coordinatorMetrics)
    coordinators = (coordinator, coordinatorMetrics) :: coordinators
    coordinator.startup(() => 1, enableMetadataExpiration = false)
    coordinator.onElection(offsetsPartition.partition, epoch)
    awaitCoordinatorStatus(coordinator, Errors.NONE)
    coordinator
  }

  private def stopCoordinator(coordinator: GroupCoordinator): Unit = {
    coordinators.filter(_._1 eq coordinator).foreach { case (c, m) =>
      c.shutdown()
      m.close()
    }
    coordinators = coordinators.filterNot(_._1 eq coordinator)
  }

  private def awaitCoordinatorStatus(coordinator: GroupCoordinator, expected: Errors): Unit = {
    val deadline = System.currentTimeMillis() + waitMs
    var status = coordinator.handleFetchOffsets(groupId, requireStable = false, Some(Seq(inputPartition.topicPartition)))._1
    while (status != expected && System.currentTimeMillis() < deadline) {
      Thread.sleep(20)
      status = coordinator.handleFetchOffsets(groupId, requireStable = false, Some(Seq(inputPartition.topicPartition)))._1
    }
    assertEquals(expected, status, s"the coordinator did not reach status $expected for the offsets partition")
  }

  /** TxnOffsetCommit of `committedOffset`, as KafkaApis would hand it to the coordinator. */
  private def sendTxnOffsetCommit(coordinator: GroupCoordinator): AtomicReference[Option[Errors]] = {
    val response = new AtomicReference[Option[Errors]](None)
    coordinator.handleTxnCommitOffsets(groupId, transactionalId, producerId, producerEpoch,
      JoinGroupRequest.UNKNOWN_MEMBER_ID, None, JoinGroupRequest.UNKNOWN_GENERATION_ID,
      Map(inputPartition -> OffsetAndMetadata(committedOffset, "", time.milliseconds())),
      errors => response.set(Some(errors.getOrElse(inputPartition, Errors.UNKNOWN_SERVER_ERROR))),
      RequestLocal.NoCaching)
    response
  }

  /** The commit must be waiting for the transaction coordinator, i.e. still in progress. */
  private def requireInProgress(response: AtomicReference[Option[Errors]]): Unit = {
    assertTrue(verificationRequests.get > 0,
      "the transactional offset commit was not checked with the transaction coordinator although " +
        "transaction.partition.verification.enable=true")
    assertTrue(response.get.isEmpty,
      s"the offset commit was answered (${response.get}) before the transaction coordinator replied")
  }

  /** The transaction coordinator confirms every pending verification request. */
  private def answerVerifications(): Unit = {
    var callback = pendingVerifications.poll()
    while (callback != null) {
      callback(Map.empty[TopicPartition, Errors])
      callback = pendingVerifications.poll()
    }
  }

  private def awaitResponse(response: AtomicReference[Option[Errors]]): Errors = {
    val deadline = System.currentTimeMillis() + waitMs
    answerVerifications()
    while (response.get.isEmpty && System.currentTimeMillis() < deadline) {
      Thread.sleep(10)
      answerVerifications()
    }
    response.get.getOrElse(fail[Errors]("the TxnOffsetCommit request was never answered"))
  }

  /** Behaves like the producer: retries retriable errors, returns the final error. */
  private def finishTxnOffsetCommit(coordinator: GroupCoordinator, firstResponse: AtomicReference[Option[Errors]]): Errors = {
    var error = awaitResponse(firstResponse)
    var attempts = 1
    while (retriableErrors.contains(error) && attempts < 5) {
      println(s"DDBench oracle: TxnOffsetCommit attempt $attempts returned $error, retrying")
      attempts += 1
      awaitCoordinatorStatus(coordinator, Errors.NONE)
      error = awaitResponse(sendTxnOffsetCommit(coordinator))
    }
    println(s"DDBench oracle: TxnOffsetCommit final response after $attempts attempt(s): $error")
    assertTrue(!retriableErrors.contains(error), s"the offset commit still failed with $error after $attempts attempts")
    error
  }

  /** The transaction coordinator writes the COMMIT/ABORT marker and notifies the group coordinator. */
  private def completeTransaction(coordinator: GroupCoordinator, result: TransactionResult): Unit = {
    val markerType = if (result == TransactionResult.COMMIT) ControlRecordType.COMMIT else ControlRecordType.ABORT
    val marker = MemoryRecords.withEndTransactionMarker(time.milliseconds(), producerId, producerEpoch,
      new EndTransactionMarker(markerType, 0))
    val appendError = new AtomicReference[Option[Errors]](None)
    replicaManager.appendRecords(
      timeout = waitMs,
      requiredAcks = -1,
      internalTopicsAllowed = true,
      origin = AppendOrigin.COORDINATOR,
      entriesPerPartition = Map(offsetsPartition -> marker),
      responseCallback = statuses => appendError.set(statuses.get(offsetsPartition).map(_.error)))
    assertEquals(Some(Errors.NONE), appendError.get, s"writing the $result marker to $offsetsPartition failed")
    coordinator.scheduleHandleTxnCompletion(producerId, Seq(offsetsPartition), result)
  }

  /** Offset the coordinator serves for the input partition, once no transactional commit is pending for it. */
  private def servedOffset(coordinator: GroupCoordinator): Long = {
    val deadline = System.currentTimeMillis() + waitMs
    var fetched = coordinator.handleFetchOffsets(groupId, requireStable = true, Some(Seq(inputPartition.topicPartition)))
    def unstable = fetched._1 != Errors.NONE ||
      fetched._2.get(inputPartition.topicPartition).exists(_.error == Errors.UNSTABLE_OFFSET_COMMIT)
    while (unstable && System.currentTimeMillis() < deadline) {
      Thread.sleep(20)
      fetched = coordinator.handleFetchOffsets(groupId, requireStable = true, Some(Seq(inputPartition.topicPartition)))
    }
    assertEquals(Errors.NONE, fetched._1, "OffsetFetch failed")
    val data = fetched._2.getOrElse(inputPartition.topicPartition, fail[Nothing]("OffsetFetch returned no data for the input partition"))
    assertEquals(Errors.NONE, data.error, s"OffsetFetch for ${inputPartition.topicPartition} kept failing after the transaction completed")
    data.offset
  }

  private def completeTransactionAndCompare(coordinator: GroupCoordinator, commitError: Errors, event: String): Unit = {
    val result = if (commitError == Errors.NONE) TransactionResult.COMMIT else TransactionResult.ABORT
    completeTransaction(coordinator, result)
    val liveOffset = servedOffset(coordinator)

    // Failover: a new coordinator takes over and rebuilds the group state from __consumer_offsets.
    stopCoordinator(coordinator)
    val reloaded = startCoordinator(epoch = 10)
    val reloadedOffset = servedOffset(reloaded)
    stopCoordinator(reloaded)

    println(s"DDBench oracle: [$event] TxnOffsetCommit=$commitError, transaction $result, " +
      s"live coordinator serves $liveOffset, reloaded coordinator serves $reloadedOffset")

    assertEquals(reloadedOffset, liveOffset,
      s"[$event] after the transaction completed ($result), the coordinator serves offset $liveOffset for " +
        s"${inputPartition.topicPartition}, but a coordinator that reloads __consumer_offsets serves $reloadedOffset: " +
        "the coordinator's in-memory offsets differ from what was written to the log")
    val expected = if (result == TransactionResult.COMMIT) committedOffset else -1L
    val outcome = if (result == TransactionResult.COMMIT) "committed" else "aborted"
    assertEquals(expected, liveOffset,
      s"[$event] the offset commit returned $commitError and the transaction was $outcome, " +
        s"so offset $expected was expected for ${inputPartition.topicPartition}, but $liveOffset is served")
  }
}
