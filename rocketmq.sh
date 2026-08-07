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
log "1. Controller Configurations (Raft Consensus), ctrl can in namesrv plugin mode, samp: conf/controller/cluster-3n-namesrv-plugin"
for node in ${!MAP_NODES[@]}; do
    log "# ${node}: (rocketmq/conf/controller.conf)"
    cat <<EOF
controllerDLegerGroup = group1
controllerDLegerPeers=$(IFS=';';echo "${peerids[*]}";)
controllerDLegerSelfId=${node}
EOF
done

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
ExecStart=/bin/sh -c "cd ${ROCKETMQ_HOME} && ./bin/mqnamesrv start >/dev/null"
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
EOF
cat <<'EOF'
# # startup seq
# [All Servers: NameServers] ==> [Server 1 & 2: Masters] ==> [Server 3 & 4: Slaves]
# # stop seq
# Server 1 & 2: Masters] ==> [Server 3 & 4: Slaves] ==> [All Servers: NameServers]

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
    ssh "$node" "sh ${ROCKETMQ_HOME}/bin/mqshutdown namesrv"
done

echo "2M2S Cluster shutdown complete."
EOF
