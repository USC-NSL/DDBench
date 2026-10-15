/*
 * DDBench oracle for kafka-14334-delayed-fetch-purgatory.
 *
 * Two brokers run in-process (ZooKeeper mode) with fetch from follower enabled:
 * each broker has its own broker.rack and the RackAwareReplicaSelector. A topic
 * with one partition is replicated on both brokers, broker 0 leading and broker 1
 * following, with min.insync.replicas=2.
 *
 * A consumer FetchRequest (minBytes=1, maxWait=30 s) is sent straight to the
 * FOLLOWER before anything is produced, so the follower has to hold it until data
 * arrives. One record is then produced to the leader with acks=all. The follower
 * must answer the waiting fetch, with that record, within 10 s of the record being
 * acknowledged, instead of when the fetch's maxWait expires. This is done twice,
 * the second time with a 15 s pause before producing, so that a follower that
 * answers waiting fetches after some fixed time (rather than when replicated data
 * arrives) cannot pass both rounds.
 *
 * An identical fetch sent to the LEADER serves as a control. When the follower has
 * not answered in time, the verdict is "bug present" only if the control was
 * answered with the record in time and a zero-wait fetch shows that the record was
 * already readable on the follower. Otherwise the run is inconclusive: the test
 * throws DDBenchOracleSetupException, which reproduce.sh reports as ERROR. Failing
 * to establish the cluster, the topic or a follower that serves consumer fetches
 * is inconclusive in the same way.
 *
 * Only public entry points are used: KafkaServer, the Admin and Producer clients,
 * and FetchRequests written to a socket. Nothing depends on how a fix is organised.
 */
package kafka.server

import java.io.{DataInputStream, DataOutputStream, File}
import java.net.{InetSocketAddress, Socket}
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets.UTF_8
import java.nio.file.Files
import java.time.Duration
import java.util.{Collections, Optional, Properties}
import java.util.concurrent.{CountDownLatch, ExecutionException, TimeUnit}
import java.util.concurrent.atomic.AtomicReference

import org.apache.kafka.clients.admin.{Admin, AdminClientConfig, NewTopic}
import org.apache.kafka.clients.producer.{KafkaProducer, ProducerConfig, ProducerRecord}
import org.apache.kafka.common.{TopicPartition, Uuid}
import org.apache.kafka.common.errors.TopicExistsException
import org.apache.kafka.common.network.ListenerName
import org.apache.kafka.common.protocol.{ApiKeys, Errors}
import org.apache.kafka.common.requests.{AbstractResponse, FetchRequest, FetchResponse, RequestHeader}
import org.apache.kafka.common.security.auth.SecurityProtocol
import org.apache.kafka.common.serialization.ByteArraySerializer
import org.apache.kafka.common.utils.{Exit, Time, Utils}
import org.apache.zookeeper.server.{NIOServerCnxnFactory, ZooKeeperServer}
import org.junit.jupiter.api.Assertions.fail
import org.junit.jupiter.api.{AfterEach, BeforeEach, Test, Timeout}

import scala.jdk.CollectionConverters._

/** The oracle could not establish its preconditions; the run is inconclusive (ERROR). */
class DDBenchOracleSetupException(message: String, cause: Throwable = null) extends RuntimeException(message, cause)

@Timeout(420)
class DDBenchOracleFetchFromFollowerTest {

  private val leaderId = 0
  private val followerId = 1
  private val topic = "ddbench-oracle-topic"
  private val partition = new TopicPartition(topic, 0)
  private val fetchVersion: Short = ApiKeys.FETCH.latestVersion()

  private val maxWaitMs = 30000         // maxWait of the consumer fetches that wait for data
  private val promptMs = 10000L         // the follower must answer within this time after the ack
  private val firstPauseMs = 1500L      // round 1: time between sending the fetch and producing
  private val secondPauseMs = 15000L    // round 2: longer than round 1's pause + promptMs
  private val setupTimeoutMs = 60000L

  private var tempDirs: List[File] = Nil
  private var zkServer: ZooKeeperServer = _
  private var zkFactory: NIOServerCnxnFactory = _
  private var brokers: Map[Int, KafkaServer] = Map.empty
  private var admin: Admin = _
  private var producer: KafkaProducer[Array[Byte], Array[Byte]] = _
  private var topicId: Uuid = Uuid.ZERO_UUID

