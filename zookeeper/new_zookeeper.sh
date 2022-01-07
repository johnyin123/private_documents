#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2022-01-07T16:44:39+08:00]:new_zookeeper.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
init_dir() {
    getent group zookeeper >/dev/null || groupadd --system zookeeper || :
    getent passwd zookeeper >/dev/null || useradd -g zookeeper --system -s /sbin/nologin -d /var/empty/zookeeper zookeeper 2> /dev/null || :
    mkdir -p /opt/zookeeper/var/zk/data
    mkdir -p /opt/zookeeper/var/zk/log
    mkdir -p /opt/zookeeper/conf
    chown -R zookeeper:zookeeper /opt/zookeeper
}

gen_zk_service() {
    cat > /lib/systemd/system/zookeeper.service <<EOF
[Unit]
Description=ZooKeeper
After=network.target network-online.target remote-fs.target

[Service]
Type=forking
User=zookeeper
Group=zookeeper
Environment="KAFKA_JMX_OPTS=-Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.port=10020 -Dcom.sun.management.jmxremote.local.only=true -Dcom.sun.management.jmxremote.authenticate=false"
ExecStart=/opt/zookeeper/bin/zkServer.sh start
ExecStop=/opt/zookeeper/bin/zkServer.sh stop
SuccessExitStatus=143

[Install]
WantedBy=multi-user.target
EOF
}

gen_zk_conf() {
    local id=${1}
    local port=${2}
    shift 2
    nodes=${*}
    cat >/opt/zookeeper/conf/zoo.cfg << EOF
# the directory where the snapshot is stored.
dataDir=/opt/zookeeper/var/zk/data
# the port at which the clients will connect
clientPort=${port}
# the maximum number of client connections.
maxClientCnxns=0

$( for i in ${*}; do echo $i; done)

initLimit=5
syncLimit=2

autopurge.snapRetainCount=3
autopurge.purgeInterval=1
EOF
    chown zookeeper:zookeeper /opt/zookeeper/conf/zoo.cfg || true
    cat >/opt/zookeeper/conf/java.env <<EOF
ZK_SERVER_HEAP=1024
JAVA_HOME=/opt/jdk-17.0.1/
EOF
    chown zookeeper:zookeeper /opt/zookeeper/conf/java.env || true
    cat >/opt/zookeeper/var/zk/data/myid << EOF
${id}
EOF
    chown zookeeper:zookeeper /opt/zookeeper/var/zk/data/myid || true
}

# remote execute function end!
################################################################################
SSH_PORT=${SSH_PORT:-60022}

teardown() {
    systemctl -q disable --now zookeeper || true
    userdel zookeeper || true
    rm -rf /opt/zookeeper || true
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -n|--node <ip>   *   zookeeper nodes
        --port    <int>      zookeeper port, default 2181
        -s|--src  <str>      tgz file of zookeeper binary, default:${DIRNAME}/zookeeper.tar.gz
        --sshpass <str>      ssh password
        --teardown <ip>      remove all zookeeper&config
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        first: install java env, then modify /opt/zookeeper/conf/java.env
EOF
    exit 1
}

main() {
    local teardown=() node=() src="${DIRNAME}/zookeeper.tar.gz" sshpass="" port=2181
    local opt_short="n:s:"
    local opt_long="node:,src:,sshpass:,port:,teardown:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -n | --node)    shift; node+=(${1}); shift;;
            --port)         shift; port=${1}; shift;;
            -s | --src)     shift; src=${1}; shift;;
            --sshpass)      shift; sshpass="${1}"; shift;;
            --teardown)     shift; teardown+=(${1}); shift;;
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; set_loglevel ${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    local ipaddr=""
    for ipaddr in "${teardown[@]}"; do
        info_msg "${ipaddr} teardown all zookeeper binary & config!\n"
        ssh_func "root@${ipaddr}" "${SSH_PORT}" "teardown"
    done
    [ "$(array_size teardown)" -gt "0" ] && { info_msg "TEARDOWN OK\n"; return 0; }
    is_integer ${port} || exit_msg "port is integet\n"
    [ "$(array_size node)" -gt "0" ] || usage "at least one node"
    [ -z ${sshpass} ] || set_sshpass "${sshpass}"
    file_exists "${src}" || exit_msg "${src} no found\n"
    local srvlst=() id=1
    for ipaddr in "${node[@]}"; do
        ssh_func "root@${ipaddr}" ${SSH_PORT} init_dir
        cat ${src} | ssh -p ${SSH_PORT} "root@${ipaddr}" "tar -C /opt/zookeeper -xz"
        ssh_func "root@${ipaddr}" ${SSH_PORT} "chown -R zookeeper:zookeeper /opt/zookeeper"
        printf -v srv "server.%d=zk%02d:2888:3888" ${id} ${id}
        srvlst+=("${srv}")
        id=$((id++))
    done
    id=1
    for ipaddr in "${node[@]}"; do
        ssh_func "root@${ipaddr}" ${SSH_PORT} gen_zk_conf ${id} ${port} ${srvlst[@]}
        id=$((id++))
    done
    return 0
}
main "$@"
