#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"

log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }

cat <<'EOF'
RocketMQ 5.0 Cloud-Native Architecture
|--------+------------------------------------------------------------------------|
| Server | RocketMQ Component Roles                                               |
|--------+------------------------------------------------------------------------|
| rmq01  | NameSrv-1, Proxy-1, DLedgerCtrl-1, Broker-A (Master)                   |
| rmq02  | NameSrv-2, Proxy-2, DLedgerCtrl-2, Broker-B (Master), Broker-A-Replica |
| rmq03  | NameSrv-3, Proxy-3, DLedgerCtrl-3, Broker-B-Replica                    |
|--------+------------------------------------------------------------------------|
                     [ Producer Client ]
                        /          \
            (Writes Msg 1, 3, 5)  (Writes Msg 2, 4, 6)
                      /              \
                     v                v
             ⚡ [ Broker-A ]     ⚡ [ Broker-B ]
             (Data Shard 1)      (Data Shard 2)
EOF
CLUSTER=${CLUSTER:-DefaultCluster}
declare -A MAP_NODES=(
    [rmq01]=192.168.168.21
    [rmq02]=192.168.168.22
    [rmq03]=192.168.168.23
    )
peerids=()
for node in ${!MAP_NODES[@]}; do
    peerids+=("${node}-${MAP_NODES[${node}]}:9877")
done
namesrvAddr=$(IFS=';';echo -n "${MAP_NODES[*]}" | sed 's/;/:9876;/g';echo ":9876")
controllerAddr=$(IFS=';';echo -n "${MAP_NODES[*]}" | sed 's/;/:9877;/g';echo ":9877")
log "0. Controller Configurations (Raft Consensus), ctrl can in namesrv plugin mode, samp: conf/controller/cluster-3n-namesrv-plugin"
for node in ${!MAP_NODES[@]}; do
    log "# ${node}: (rocketmq/conf/controller.conf)"
    cat <<EOF
controllerDLegerGroup = group1
controllerDLegerPeers=$(IFS=';';echo "${peerids[*]}";)
controllerDLegerSelfId=${node}
EOF
done
log "1 NameServer Configuration (Stateless Layer)"
log "# On all nodes (rocketmq/conf/namesrv.conf)"
cat <<EOF
listenPort=9876
useEpollNativeSelector=true
EOF
log "2. Proxy Configuration (Stateless Layer)"
log "# On all nodes (rocketmq/conf/rmq-proxy.json)"
cat <<EOF
{
  "proxyMode":"CLUSTER",
  "rocketMQClusterName": "${CLUSTER}",
  "grpcServerPort": 8081,
  "remotingListenPort": 8080,
  "enableGrpcEpoll":true
}
EOF

log "3. Broker Configuration (M/S broker-a & broker-b)"
log "M. Broker Master-A Configuration"
log "# (rocketmq/conf/broker-a.conf)"
cat <<EOF
# autoCreateTopicEnable=true
# defaultTopicQueueNums=16
# useEpollNativeSelector=true
# storePathRootDir=\$HOME/store/
# storePathCommitLog=\$HOME/store/commitlog/
# mappedFileSizeCommitLog=$((1024*1024*1024))
# namesrvAddr=${namesrvAddr}
# listenPort=10911
brokerClusterName=${CLUSTER}
brokerName=broker-a
brokerId=0
deleteWhen=04
fileReservedTime=48
enableControllerMode=true
controllerAddr=${controllerAddr}
syncBrokerMetadataPeriod=5000
brokerRole=SYNC_MASTER
flushDiskType=ASYNC_FLUSH
EOF

log "R. Broker-A Replica Configuration"
log "# (rocketmq/conf/broker-a-replica.conf)"
cat <<EOF
brokerClusterName=${CLUSTER}
brokerName=broker-a
brokerId=1
deleteWhen=04
fileReservedTime=48
enableControllerMode=true
controllerAddr=${controllerAddr}
syncBrokerMetadataPeriod=5000
brokerRole=SLAVE
flushDiskType=ASYNC_FLUSH
EOF