  @BeforeEach
  def setUp(): Unit = {
    // A broker that calls Exit must not take the test JVM down with it.
    Exit.setExitProcedure((code: Int, message: String) =>
      throw new IllegalStateException(s"a broker called Exit.exit($code): $message"))
    Exit.setHaltProcedure((code: Int, message: String) =>
      throw new IllegalStateException(s"a broker called Exit.halt($code): $message"))
    System.setProperty("zookeeper.forceSync", "no")

    try {
      zkServer = new ZooKeeperServer(tempDir("zk-snapshots"), tempDir("zk-log"), 800)
      zkFactory = new NIOServerCnxnFactory()
      zkFactory.configure(new InetSocketAddress("127.0.0.1", 0), 0)
      zkFactory.startup(zkServer)
    } catch {
      case e: Exception => throw new DDBenchOracleSetupException(s"setup: ZooKeeper did not start: $e", e)
    }
    val zkConnect = s"127.0.0.1:${zkServer.getClientPort}"

    // The brokers are the code under test: if they do not start, that is a failure.
    for (id <- Seq(leaderId, followerId)) {
      val props = new Properties()
      props.put("broker.id", id.toString)
      props.put("zookeeper.connect", zkConnect)
      props.put("listeners", "PLAINTEXT://localhost:0")
      props.put("log.dirs", tempDir(s"broker-$id").getAbsolutePath)
      props.put("broker.rack", rack(id))
      props.put("replica.selector.class", "org.apache.kafka.common.replica.RackAwareReplicaSelector")
      props.put("auto.create.topics.enable", "false")
      props.put("controlled.shutdown.enable", "false")
      props.put("num.partitions", "1")
      props.put("offsets.topic.replication.factor", "1")
      props.put("transaction.state.log.replication.factor", "1")
      props.put("transaction.state.log.min.isr", "1")
      props.put("group.initial.rebalance.delay.ms", "0")
      try {
        val broker = new KafkaServer(KafkaConfig.fromProps(props), Time.SYSTEM, Some(s"ddbench-oracle-broker-$id"))
        brokers += id -> broker
        broker.startup()
      } catch {
        case e: Throwable => fail(s"broker $id did not start: $e", e)
      }
    }
  }

  @AfterEach
  def tearDown(): Unit = {
    if (producer != null) quietly(producer.close(Duration.ofSeconds(5)))
    if (admin != null) quietly(admin.close(Duration.ofSeconds(5)))
    brokers.values.foreach(broker => quietly(broker.shutdown()))
    brokers.values.foreach(broker => quietly(broker.awaitShutdown()))
    if (zkFactory != null) quietly(zkFactory.shutdown())
    if (zkServer != null) quietly(zkServer.shutdown())
    tempDirs.foreach(dir => quietly(Utils.delete(dir)))
    Exit.resetExitProcedure()
    Exit.resetHaltProcedure()
  }

  @Test
  def testDDBenchOracleFollowerAnswersWaitingFetchOnReplication(): Unit = {
    prepareTopic()
    val nextOffset = round(1, fetchOffset = 0L, pauseMs = firstPauseMs)
    round(2, fetchOffset = nextOffset, pauseMs = secondPauseMs)
  }

  // ── the measurement ──

