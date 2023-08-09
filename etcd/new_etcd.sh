#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("deffc62[2022-01-06T14:39:22+08:00]:new_etcd.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
init_dir() {
    local etcd_data_dir=${1}
    getent group etcd >/dev/null || groupadd --system etcd || :
    getent passwd etcd >/dev/null || useradd -g etcd --system -s /sbin/nologin -d /var/empty/etcd etcd 2> /dev/null || :
    mkdir -p -m0700 ${etcd_data_dir} && chown -R etcd:etcd ${etcd_data_dir}
}
gen_etcd_conf() {
    local pub_ip=$1
    local pub_port=$2
    local cluster_ip=$3
    local cluster_port=$4
    local token=$5
    local member_lst=$6
    local etcd_data_dir=${7}
    local etcd_name=${HOSTNAME:-$(hostname)}
    local etcd_listen_peer_urls=http://${cluster_ip}:${cluster_port}
    local etcd_initial_advertise_peer_urls="http://${cluster_ip}:${cluster_port}"
    local etcd_listen_client_urls="${pub_port},http://127.0.0.1:${pub_port}"
    local etcd_advertise_client_urls="http://${pub_ip}:${pub_port}"
    local etcd_initial_cluster="${member_lst}"
    local etcd_initial_cluster_state=new
    local etcd_initial_cluster_token="${token}"
    cat > /etc/default/etcd <<EOF
ETCD_NAME="${etcd_name}"
ETCD_DATA_DIR="${etcd_data_dir}"
# 集群内部通信使用的URL
ETCD_LISTEN_PEER_URLS="${etcd_listen_peer_urls}"
# 供外部客户端使用的URL
ETCD_LISTEN_CLIENT_URLS="${etcd_listen_client_urls}"
# 广播给集群内其他成员访问的URL
ETCD_INITIAL_ADVERTISE_PEER_URLS="${etcd_initial_advertise_peer_urls}"
# 广播给外部客户端使用的URL
ETCD_ADVERTISE_CLIENT_URLS="${etcd_advertise_client_urls}"
# 初始集群成员列表
ETCD_INITIAL_CLUSTER="${etcd_initial_cluster}"
# 初始集群状态，new为新建集群
ETCD_INITIAL_CLUSTER_STATE="${etcd_initial_cluster_state}"
# 集群的名称
ETCD_INITIAL_CLUSTER_TOKEN="${etcd_initial_cluster_token}"
# # Security
# ETCD_CERT_FILE="/opt/etcd/ssl/server.pem"
# ETCD_KEY_FILE="/opt/etcd/ssl/server-key.pem"
# ETCD_TRUSTED_CA_FILE="/opt/etcd/ssl/ca.pem"
# ETCD_CLIENT_CERT_AUTH="true"
# ETCD_PEER_CERT_FILE="/opt/etcd/ssl/server.pem"
# ETCD_PEER_KEY_FILE="/opt/etcd/ssl/server-key.pem"
# ETCD_PEER_TRUSTED_CA_FILE="/opt/etcd/ssl/ca.pem"
# ETCD_PEER_CLIENT_CERT_AUTH="true"
EOF
}

gen_etcd_service() {
    cat > /lib/systemd/system/etcd.service <<'EOF'
[Unit]
Description=etcd - highly-available key value store
After=network.target
Wants=network-online.target

[Service]
Environment=DAEMON_ARGS=
Environment=ETCD_NAME=%H
Environment=ETCD_DATA_DIR=/var/lib/etcd/default
EnvironmentFile=-/etc/default/%p
Type=notify
User=etcd
PermissionsStartOnly=true
#ExecStart=/bin/sh -c "GOMAXPROCS=$(nproc) /usr/bin/etcd $DAEMON_ARGS"
ExecStart=/usr/bin/etcd $DAEMON_ARGS
Restart=on-abnormal
#RestartSec=10s
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
Alias=etcd2.service
EOF
}