log "4. service files"
log "# (/etc/rocketmq.conf)"
cat <<EOF >rocketmq.conf
ROCKETMQ_HOME=/opt/rocketmq-all-5.3.0-bin-release
NAMESRV_ADDR=${namesrvAddr}
BROKER_CONF=conf/2m-2s-sync/broker-b.properties
DASHBOARD_PORT=18080
JAVA_OPT="-Djava.net.preferIPv4Stack=true -Djava.security.egd=file:/dev/urandom"
EOF
log "# (/etc/systemd/system/rocketmq-namesrv.service)"
cat <<'EOF' >rocketmq-namesrv.service
[Unit]
Description=RocketMQ NameServer
After=network.target

[Service]
Type=simple
User=rocketmq
Group=rocketmq
Environment="ROCKETMQ_HOME=/opt/rocketmq"
EnvironmentFile=-/etc/rocketmq.conf
ExecStart=/bin/sh -c "cd ${ROCKETMQ_HOME} && ./bin/mqnamesrv start -c conf/namesrv.conf >/dev/null"
ExecStop=/bin/sh -c "cd ${ROCKETMQ_HOME} && ./bin/mqshutdown namesrv"
Restart=on-failure
RestartSec=5s
LimitNOFILE=655360

[Install]
WantedBy=multi-user.target
EOF

log "# (/etc/systemd/system/rocketmq-controller.service)"
cat <<'EOF' >rocketmq-controller.service
[Unit]
Description=RocketMQ Controller
After=network.target rocketmq-namesrv.service

[Service]
Type=simple
User=rocketmq
Group=rocketmq
Environment="ROCKETMQ_HOME=/opt/rocketmq"
EnvironmentFile=-/etc/rocketmq.conf
ExecStart=/bin/sh -c "cd ${ROCKETMQ_HOME} && ./bin/mqcontroller -n ${NAMESRV_ADDR} -c conf/controller.conf >/dev/null"
ExecStop=/bin/sh -c "cd ${ROCKETMQ_HOME} && ./bin/mqshutdown controller"
Restart=on-failure
RestartSec=5s
EOF

log "# (/etc/systemd/system/rocketmq-broker.service)"
log "# nofile   1024000"
log "# memlock  unlimited"
log "# mount    noatime"
log "# JAVA_OPT=-XX:+UseNUMA"
cat <<'EOF' >rocketmq-broker.service
[Unit]
Description=RocketMQ Broker
After=network.target rocketmq-namesrv.service

[Service]
Type=simple
User=rocketmq
Group=rocketmq
Environment="ROCKETMQ_HOME=/opt/rocketmq"
Environment="NAMESRV_ADDR=127.0.0.1:9876"
Environment="BROKER_CONF=conf/broker.conf"
EnvironmentFile=-/etc/rocketmq.conf
ExecStart=/bin/sh -c "cd ${ROCKETMQ_HOME} && ./bin/mqbroker -n ${NAMESRV_ADDR} -c ${BROKER_CONF} >/dev/null"
ExecStop=/bin/sh -c "cd ${ROCKETMQ_HOME} && ./bin/mqshutdown broker"
Restart=on-failure
RestartSec=5s
LimitNOFILE=655360
LimitMEMLOCK=infinity
EOF

log "# (/etc/systemd/system/rocketmq-proxy.service)"
cat <<'EOF' >rocketmq-proxy.service
[Unit]
Description=RocketMQ Proxy
After=network.target rocketmq-namesrv.service

[Service]
Type=simple
User=rocketmq
Group=rocketmq
Environment="ROCKETMQ_HOME=/opt/rocketmq"
Environment="NAMESRV_ADDR=127.0.0.1:9876"
EnvironmentFile=-/etc/rocketmq.conf
ExecStart=/bin/sh -c "cd ${ROCKETMQ_HOME} && ./bin/mqproxy -n ${NAMESRV_ADDR} -pc conf/rmq-proxy.json >/dev/null"
ExecStop=/bin/sh -c "cd ${ROCKETMQ_HOME} && ./bin/mqshutdown proxy"
Restart=on-failure
RestartSec=5s
LimitNOFILE=655360

