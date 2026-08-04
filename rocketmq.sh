#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"

log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }

cat <<EOF
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
log "1. Controller Configurations (Raft Consensus)"
for node in ${!MAP_NODES[@]}; do
    log "# ${node}: (rocketmq/config/controller.conf)"
    cat <<EOF
controllerType=DLEDGER
localAddress=${MAP_NODES[${node}]}:9877
controllerDLegerPeerIds=$(IFS=';';echo "${peerids[*]}";)
controllerDLegerSelfId=${node}
controllerStorePath=/home/rocketmq/store/controller
enableElectUncleanMaster=false
EOF
done

log "2. Proxy Configuration (Stateless Layer)"
log "# On all nodes (rocketmq/config/rmq-proxy.json)"
cat <<EOF
{
#   "grpcKeepAliveTimeMs": 60000,
#   "grpcKeepAliveTimeoutMs": 20000,
#   "grpcPermitKeepAliveWithoutCalls": true,
#   "grpcServerWorkerThreads": 64,
#   "grpcServerSelectorThreads": 16,
#   "remotingThreadPoolNums": 64,
#   "clientExpiredPoolNums": 16,
  "proxyMode":"CLUSTER",
  "rocketMQClusterName": "DefaultCluster",
  "grpcServerPort": 8081,
  "remotingListenPort": 8080,
  "enableGrpcEpoll":true
}
EOF

log "M. Broker Master-A Configuration"
log "# (rocketmq/config/broker-a.conf)"
cat <<EOF
# # Netty thread pool configurations for handling raw I/O
# serverSelectorThreads=8               # Thread count for Netty epoll selectors
# serverWorkerThreads=32                # Worker threads for processing packet parsing
# serverCallbackExecutorThreads=32      # Callback thread allocation
#
# # Core execution worker threads (scale up based on CPU cores)
# sendMessageThreadPoolNums=64          # Dedicate more threads to handling ingestion
# pullMessageThreadPoolNums=64          # Dedicate more threads to message polling
#
# # High connection stability parameters
# clientChannelMaxIdleTimeSeconds=120   # Terminate stale dead connections
# connectTimeoutMillis=5000             # Allow higher timeout for handshake queues

brokerName=broker-a
storePathRootDir=/home/rocketmq/store/broker-a
clusterName=DefaultCluster
namesrvAddr=${namesrvAddr}
enableControllerMode=true
controllerAddr=${controllerAddr}
syncBrokerMetadataPeriod=5000
brokerRole=ASYNC_MASTER
flushDiskType=ASYNC_FLUSH
EOF

log "R. Broker-A Replica Configuration"
log "# (rocketmq/config/broker-a-replica.conf)"
cat <<EOF
brokerName=broker-a
storePathRootDir=/home/rocketmq/store/broker-a-replica
clusterName=DefaultCluster
namesrvAddr=${namesrvAddr}
enableControllerMode=true
controllerAddr=${controllerAddr}
syncBrokerMetadataPeriod=5000
brokerRole=SLAVE
flushDiskType=ASYNC_FLUSH
EOF

log "# Verify Check Cluster Topology:"
log "mqadmin clusterList -n ip:9876"
log "# Verify Check Controller Status:"
log "mqadmin getControllerMetaData -a ip:9877"

cat <<'EOF' >rocketmq-broker.service
[Unit]
Description=RocketMQ Broker
After=network.target rocketmq-namesrv.service

[Service]
Type=simple
User=rocketmq
Group=rocketmq
Environment="ROCKETMQ_HOME=/opt/rocketmq-all-5.3.0-bin-release"
EnvironmentFile=-/etc/rocketmq.conf
WorkingDirectory=${ROCKETMQ_HOME}
# Environment="JAVA_OPT="
ExecStart=${ROCKETMQ_HOME}/bin/mqbroker -n hios-mq-s01:9876;hios-mq-s02:9876 -c /opt/rocketmq-all-5.3.0-bin-release/conf/2m-2s-sync/broker-b.properties
ExecStop=${ROCKETMQ_HOME}/bin/mqshutdown broker
Restart=on-failure
RestartSec=5s
LimitNOFILE=655360
LimitMEMLOCK=infinity
EOF
cat <<'EOF' > rocketmq-proxy.service
[Unit]
Description=RocketMQ Proxy
After=network.target rocketmq-namesrv.service