# remote execute function end!
################################################################################
SSH_PORT=${SSH_PORT:-60022}
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -n|--node <ip>   *   etcd nodes
        --port    <int>      clent connect port, default 2379
        -t|--token <str>     etcd cluster token, default: etcd-cluster
        -s|--src  <dir>      directory contian etcd/etcdctl/etcdutl binary
        --sshpass <str>      ssh password
        --teardown <ip>      remove all etcd&config
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        demo:

EOF
    exit 1
}

teardown() {
    systemctl -q disable --now etcd || true
    kill -9 $(pidof etcd) 2>/dev/null || true
    source <(grep -E "^\s*(ETCD_DATA_DIR)\s*=" /etc/default/etcd 2>/dev/null)
    [ -d "${ETCD_DATA_DIR:-}" ] && rm -fr ${ETCD_DATA_DIR}
    rm -f /usr/bin/etcd /usr/bin/etcdctl /usr/bin/etcdutl || true
    rm -f /etc/default/etcd || true
    rm -f /lib/systemd/system/etcd.service || true
    userdel etcd || true
}

main() {
    local teardown=() node=() token="etcd-cluster" src="${DIRNAME}" sshpass="" port=2379
    local etcd_data_dir="/var/lib/etcd" cluster_port=2380;
    local opt_short="n:t:s:d:"
    local opt_long="node:,token:,src:,sshpass:,port:,data:,teardown:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -n | --node)    shift; node+=(${1}); shift;;
            -d | --data)    shift; etcd_data_dir=${1}; shift;;
            --port)         shift; port=${1}; shift;;
            -t | --token)   shift; token=${1}; shift;;
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
        info_msg "${ipaddr} teardown all etcd binary & config!\n"
        ssh_func "root@${ipaddr}" "${SSH_PORT}" "teardown"
    done
    [ "$(array_size teardown)" -gt "0" ] && { info_msg "TEARDOWN OK\n"; return 0; }
    is_integer ${port} || exit_msg "port is integet\n"
    [ "$(array_size node)" -gt "0" ] || usage "at least one node"
    [ -z ${sshpass} ] || set_sshpass "${sshpass}"
    file_exists "${src}/etcd" || file_exists "${src}/etcdctl" || file_exists "${src}/etcdutl" || exit_msg "etcd/etcdctl/etcdutl no found in '${src}'\n"
    cluster_port=$((port + 1))
    local member_lst=() cluster="" name=""
    for ipaddr in ${node[@]}; do
        name=$(ssh_func "root@${ipaddr}" ${SSH_PORT} 'echo ${HOSTNAME:-$(hostname)}')
        member_lst+=("${name}=http://${ipaddr}:${cluster_port}")
    done
    cluster="$(OIFS="$IFS" IFS=,; echo "${member_lst[*]}"; IFS="$OIFS")"
    for ipaddr in ${node[@]}; do
        upload "${src}/etcd" ${ipaddr} ${SSH_PORT} "root" "/usr/bin/"
        upload "${src}/etcdctl" ${ipaddr} ${SSH_PORT} "root" "/usr/bin/"
        upload "${src}/etcdutl" ${ipaddr} ${SSH_PORT} "root" "/usr/bin/"
        ssh_func "root@${ipaddr}" ${SSH_PORT} init_dir "${etcd_data_dir}"
        ssh_func "root@${ipaddr}" ${SSH_PORT} gen_etcd_service
        ssh_func "root@${ipaddr}" ${SSH_PORT} gen_etcd_conf "${ipaddr}" $port "${ipaddr}" ${cluster_port} "${token}" "${cluster}" "${etcd_data_dir}"
        ssh_func "root@${ipaddr}" ${SSH_PORT} "systemctl daemon-reload && systemctl enable etcd.service"
    done
    for ipaddr in ${node[@]}; do
        ssh_func "root@${ipaddr}" ${SSH_PORT} "nohup systemctl start etcd.service &>/dev/null &"
    done
    sleep 1
    ssh_func "root@${node[0]}" ${SSH_PORT} "etcdctl --endpoints=127.0.0.1:${port} member list"
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