[Install]
WantedBy=multi-user.target
EOF

log "# (/etc/systemd/system/rocketmq-dashboard.service)"
cat <<'EOF' >rocketmq-dashboard.service
[Unit]
Description=RocketMQ Dashboard
After=network.target

[Service]
Type=simple
User=rocketmq
Group=rocketmq
Environment="ROCKETMQ_HOME=/opt/rocketmq"
Environment="DASHBOARD_PORT=8080"
EnvironmentFile=-/etc/rocketmq.conf
ExecStart=/bin/sh -c "java -jar ${ROCKETMQ_HOME}/rocketmq-dashboard-2.0.0.jar --server.port=${DASHBOARD_PORT} >/dev/null"
Restart=on-failure
RestartSec=5s
LimitNOFILE=655360

[Install]
WantedBy=multi-user.target
EOF
log "5. ====================================================================="
log "# Verify Check Cluster Topology:"
log "mqadmin clusterList -n ip:9876"
log "# Verify Check Controller Status:"
log "mqadmin getControllerMetaData -a ip:9877"
log "# Get/Set consumer mode(pull/pop):"
log "export NAMESRV_ADDR=localhost:9876"
log "mqadmin consumerProgress"
log "mqadmin topicList"
log "mqadmin setConsumeMode -c ${CLUSTER} -g [Consumer_Grp] -t [Topic] -m POP -q 8"
log "mqadmin resetOffsetByTime -g sg-event-bus-64 -s '2026-08-06#00:00:00:000' -t tp-event-bus-64"
log 'mqadmin updateConsumerGroup -c DefaultCluster -g grp -r 16 -s "1s 5s 10s 30s 1m 2m 3m 4m 5m 6m 7m 8m 9m 10m 20m 30m 1h 2h"'

cat <<'EOF'
USER=rocketmq
GROUP=rocketmq
getent group  ${GROUP} >/dev/null || groupadd ${GROUP} || :
getent passwd ${USER} >/dev/null || useradd -g ${GROUP} --create-home --home-dir /home/${USER}/ --shell /bin/bash ${USER} 2> /dev/null || :
echo "export PATH=$PATH:/opt/rocketmq/bin" >> /home/${USER}/.bashrc
EOF
cat <<EOF
echo "export NAMESRV_ADDR=\"${namesrvAddr}\"" >> /home/\${USER}/.bashrc

# Verify it started
jps | grep NamesrvStartup
jps | grep ControllerStartup
jps | grep ProxyStartup
# # startup seq
# [All Servers: NameServers] ==> [Server 1 & 2: Masters] ==> [Server 3 & 4: Slaves]
# # stop seq
# Server 1 & 2: Masters] ==> [Server 3 & 4: Slaves] ==> [All Servers: NameServers]
EOF

log 'shutdown script'
cat <<'EOF'
!/bin/bash
MASTERS=("192.168.1.10" "192.168.1.11")
SLAVES=("192.168.1.12" "192.168.1.13")
ALL_NODES=("192.168.1.10" "192.168.1.11" "192.168.1.12" "192.168.1.13")

# Define RocketMQ installation path
ROCKETMQ_HOME=/opt/rocketmq-all-5.3.0-bin-release

echo "Stopping Master Brokers..."
for node in "${MASTERS[@]}"; do
    ssh "$node" "sh ${ROCKETMQ_HOME}/bin/mqshutdown broker"
done

echo "Waiting for data sync to settle..."
sleep 30

echo "Stopping Slave Brokers..."
for node in "${SLAVES[@]}"; do
    ssh "$node" "sh ${ROCKETMQ_HOME}/bin/mqshutdown broker"
done

echo "Stopping NameServers..."
for node in "${ALL_NODES[@]}"; do
    ssh "$node" "sh ${ROCKETMQ_HOME}/bin/mqshutdown namesrv "
