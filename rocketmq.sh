#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"

log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }

cat <<EOF
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
  "rocketMQClusterName": "DefaultCluster",
  "grpcServerPort": 8081,
  "remotingListenPort": 8080,
  "enableGrpcEpoll":true
}
EOF

log "M. Broker Master-A Configuration"
log "# (rocketmq/config/broker-a.conf)"
cat <<EOF
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

cat <<'EOF'
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
EOF
