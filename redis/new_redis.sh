#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("f40aa52[2021-12-31T11:03:01+08:00]:new_redis.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
init_dir() {
    getent group redis >/dev/null || groupadd --system redis || :
    getent passwd redis >/dev/null || useradd -g redis --system -s /sbin/nologin -d /var/empty/redis redis 2> /dev/null || :
    mkdir -p /etc/redis && chown -R redis:redis /etc/redis
    mkdir -p /var/log/redis && chown -R redis:redis /var/log/redis
    mkdir -p /var/lib/redis && chown -R redis:redis /var/lib/redis
    echo "vm.overcommit_memory = 1" > /etc/sysctl.d/99-zredis.conf
}

gen_redis_service() {
    cat > /lib/systemd/system/redis-server@.service <<EOF
[Unit]
Description=redis key-value store (%I)
After=network.target

[Service]
Type=notify
ExecStart=/usr/bin/redis-server /etc/redis/redis-%i.conf --supervised systemd --daemonize no
PIDFile=/run/redis-%i/redis-server.pid
TimeoutStopSec=0
Restart=always
User=redis
Group=redis
RuntimeDirectory=redis-%i
RuntimeDirectoryMode=2755

UMask=007
PrivateTmp=yes
LimitNOFILE=65535
PrivateDevices=yes
ProtectHome=yes
ReadOnlyDirectories=/
ReadWritePaths=-/var/lib/redis
ReadWritePaths=-/var/log/redis
ReadWritePaths=-/var/run/redis-%i

NoNewPrivileges=true
CapabilityBoundingSet=CAP_SETGID CAP_SETUID CAP_SYS_RESOURCE
MemoryDenyWriteExecute=true
ProtectKernelModules=true
ProtectKernelTunables=true
ProtectControlGroups=true
RestrictRealtime=true
RestrictNamespaces=true
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX

# redis-server can write to its own config file when in cluster mode so we
# permit writing there by default. If you are not using this feature, it is
# recommended that you replace the following lines with "ProtectSystem=full".
ProtectSystem=true
ReadWriteDirectories=-/etc/redis

[Install]
WantedBy=multi-user.target
EOF
}

gen_redis_conf() {
    local dir=${1}
    local port=${2}
    local password=${3}
    cat >${dir}/redis-${port}.conf << EOF
bind 0.0.0.0
port ${port}
tcp-backlog 511
cluster-enabled yes
cluster-node-timeout 5000
cluster-config-file node-${port}.conf
dir /var/lib/redis/redis-server-${port}
logfile /var/log/redis/redis-server-${port}.log
pidfile /run/redis-${port}/redis-server.pid
dbfilename dump-${port}.rdb
appendfilename "appendonly-${port}.aof"
requirepass ${password}
###########################################
appendonly yes
loglevel notice
save 900 1
save 300 10
save 60 10000
EOF
    mkdir -p /var/lib/redis/redis-server-${port} || true
    chown redis:redis /var/lib/redis/redis-server-${port} || true
    chown redis:redis ${dir}/redis-${port}.conf || true
    cat >/etc/logrotate.d/redis-server <<EOF
/var/log/redis/redis-server*.log {
    weekly
    missingok
    rotate 12
    compress
    notifempty
}
EOF

}

init_redis_cluster() {
    local password=${1}
    local port=${2}
    local replicas=${3}
    shift 3
    /usr/bin/redis-cli -p ${port} -a "${password}" --cluster create ${*} --cluster-replicas ${replicas} --cluster-yes
    # Using redis-trib.rb for Redis 4 or 3 type:
    echo "redis-trib.rb create --replicas ${replicas} ${*}"
}

# remote execute function end!
################################################################################
SSH_PORT=${SSH_PORT:-60022}

upload() {
    local lfile=${1}
    local ipaddr=${2}
    local port=${3}
    local user=${4}
    local rfile=${5}
    info2_msg "upload ${lfile} ====> ${user}@${ipaddr}:${port}${rfile}\n"
    try scp -P${port} ${lfile} ${user}@${ipaddr}:${rfile}
}


usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -n|--node <ip>   *   redis nodes
        --num <int>          redis instance per node, default 2
        --port    <int>      redis port, default 6379
        --replicas <int>     redis replicas, default 1
        -p|--passwd <str>    redis password, default: random gen
        -s|--src  <dir>      directory contian redis-server/redis-cli binary
        --sshpass <str>      ssh password
        --teardown <ip>      remove all redis&config
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        # build redis with: make USE_SYSTEMD=yes
        *** Redis Cluster requires at least 3 master nodes.
        *** At least 6 nodes are required.
        demo:
            (node * num == master * (replicas+1))
           ./new_redis.sh -n 192.168.168.124 -s ~/centos8 --num 3 --replicas 0
           ./new_redis.sh -n 192.168.168.124 -s ~/centos8 --num 6 --replicas 1
           ./new_redis.sh -s ~/centos8 --num 2 --replicas 1 -n 192.168.168.A -n 192.168.168.B -n 192.168.168.C