  /**
   * Sends a waiting consumer fetch to the follower (and, as a control, to the
   * leader), produces one record after `pauseMs`, and checks that the follower
   * answers promptly with it. Returns the offset after the produced record.
   */
  private def round(n: Int, fetchOffset: Long, pauseMs: Long): Long = {
    val value = s"ddbench-oracle-record-$n-${System.nanoTime()}"
    val onFollower = new WaitingFetch(followerId, fetchOffset)
    val onLeader = new WaitingFetch(leaderId, fetchOffset)
    try {
      Thread.sleep(pauseMs)

      onFollower.answer.foreach(answer => fail(
        s"round $n: the follower answered the consumer's fetch ${ms(answer.receivedNanos - onFollower.sentNanos)} ms " +
          s"after it was sent, before any record was produced ($answer); with minBytes=1 it has to wait for data, " +
          s"up to its maxWait of $maxWaitMs ms"))

      val produceNanos = System.nanoTime()
      val metadata = try {
        producer.send(new ProducerRecord[Array[Byte], Array[Byte]](topic, 0, null, value.getBytes(UTF_8))).get(30, TimeUnit.SECONDS)
      } catch {
        case e: Exception => throw new DDBenchOracleSetupException(
          s"round $n: the record was not acknowledged by the leader (acks=all, min.insync.replicas=2) within 30 s: $e", e)
      }
      val ackNanos = System.nanoTime()
      val deadlineNanos = ackNanos + promptMs * 1000000L

      // An answer that arrives after the deadline counts as not answered in time.
      onFollower.awaitAnswer(deadlineNanos).filter(_.receivedNanos <= deadlineNanos) match {
        case Some(answer) if answer.receivedNanos < produceNanos =>
          fail(s"round $n: the follower answered the consumer's fetch before any record was produced ($answer); " +
            s"with minBytes=1 it has to wait for data, up to its maxWait of $maxWaitMs ms")

        case Some(answer) if answer.contains(value) =>
          val control = onLeader.awaitAnswer(deadlineNanos)
          println(s"DDBench oracle: round $n: the follower answered the waiting fetch with the record " +
            s"${ms(answer.receivedNanos - ackNanos)} ms after the record was acknowledged " +
            s"(${ms(answer.receivedNanos - onFollower.sentNanos)} ms after the fetch was sent; maxWait $maxWaitMs ms) " +
            s"[control: the leader answered ${describeAfter(control, ackNanos)}]")
          metadata.offset + 1

        case Some(answer) =>
          fail(s"round $n: the follower answered the waiting fetch ${ms(answer.receivedNanos - ackNanos)} ms after the " +
            s"record was acknowledged, but without that record ($answer)")

        case None if onFollower.readFailure.isDefined =>
          fail(s"round $n: the follower closed the connection or sent an unreadable answer to the waiting fetch: " +
            onFollower.readFailure.get)

        case None =>
          // Not answered in time. Only call it the bug if the setup demonstrably allowed a prompt answer.
          val control = onLeader.answer
          if (!control.exists(_.contains(value)))
            throw new DDBenchOracleSetupException(
              s"round $n: the follower did not answer the waiting fetch within $promptMs ms of the ack, but the leader " +
                s"did not answer its own waiting fetch with the record in that time either " +
                s"(${control.getOrElse(onLeader.readFailure.getOrElse("no answer"))}): the environment is too slow to judge")
          val probe = try fetchNow(followerId, fetchOffset) catch {
            case e: Exception => throw new DDBenchOracleSetupException(s"round $n: zero-wait fetch from the follower failed: $e", e)
          }
          if (!probe.contains(value))
            throw new DDBenchOracleSetupException(
              s"round $n: $promptMs ms after the record was acknowledged it was still not readable on the follower " +
                s"(zero-wait fetch: $probe): replication did not complete in time, so the follower's delay is inconclusive")

          val eventual = onFollower.awaitAnswer(onFollower.sentNanos + (maxWaitMs + 15000L) * 1000000L)
          val outcome = eventual match {
            case Some(answer) =>
              s"answered it only ${ms(answer.receivedNanos - onFollower.sentNanos)} ms after it was sent " +
                s"(${ms(answer.receivedNanos - ackNanos)} ms after the ack; maxWait $maxWaitMs ms): $answer"
            case None =>
              s"had not answered it ${maxWaitMs + 15000} ms after it was sent" +
                onFollower.readFailure.map(t => s" ($t)").getOrElse("")
          }
          println(s"DDBench oracle: round $n: the follower $outcome " +
            s"[control: the leader answered ${describeAfter(control, ackNanos)}; " +
            s"zero-wait fetch from the follower ${promptMs / 1000} s after the ack: $probe]")
          fail(s"round $n: a consumer fetch waiting on the follower was not answered within $promptMs ms after the " +
            s"record was acknowledged, although the record was readable on the follower by then (zero-wait fetch: " +
            s"$probe) and the leader answered the same waiting fetch ${describeAfter(control, ackNanos)}; " +
            s"the follower $outcome")
      }
    } finally {
      onFollower.close()
      onLeader.close()
    }
  }

  // ── setup ──