done

echo "2M2S Cluster shutdown complete."
EOF

log 'demo programs'
cat <<'EOF'
javac -cp rocketmq-client-java-5.2.1.jar:slf4j-api-2.0.3.jar MyConsumer.java  MyProducer.java

java -cp ./:rocketmq-client-java-5.2.1.jar:slf4j-api-2.0.3.jar:slf4j-simple-2.0.3.jar \
    -Drocketmq.endpoint="192.168.168.101:8081" \
    -Drocketmq.topic="MyTopicName" \
    -Drocketmq.group="MyConsumerGroupName" \
    -Drocketmq.tag="myTag" \
    -Drocketmq.rtimeout=3 \
    MyProducer

java -cp ./:rocketmq-client-java-5.2.1.jar:slf4j-api-2.0.3.jar:slf4j-simple-2.0.3.jar \
    -Drocketmq.endpoint="192.168.168.101:8081" \
    -Drocketmq.topic="MyTopicName" \
    -Drocketmq.group="MyConsumerGroupName" \
    -Drocketmq.tag="myTag" \
    -Drocketmq.threads=20 \
    -Drocketmq.rtimeout=3 \
    -Dtest.sleep=6000 \
    -Dtask.async=0 \
    MyConsumer

# # MyProducer.java
import org.apache.rocketmq.client.apis.ClientConfiguration;
import org.apache.rocketmq.client.apis.ClientConfigurationBuilder;
import org.apache.rocketmq.client.apis.ClientServiceProvider;
import org.apache.rocketmq.client.apis.message.Message;
import org.apache.rocketmq.client.apis.producer.Producer;
import org.apache.rocketmq.client.apis.producer.SendReceipt;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class MyProducer {
    private static final Logger log = LoggerFactory.getLogger(MyProducer.class);
    private static final String ENDPOINT = System.getProperty("rocketmq.endpoint", "192.168.168.101:8081");
    private static final String FIFO_TOPIC = System.getProperty("rocketmq.topic", "MyTopicName");
    private static final String CONSUMER_GROUP = System.getProperty("rocketmq.group", "MyConsumerGroupName");
    private static final String TAG = System.getProperty("rocketmq.tag", "myTag");
    private static void sendLifecycleEvent(ClientServiceProvider provider, Producer producer, String messageGroupKey, String payload) {
        try {
            byte[] body = payload.getBytes(java.nio.charset.StandardCharsets.UTF_8);
            Message message = provider.newMessageBuilder()
                .setTopic(FIFO_TOPIC)
                .setTag(TAG)
                .setKeys(messageGroupKey)
                .setMessageGroup(messageGroupKey)
                .setBody(body)
                .build();
            SendReceipt sendReceipt = producer.send(message);
            log.info("[Send Success] Payload: '{}' mapped to Message Group: {}. MsgID: {}", payload, messageGroupKey, sendReceipt.getMessageId());
        } catch (Exception e) {
            log.error("Failed to send message sequence for group: {}", messageGroupKey, e);
        }
    }
    public static void main(String[] args) {
        final ClientServiceProvider provider = ClientServiceProvider.loadService();
        ClientConfiguration clientConfiguration = ClientConfiguration.newBuilder()
            .setEndpoints(ENDPOINT)
            .setRequestTimeout(java.time.Duration.ofSeconds(Long.parseLong(System.getProperty("rocketmq.rtimeout", "3"))))
            .build();
        try {
            Producer producer = provider.newProducerBuilder()
                .setClientConfiguration(clientConfiguration)
                .setTopics(FIFO_TOPIC)
                .build();
            log.info("Producer successfully started.");
            for (int i = 0; i < 10000; i++) {
                java.util.UUID uuid = java.util.UUID.randomUUID();
                sendLifecycleEvent(provider, producer, uuid.toString(), "payload info");
            }
        } catch (Exception e) {
            log.error("Error occurred during FIFO demo execution", e);
        }
    }
}
# # MyConsumer.java
import org.apache.rocketmq.client.apis.ClientConfiguration;
import org.apache.rocketmq.client.apis.ClientConfigurationBuilder;
import org.apache.rocketmq.client.apis.ClientServiceProvider;
import org.apache.rocketmq.client.apis.consumer.ConsumeResult;
import org.apache.rocketmq.client.apis.consumer.FilterExpression;
import org.apache.rocketmq.client.apis.consumer.FilterExpressionType;
import org.apache.rocketmq.client.apis.consumer.MessageListener;
import org.apache.rocketmq.client.apis.consumer.PushConsumer;
import org.apache.rocketmq.client.apis.message.MessageView;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