EOF
    exit 1
}

new_redis_cluster() {
    local ipaddr=${1}
    local passwd=${2}
    local port=${3}
    local src=${4}
    local replicas=${5}

    upload "${src}/redis-server" ${ipaddr} ${SSH_PORT} "root" "/usr/bin/"
    upload "${src}/redis-cli" ${ipaddr} ${SSH_PORT} "root" "/usr/bin/"

    ssh_func "root@${ipaddr}" ${SSH_PORT} init_dir
    ssh_func "root@${ipaddr}" ${SSH_PORT} gen_redis_service
    for i in $(seq 0 ${replicas});do
        ssh_func "root@${ipaddr}" ${SSH_PORT} gen_redis_conf "/etc/redis" "$((port + i))" "${passwd}"
        ssh_func "root@${ipaddr}" ${SSH_PORT} "systemctl daemon-reload && systemctl enable --now redis-server@$((port + i)).service"
    done
}

teardown() {
    systemctl -q disable --now redis-server@ || true
    kill -9 $(pidof redis-server) 2>/dev/null || true
    userdel redis || true
    rm -rf /etc/redis || true
    rm -rf /var/log/redis || true
    rm -rf /var/lib/redis || true
    rm -f /etc/sysctl.d/99-zredis.conf || true
    rm -f /lib/systemd/system/redis-server@.service /usr/bin/redis-server /usr/bin/redis-cli || true
}

main() {
    local teardown=() node=() num=2 passwd="" src="${DIRNAME}" sshpass="" port=6379 replicas=1
    local opt_short="n:p:s:"
    local opt_long="node:,num:,passwd:,src:,sshpass:,port:,replicas:,teardown:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -n | --node)    shift; node+=(${1}); shift;;
            --num)          shift; num=${1}; shift;;
            --port)         shift; port=${1}; shift;;
            --replicas)     shift; replicas=${1}; shift;;
            -p | --passwd)  shift; passwd=${1}; shift;;
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
        info_msg "${ipaddr} teardown all k8s config!\n"
        ssh_func "root@${ipaddr}" "${SSH_PORT}" "teardown"
    done
    [ "$(array_size teardown)" -gt "0" ] && { info_msg "TEARDOWN OK\n"; return 0; }
    is_integer ${replicas} || is_integer ${port} || is_integer ${num} || exit_msg "replicas/port/num is integet\n"
    [ "$(array_size node)" -gt "0" ] || usage "at least one node"
    [ -z ${sshpass} ] || set_sshpass "${sshpass}"
    [ -z ${passwd} ] && passwd=$(gen_passwd)
    file_exists "${src}/redis-server" || file_exists "${src}/redis-cli" || exit_msg "redis-server/redis-cli no found in '${src}'\n"
    peers_lst=()
    for ipaddr in ${node[@]}; do
        upload "${src}/redis-server" ${ipaddr} ${SSH_PORT} "root" "/usr/bin/"
        upload "${src}/redis-cli" ${ipaddr} ${SSH_PORT} "root" "/usr/bin/"
        ssh_func "root@${ipaddr}" ${SSH_PORT} init_dir
        ssh_func "root@${ipaddr}" ${SSH_PORT} gen_redis_service
        for ((i=0;i<num;i++));do
            peers_lst+=("${ipaddr}:$((port + i))")
            ssh_func "root@${ipaddr}" ${SSH_PORT} gen_redis_conf "/etc/redis" "$((port + i))" "${passwd}"
            ssh_func "root@${ipaddr}" ${SSH_PORT} "systemctl daemon-reload && systemctl enable --now redis-server@$((port + i)).service"
        done
    done
    ipaddr=${node[0]}
    ssh_func "root@${ipaddr}" ${SSH_PORT} init_redis_cluster "${passwd}" ${port} ${replicas} "${peers_lst[@]}"
    ssh_func "root@${ipaddr}" ${SSH_PORT} "redis-cli --cluster check -a ${passwd}  ${peers_lst[0]}"
            # redis-cli -c -p 7000
            # redis 127.0.0.1:7000> set foo ba
            # redis-cli -s /var/run/redis-myname/redis-server.sock info | grep config_file


    return 0
}
main "$@"

# https://github.com/twitter/twemproxy
# https://github.com/RedisLabs/redis-cluster-proxy