  private def prepareTopic(): Unit = {
    val bootstrap = Seq(leaderId, followerId).map(id => s"localhost:${port(id)}").mkString(",")
    val adminProps = new Properties()
    adminProps.put(AdminClientConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrap)
    adminProps.put(AdminClientConfig.REQUEST_TIMEOUT_MS_CONFIG, "20000")
    admin = Admin.create(adminProps)

    val assignment = Map[Integer, java.util.List[Integer]](
      Int.box(0) -> List(Int.box(leaderId), Int.box(followerId)).asJava).asJava
    val newTopic = new NewTopic(topic, assignment).configs(Map("min.insync.replicas" -> "2").asJava)
    awaitSetup(s"create topic $topic") {
      try {
        admin.createTopics(Collections.singleton(newTopic)).all().get(30, TimeUnit.SECONDS)
        Right(())
      } catch {
        case e: ExecutionException if e.getCause.isInstanceOf[TopicExistsException] => Right(()) // an earlier attempt
      }
    }

    // Broker 0 leads and broker 1 is in sync.
    topicId = awaitSetup(s"broker $leaderId leading $partition with ISR {$leaderId,$followerId}") {
      val description = admin.describeTopics(Collections.singleton(topic)).allTopicNames().get(10, TimeUnit.SECONDS).get(topic)
      val info = description.partitions().get(0)
      val leader = Option(info.leader()).map(_.id).getOrElse(-1)
      val isr = info.isr().asScala.map(_.id).toSet
      if (leader == leaderId && isr == Set(leaderId, followerId) && description.topicId() != Uuid.ZERO_UUID)
        Right(description.topicId())
      else Left(s"leader $leader, ISR $isr")
    }

    // Both brokers serve consumer fetches for the partition themselves (the follower
    // does not redirect the consumer), with the request version used below.
    for (id <- Seq(followerId, leaderId)) {
      awaitSetup(s"broker $id serving consumer fetches for $partition (fetch v$fetchVersion)") {
        val answer = fetchNow(id, 0L)
        if (answer.ok) Right(()) else Left(answer.toString)
      }
    }

    val producerProps = new Properties()
    producerProps.put(ProducerConfig.BOOTSTRAP_SERVERS_CONFIG, bootstrap)
    producerProps.put(ProducerConfig.ACKS_CONFIG, "all")
    producerProps.put(ProducerConfig.LINGER_MS_CONFIG, "0")
    producerProps.put(ProducerConfig.REQUEST_TIMEOUT_MS_CONFIG, "20000")
    producerProps.put(ProducerConfig.DELIVERY_TIMEOUT_MS_CONFIG, "30000")
    producerProps.put(ProducerConfig.MAX_BLOCK_MS_CONFIG, "30000")
    producer = new KafkaProducer[Array[Byte], Array[Byte]](producerProps, new ByteArraySerializer, new ByteArraySerializer)
    awaitSetup(s"producer metadata for $topic") {
      if (producer.partitionsFor(topic).size == 1) Right(()) else Left("no partition metadata")
    }
    println(s"DDBench oracle: cluster ready: broker $leaderId leads $partition, broker $followerId follows; " +
      s"consumer fetches use FetchRequest v$fetchVersion")
  }

  // ── fetching ──

  /** What a broker answered to a consumer fetch for the partition. */
  private case class FetchAnswer(error: Errors, partitionError: Option[Errors], highWatermark: Long,
                                 preferredReadReplica: Int, values: Seq[String], receivedNanos: Long) {
    def ok: Boolean = error == Errors.NONE && partitionError.contains(Errors.NONE) && preferredReadReplica < 0
    def contains(value: String): Boolean = ok && values.contains(value)
    override def toString: String =
      s"error ${error.name}, partition error ${partitionError.map(_.name).getOrElse("(partition missing)")}, " +
        s"high watermark $highWatermark, preferred read replica $preferredReadReplica, ${values.size} record(s)"
  }

  private def fetchRequest(offset: Long, maxWait: Int, minBytes: Int, rackId: String): FetchRequest = {
    val partitions = new java.util.LinkedHashMap[TopicPartition, FetchRequest.PartitionData]()
    partitions.put(partition, new FetchRequest.PartitionData(topicId, offset, -1L, 1024 * 1024, Optional.empty[Integer]()))
    FetchRequest.Builder.forConsumer(fetchVersion, maxWait, minBytes, partitions)
      .rackId(rackId)
      .setMaxBytes(1024 * 1024)
      .build(fetchVersion)
  }

  /** A consumer connection to one broker, speaking the Kafka protocol on a plain socket. */
  private class BrokerConnection(brokerId: Int) extends AutoCloseable {
    private val socket = new Socket()
    socket.connect(new InetSocketAddress("localhost", port(brokerId)), 10000)
    socket.setTcpNoDelay(true)
    socket.setSoTimeout(maxWaitMs + 30000)
    private val out = new DataOutputStream(socket.getOutputStream)
    private val in = new DataInputStream(socket.getInputStream)