[Service]
Type=simple
User=rocketmq
Group=rocketmq
Environment="ROCKETMQ_HOME=/opt/rocketmq-all-5.3.0-bin-release"
EnvironmentFile=-/etc/rocketmq.conf
WorkingDirectory=${ROCKETMQ_HOME}
ExecStart=${ROCKETMQ_HOME}/bin/mqproxy -n hios-mq-s01:9876;hios-mq-s02:9876 -pc conf/rmq-proxy.json
ExecStop=${ROCKETMQ_HOME}/bin/mqshutdown proxy
Restart=on-failure
RestartSec=5s
LimitNOFILE=655360

[Install]
WantedBy=multi-user.target
EOF
cat <<'EOF' >rocketmq-namesrv.service
[Unit]
Description=RocketMQ NameServer
After=network.target

[Service]
Type=simple
User=rocketmq
Group=rocketmq
Environment="ROCKETMQ_HOME=/opt/rocketmq-all-5.3.0-bin-release"
EnvironmentFile=-/etc/rocketmq.conf
WorkingDirectory=${ROCKETMQ_HOME}
ExecStart=${ROCKETMQ_HOME}/bin/mqnamesrv start
ExecStop=${ROCKETMQ_HOME}/bin/mqshutdown namesrv
Restart=on-failure
RestartSec=5s
LimitNOFILE=655360

[Install]
WantedBy=multi-user.target
EOF

cat <<'EOF'
# export NAMESRV_ADDR=localhost:9876
# sh bin/tools.sh org.apache.rocketmq.example.quickstart.Producer
# sh bin/tools.sh org.apache.rocketmq.example.quickstart.Consumer

nohup sh mqnamesrv &> ~/namesrv.log &
nohup sh mqcontroller -c /opt/rocketmq/conf/controller.conf &> ~/controller.log &
nohup sh mqbroker -c /opt/rocketmq/conf/broker-a.conf &> ~/broker-a.log &
nohup sh mqbroker -c /opt/rocketmq/conf/broker-a-replica.conf &> ~/broker-a-replica.log &
nohup sh mqproxy -c /opt/rocketmq/conf/rmq-proxy.json &> ~/proxy.log &

# Verify it started
jps | grep NamesrvStartup
jps | grep ControllerStartup
jps | grep ProxyStartup

sh mqshutdown proxy
sh mqshutdown broker
sh mqshutdown controller
sh mqshutdown namesrv
bin/runserver.sh (NameServer & Proxy)
    JAVA_OPT="${JAVA_OPT} -server -Xms1g -Xmx1g -Xmn512m -XX:MetaspaceSize=128m -XX:MaxMetaspaceSize=256m"
bin/runbroker.sh (Broker & Controller)
    JAVA_OPT="${JAVA_OPT} -server -Xms4g -Xmx4g -Xmn2g -XX:MaxDirectMemorySize=2g"
# three brokers
mqadmin clusterList -n 192.168.1.10:9876
# Cluster Name     # Broker Name     # BID      # InSyncReplica
DefaultCluster     broker-a          0          True   (Master on Node 1)
DefaultCluster     broker-a          1          True   (Replica on Node 2)
DefaultCluster     broker-a          2          True   (Replica on Node 3)
DefaultCluster     broker-b          0          True   (Master on Node 2)
DefaultCluster     broker-b          1          True   (Replica on Node 3)
DefaultCluster     broker-b          2          True   (Replica on Node 1)
DefaultCluster     broker-c          0          True   (Master on Node 3)
DefaultCluster     broker-c          1          True   (Replica on Node 1)
DefaultCluster     broker-c          2          True   (Replica on Node 2)
EOF
