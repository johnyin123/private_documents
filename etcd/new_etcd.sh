#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("1635f19[2024-03-25T13:07:16+08:00]:new_etcd.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
init_dir() {
    local etcd_data_dir=${1}
    getent group etcd >/dev/null || groupadd --system etcd || :
    getent passwd etcd >/dev/null || useradd -g etcd --system -s /sbin/nologin -d /var/empty/etcd etcd 2> /dev/null || :
    mkdir -p -m0700 ${etcd_data_dir} && chown -R etcd:etcd ${etcd_data_dir}
    mkdir -p /etc/etcd/ssl
}
gen_etcd_conf() {
    local pub_ip=$1
    local pub_port=$2
    local cluster_ip=$3
    local cluster_port=$4
    local token=$5
    local member_lst=$6
    local etcd_data_dir=${7}
    local cert=${8##*/}
    local key=${9##*/}
    local ca=${10##*/}
    local protocol="http"
    [ -z "${key}" ] || {
        chown -R etcd:etcd /etc/etcd/
        chmod -R 550 /etc/etcd/ssl
        protocol="https"
    }
    local etcd_name=${HOSTNAME:-$(hostname)}
    local etcd_listen_peer_urls="${protocol}://${cluster_ip}:${cluster_port}"
    local etcd_initial_advertise_peer_urls="${protocol}://${cluster_ip}:${cluster_port}"
    local etcd_listen_client_urls="${protocol}://${pub_ip}:${pub_port},${protocol}://127.0.0.1:${pub_port}"
    local etcd_advertise_client_urls="${protocol}://${pub_ip}:${pub_port}"
    local etcd_initial_cluster="${member_lst}"
    local etcd_initial_cluster_state=new
    local etcd_initial_cluster_token="${token}"
    cat > /etc/default/etcd <<EOF
ETCD_NAME="${etcd_name}"
# 初始集群成员列表
ETCD_INITIAL_CLUSTER="${etcd_initial_cluster}"
# 广播给集群内其他成员访问的URL
ETCD_INITIAL_ADVERTISE_PEER_URLS="${etcd_initial_advertise_peer_urls}"
# 初始集群状态，new为新建集群
ETCD_INITIAL_CLUSTER_STATE="${etcd_initial_cluster_state}"
ETCD_DATA_DIR="${etcd_data_dir}"
# 集群内部通信使用的URL
ETCD_LISTEN_PEER_URLS="${etcd_listen_peer_urls}"
# 供外部客户端使用的URL
ETCD_LISTEN_CLIENT_URLS="${etcd_listen_client_urls}"
# 广播给外部客户端使用的URL
ETCD_ADVERTISE_CLIENT_URLS="${etcd_advertise_client_urls}"
# 集群的名称
ETCD_INITIAL_CLUSTER_TOKEN="${etcd_initial_cluster_token}"
# # Security
$(
[ -z "${cert}" ] ||{
    echo "ETCD_CERT_FILE=\"/etc/etcd/ssl/${cert}\""
    echo "ETCD_PEER_CERT_FILE=\"/etc/etcd/ssl/${cert}\""
}
[ -z "${key}" ] ||{
    echo "ETCD_KEY_FILE=\"/etc/etcd/ssl/${key}\""
    echo "ETCD_PEER_KEY_FILE=\"/etc/etcd/ssl/${key}\""
}
[ -z "${ca}" ] ||{
    echo "ETCD_PEER_TRUSTED_CA_FILE=\"/etc/etcd/ssl/${ca}\""
    echo "ETCD_TRUSTED_CA_FILE=\"/etc/etcd/ssl/${ca}\""
    echo "ETCD_PEER_CLIENT_CERT_AUTH=\"true\""
}
)
# echo "ETCD_CLIENT_CERT_AUTH=\"true\""
EOF
    [ -z "${key}" ] ||{
        cat <<EOF > /etc/profile.d/etcd.sh
export ETCDCTL_CACERT=/etc/etcd/ssl/${ca}
export ETCDCTL_CERT=/etc/etcd/ssl/${cert}
export ETCDCTL_KEY=/etc/etcd/ssl/${key}
EOF
        chmod 644 /etc/profile.d/etcd.sh
    }
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

etcd_member_list() {
    local port=${1}
    local cert=${2##*/}
    local key=${3##*/}
    local ca=${4##*/}
    [ -z "${key}" ] || {
        export ETCDCTL_CACERT=/etc/etcd/ssl/${ca}
        export ETCDCTL_CERT=/etc/etcd/ssl/${cert}
        export ETCDCTL_KEY=/etc/etcd/ssl/${key}
    }
    etcdctl --endpoints=127.0.0.1:${port} member list -w table
    echo "ETCDCTL_CACERT=/etc/etcd/ssl/${ca} ETCDCTL_CERT=/etc/etcd/ssl/${cert} ETCDCTL_KEY=/etc/etcd/ssl/${key} etcdctl --endpoints=127.0.0.1:${port} member list -w table"
}
# remote execute function end!
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -n|--node  <ip>   *  etcd nodes
        --port     <int>     clent connect port, default 2379
        -t|--token <str>     etcd cluster token, default: etcd-cluster
        -s|--src   <dir>     directory contian etcd/etcdctl/etcdutl binary, default current dir
        --cert     <file>
        --key      <file>
        --ca       <file>
        --teardown <ip>      remove all etcd&config
        -U|--user     <user> ssh user, default root
        -P|--port     <int>  ssh port, default 60022
        --password    <str>  ssh password(default use sshkey)
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
    rm -fr /etc/etcd || true
    rm -f /lib/systemd/system/etcd.service || true
    userdel etcd || true
}

main() {
    local sshuser=root sshport=60022
    local teardown=() node=() token="etcd-cluster" src="${DIRNAME}" sshpass="" port=2379
    local etcd_data_dir="/var/lib/etcd" cluster_port=2380 cert="" key="" ca=""
    local opt_short="n:t:s:d:"
    local opt_long="node:,token:,src:,sshpass:,port:,data:,teardown:,cert:,key:,ca:,"
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
            --cert)         shift; cert=${1}; shift;;
            --key)          shift; key=${1}; shift;;
            --ca)           shift; ca=${1}; shift;;
            -U | --sshuser) shift; sshuser=${1}; shift;;
            -P | --sshport) shift; sshport=${1}; shift;;
            --password)     shift; set_sshpass "${1}"; shift;;
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
        ssh_func "${sshuser}@${ipaddr}" "${sshport}" "teardown"
    done
    [ "$(array_size teardown)" -gt "0" ] && { info_msg "TEARDOWN OK\n"; return 0; }
    is_integer ${port} || exit_msg "port is integet\n"
    [ "$(array_size node)" -gt "0" ] || usage "at least one node"
    file_exists "${src}/etcd" || file_exists "${src}/etcdctl" || exit_msg "etcd/etcdctl no found in '${src}'\n"
    cluster_port=$((port + 1))
    local member_lst=() cluster="" name="" protocol="http"
    [ -z "${key}" ] || protocol="https"
    for ipaddr in ${node[@]}; do
        name=$(ssh_func "${sshuser}@${ipaddr}" ${sshport} 'echo ${HOSTNAME:-$(hostname)}')
        member_lst+=("${name}=${protocol}://${ipaddr}:${cluster_port}")
    done
    cluster="$(OIFS="$IFS" IFS=,; echo "${member_lst[*]}"; IFS="$OIFS")"
    for ipaddr in ${node[@]}; do
        upload "${src}/etcd" "${ipaddr}" "${sshport}" "${sshuser}" "/usr/bin/"
        upload "${src}/etcdctl" "${ipaddr}" "${sshport}" "${sshuser}" "/usr/bin/"
        file_exists "${src}/etcdutl" && upload "${src}/etcdutl" "${ipaddr}" "${sshport}" "${sshuser}" "/usr/bin/"
        ssh_func "${sshuser}@${ipaddr}" ${sshport} init_dir "${etcd_data_dir}"
        [ -z "${cert}" ] || upload "${cert}" "${ipaddr}" "${sshport}" "${sshuser}" "/etc/etcd/ssl"
        [ -z "${key}" ] || upload "${key}" "${ipaddr}" "${sshport}" "${sshuser}" "/etc/etcd/ssl"
        [ -z "${ca}" ] ||  upload "${ca}" "${ipaddr}" "${sshport}" "${sshuser}" "/etc/etcd/ssl"
        ssh_func "${sshuser}@${ipaddr}" ${sshport} gen_etcd_service
        ssh_func "${sshuser}@${ipaddr}" ${sshport} gen_etcd_conf "${ipaddr}" $port "${ipaddr}" ${cluster_port} "${token}" "${cluster}" "${etcd_data_dir}" "${cert}" "${key}" "${ca}"
        ssh_func "${sshuser}@${ipaddr}" ${sshport} "systemctl daemon-reload && systemctl enable etcd.service"
    done
    for ipaddr in ${node[@]}; do
        ssh_func "${sshuser}@${ipaddr}" ${sshport} "nohup systemctl start etcd.service &>/dev/null &"
    done
    sleep 1
    [ -z "${key}" ] || {
        info_msg "TLS etcd, can restart etc more times then all ok\n"
        for ipaddr in ${node[@]}; do
            ssh_func "${sshuser}@${ipaddr}" ${sshport} "nohup systemctl start etcd.service &>/dev/null &"
        done
    }
    ssh_func "${sshuser}@${node[0]}" ${sshport} etcd_member_list "$port" "${cert}" "${key}" "${ca}"
    cat <<'EOF'
复制其他节点的data-dir中的内容，以此为基础上以--force-new-cluster强行拉起，然后以添加新成员的方式恢复这个集群
#!/bin/bash
etcdctl --endpoints https://127.0.0.1:2379 --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key snapshot save /backup/snap-$(date +%Y%m%d)
# find /tmp/etcd_backup/ -ctime +7 -exec rm -r {}

etcdctl member add mynew_node1 --peer-urls=http://10.0.1.13:2380
etcdctl在注册完新节点后，会返回一段提示，包含3个环境变量。然后在新节点启动时候，带上这3个环境变量即可。

kubectl get pods -n kube-system | grep etcd | awk '{print $1}'
endpoints=https://127.0.0.1:2379
kubectl exec -ti -n kube-system ${etcd_name} -- etcdctl --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key --endpoints=${endpoints} member list -w table
kubectl exec -ti -n kube-system ${etcd_name} -- etcdctl --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key --endpoints=${endpoints} endpoint status -w table
kubectl exec -ti -n kube-system ${etcd_name} -- etcdctl --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key --endpoints=${endpoints} snapshot save /var/lib/etcd/k8s_etcd.db
kubectl exec -ti -n kube-system ${etcd_name} -- etcdctl --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key --endpoints=${endpoints} member add srv153 --peer-urls=https://192.168.168.153:2380
# # make sure new etcd  nodes has same version
kubectl exec -ti -n kube-system ${etcd_name} -- etcdctl --cacert=/etc/kubernetes/pki/etcd/ca.crt --cert=/etc/kubernetes/pki/etcd/server.crt --key=/etc/kubernetes/pki/etcd/server.key --endpoints=${endpoints} version
# # on new nodes
# # get etc/kubernetes/pki/etcd/ca.crt/ca.key,  use new_ssl.sh renew a node key/pem
./new_etcd.sh -n 192.168.168.153 --cert etcd.pem  --key etcd.key --ca ca.pem
# # and edit /etc/default/etcd, add new configure
# # on etcd k8s node
rm /etc/kubernetes/manifests/etcd.yaml
systemctl restart kubelet
EOF
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