class RocketMQMultiTopicListener implements MessageListener {
    private static final Logger log = LoggerFactory.getLogger(RocketMQMultiTopicListener.class);
    private static final int mysleep = Integer.getInteger("test.sleep", 1000);
    private static void sleep(int ms) {
        try { Thread.sleep(ms); } catch (InterruptedException e) {}
    }
    private static void myTask(String payload) {
        log.info("message payload：{}", payload);
        sleep(mysleep);
        log.info("task complete!");
    }
    public ConsumeResult consume(MessageView messageView) {
        String messageId = messageView.getMessageId().toString();
        int deliveryAttempt = messageView.getDeliveryAttempt();
        try {
            if (deliveryAttempt > 1) {
                log.error("deliveryAttempt {}：{}, sleep={}", deliveryAttempt, messageView.toString(), mysleep);
            }
            String message = java.nio.charset.StandardCharsets.UTF_8.decode(messageView.getBody()).toString();
            if(Integer.getInteger("task.async", 0) == 0) {
                myTask(message);
            } else {
                java.util.concurrent.CompletableFuture.runAsync(() -> { myTask(message); });
            }
        } finally {
            log.info("complete: {}", messageId);
        }
        return ConsumeResult.SUCCESS;
    }
}
public class MyConsumer {
    private static final Logger log = LoggerFactory.getLogger(MyConsumer.class);
    private static final String ENDPOINT = System.getProperty("rocketmq.endpoint", "192.168.168.101:8081");
    private static final String FIFO_TOPIC = System.getProperty("rocketmq.topic", "MyTopicName");
    private static final String CONSUMER_GROUP = System.getProperty("rocketmq.group", "MyConsumerGroupName");
    private static final String TAG = System.getProperty("rocketmq.tag", "myTag");

    public static void main(String[] args) {
        final ClientServiceProvider provider = ClientServiceProvider.loadService();
        ClientConfiguration clientConfiguration = ClientConfiguration.newBuilder()
            .setEndpoints(ENDPOINT)
            .setRequestTimeout(java.time.Duration.ofSeconds(Long.parseLong(System.getProperty("rocketmq.rtimeout", "3"))))
            .build();
        try {
            FilterExpression filterExpression = new FilterExpression(TAG, FilterExpressionType.TAG);
            log.info("Starting RocketMQ Push Consumer, topic: {}", FIFO_TOPIC);
            PushConsumer consumer = provider.newPushConsumerBuilder()
                .setClientConfiguration(clientConfiguration)
                .setConsumerGroup(CONSUMER_GROUP)
                .setSubscriptionExpressions(java.util.Collections.singletonMap(FIFO_TOPIC, filterExpression))
                .setMessageListener(new RocketMQMultiTopicListener())
                .setConsumptionThreadCount(Integer.getInteger("rocketmq.threads", 20))
                .build();
            // Lock the thread to keep consumer active
            Runtime.getRuntime().addShutdownHook(new Thread(() -> {
                try {
                    if (consumer != null) {
                        consumer.close();
                    }
                } catch (java.io.IOException e) {
                    e.printStackTrace();
                }
                log.info("Consumer closed successfully.");
            }));
        } catch (Exception e) {
            log.error("Failed to initialize RocketMQ consumer", e);
            throw new RuntimeException(e);
        }
    }
}
EOF