    def send(request: FetchRequest): RequestHeader = {
      val header = new RequestHeader(ApiKeys.FETCH, request.version, "ddbench-oracle-consumer", 1)
      val bytes = Utils.toArray(request.serializeWithHeader(header))
      out.writeInt(bytes.length)
      out.write(bytes)
      out.flush()
      header
    }

    def receive(header: RequestHeader): FetchAnswer = {
      val bytes = new Array[Byte](in.readInt())
      in.readFully(bytes)
      val receivedNanos = System.nanoTime()
      val response = AbstractResponse.parseResponse(ByteBuffer.wrap(bytes), header).asInstanceOf[FetchResponse]
      val data = Option(response.responseData(Map(topicId -> topic).asJava, header.apiVersion).get(partition))
      FetchAnswer(
        error = response.error,
        partitionError = data.map(d => Errors.forCode(d.errorCode)),
        highWatermark = data.map(_.highWatermark).getOrElse(-1L),
        preferredReadReplica = data.map(_.preferredReadReplica).getOrElse(-1),
        values = data.toSeq.flatMap(d => FetchResponse.recordsOrFail(d).records().asScala.map { record =>
          if (record.hasValue) new String(Utils.toArray(record.value()), UTF_8) else ""
        }),
        receivedNanos = receivedNanos)
    }

    override def close(): Unit = socket.close()
  }

  /** A fetch that does not wait: what the broker can serve right now. */
  private def fetchNow(brokerId: Int, offset: Long): FetchAnswer = {
    val connection = new BrokerConnection(brokerId)
    try connection.receive(connection.send(fetchRequest(offset, maxWait = 0, minBytes = 0, rack(brokerId))))
    finally connection.close()
  }

  /** A consumer fetch (minBytes=1, maxWait=maxWaitMs) sent now; its answer is read in the background. */
  private class WaitingFetch(brokerId: Int, offset: Long) {
    private val connection = new BrokerConnection(brokerId)
    private val result = new AtomicReference[Either[Throwable, FetchAnswer]]()
    private val done = new CountDownLatch(1)
    val sentNanos: Long = System.nanoTime()
    private val header = connection.send(fetchRequest(offset, maxWaitMs, minBytes = 1, rack(brokerId)))
    private val reader = new Thread(() => {
      try result.set(Right(connection.receive(header)))
      catch { case t: Throwable => result.set(Left(t)) }
      finally done.countDown()
    }, s"ddbench-oracle-waiting-fetch-$brokerId")
    reader.setDaemon(true)
    reader.start()

    def answer: Option[FetchAnswer] = Option(result.get).flatMap(_.toOption)
    def readFailure: Option[Throwable] = Option(result.get).flatMap(_.left.toOption)
    def awaitAnswer(untilNanos: Long): Option[FetchAnswer] = {
      val waitNanos = untilNanos - System.nanoTime()
      if (waitNanos > 0) done.await(waitNanos, TimeUnit.NANOSECONDS)
      answer
    }
    def close(): Unit = quietly(connection.close())
  }

  // ── helpers ──

  private def rack(brokerId: Int): String = s"ddbench-rack-$brokerId"

  private def port(brokerId: Int): Int =
    brokers(brokerId).boundPort(ListenerName.forSecurityProtocol(SecurityProtocol.PLAINTEXT))

  private def ms(nanos: Long): Long = nanos / 1000000L

  private def describeAfter(answer: Option[FetchAnswer], ackNanos: Long): String = answer match {
    case Some(a) => s"${ms(a.receivedNanos - ackNanos)} ms after the ack ($a)"
    case None => "not yet"
  }

  private def tempDir(name: String): File = {
    val dir = Files.createTempDirectory(s"ddbench-oracle-$name-").toFile
    tempDirs = dir :: tempDirs
    dir
  }

  private def quietly(action: => Unit): Unit = {
    try action catch { case _: Throwable => () }
  }

  /** Retries `attempt` until it returns Right; a timeout is a setup problem (ERROR), not a verdict. */
  private def awaitSetup[T](what: String)(attempt: => Either[String, T]): T = {
    val deadline = System.currentTimeMillis() + setupTimeoutMs
    var last: Either[String, T] = Left("no attempt")
    while (System.currentTimeMillis() < deadline) {
      last = try attempt catch { case e: Exception => Left(e.toString) }
      last match {
        case Right(value) => return value
        case Left(_) => Thread.sleep(100)
      }
    }
    throw new DDBenchOracleSetupException(
      s"setup: $what not reached within ${setupTimeoutMs / 1000} s (last: ${last.left.getOrElse("")})")
  }
}
