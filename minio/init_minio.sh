#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2023-05-26T13:48:35+08:00]:init_minio.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
SSH_PORT=${SSH_PORT:-60022}

upload() {
    local lfile=${1}
    local ipaddr=${2}
    local port=${3}
    local user=${4}
    local rfile=${5}
    warn_msg "upload ${lfile} ====> ${user}@${ipaddr}:${port}${rfile}\n"
    try scp -P${port} ${lfile} ${user}@${ipaddr}:${rfile}
}

download_minio() {
    info_msg "download minio server minio.amd64, minio.arm64\n"
    file_exists minio.amd64 || fetch https://dl.min.io/server/minio/release/linux-amd64/minio minio.amd64
    file_exists minio.arm64 || fetch https://dl.min.io/server/minio/release/linux-arm64/minio minio.arm64
    info_msg "download minio client mc.amd64, mc.arm64\n"
    file_exists mc.amd64 || fetch https://dl.min.io/client/mc/release/linux-amd64/mc
    file_exists mc.arm64 || fetch https://dl.min.io/client/mc/release/linux-arm64/mc
    return 0
}

init_minio_server() {
    local user=${1}
    local group=${2}
    local store_path=${3}
    mkdir -p /etc/minio ${store_path}
    mountpoint -q ${store_path} || { "********************${store_path} not mount any disk!!!!!!****************"; return 1; }
    touch /etc/default/minio || true
    getent group ${group} >/dev/null || groupadd --system ${group}
    getent passwd ${user} >/dev/null || useradd -g ${group} --system -s /sbin/nologin -d /var/empty/minio ${user}
    chown ${user}:${group} ${store_path} || true
    cat <<EOF | tee /lib/systemd/system/minio.service
[Unit]
Description=Minio
Documentation=https://docs.minio.io
Wants=network-online.target
After=network-online.target
AssertFileIsExecutable=/usr/bin/minio

[Service]
WorkingDirectory=/usr/

User=${user}
Group=${group}
EOF
    cat <<'EOF' | tee -a /lib/systemd/system/minio.service
ProtectProc=invisible

EnvironmentFile=-/etc/default/minio
ExecStartPre=/bin/bash -c "if [ -z \"${MINIO_VOLUMES}\" ]; then echo \"Variable MINIO_VOLUMES not set in /etc/default/minio\"; exit 1; fi"
ExecStart=/usr/bin/minio server $MINIO_OPTS $MINIO_VOLUMES

# Let systemd restart this service always
Restart=always

# Specifies the maximum file descriptor number that can be opened by this process
LimitNOFILE=65536

# Specifies the maximum number of threads this process can create
TasksMax=infinity

# Disable timeout logic and wait until the process is stopped
TimeoutStopSec=infinity
SendSIGKILL=no

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload || true
    systemctl enable minio --now || true
}

conf_minio_server() {
    local cfg=${1}
    local port=${2}
    local store_path=${3}
    local cport=${4}
    shift 4
    cat <<EOF > ${cfg}
# user for client admin
MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=password
# http://srv{1..4}:9000/minio-data{1..4}
MINIO_VOLUMES="$(for ip in $*; do echo -n "http://${ip}:${port}${store_path} "; done)"
MINIO_OPTS="--config-dir /etc/minio --address 0.0.0.0:${port} --console-address 0.0.0.0:${cport}"
# Set to the URL of the load balancer for the MinIO deployment
# This value *must* match across all MinIO servers. If you do
# not have a load balancer, set this value to to any *one* of the
# MinIO hosts in the deployment as a temporary measure.
# MINIO_SERVER_URL="http://oss.example.net"
EOF
    ${EDITOR:-vi} ${cfg} || true
    confirm "Confirm start init minio cluster (timeout 10,default N)?" 10 || exit_msg "BYE!\n"
}
teardown() {
    systemctl disable minio --now || true
    source <(grep -E "^\s*(User|Group)=" /lib/systemd/system/minio.service)
    [ -z "${User:-}" ] || userdel ${User} || true
    [ -z "${Group:-}" ] || groupdel ${Group} || true
    rm -fr /etc/minio /etc/default/minio /lib/systemd/system/minio.service || true
    rm -f /usr/bin/minio /usr/bin/mc || true
}
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        env: SSH_PORT, default 60022
        -n|--node       * <ip>             minio server nodes, support multi input
        -s|--store_path * <path>           server storage path
        --user            <str>            service startup user, default minio
        --group           <str>            service startup group, default minio
        --port            <int>            port, default 9000
        --console_port    <int>            console port, default 9001
        --teardown     *  <ip>             remove all minio & config
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
       prepare: 
         nodes mount device on <store_path>
            ${SCRIPTNAME} -n 192.168.168.111 -n 192.168.168.112 --store_path <store_path> ....
         if error:
            ${SCRIPTNAME} --teardown 192.168.168.111 --teardown 192.168.168.112

EOF
    exit 1
}
main() {
    node=()
    local user=minio group=minio port=9000 store_path="" teardown=0 console_port=9001
    local opt_short="n:s:"
    local opt_long="node:,store_path:,teardown:,user:,group:,port:,console_port:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -n | --node)    shift; node+=(${1}); shift;;
            -s|--store_path)shift; store_path=${1}; shift;;
            --user)         shift; user=${1}; shift;;
            --group)        shift; group=${1}; shift;;
            --port)         shift; port=${1}; shift;;
            --console_port) shift; console_port=${1}; shift;;
            --teardown)     shift; teardown=1;info_msg "${1} teardown!\n"; ssh_func "root@${1}" ${SSH_PORT} teardown; shift;;
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
    [ "${teardown}" -gt 0 ] && { info_msg "Teardown ALL OK\n"; exit 0; }
    [ -z ${store_path} ] && usage "store_path need input"
    download_minio
    [ "$(array_size node)" -gt "0" ] && conf_minio_server "minio.cfg" "${port}" "${store_path}" "${console_port}" "${node[@]}"
    for ipaddr in ${node[@]}; do
        # ipaddr=$(awk -F'[/:]+' '{print $2}' <<< 'http://ipaddr:port/store_path')
        info_msg "init node ${ipaddr}:${port}${store_path} start ...\n"
        local minio_bin="" mc_bin=""
        local arch=$(ssh_func "root@${ipaddr}" ${SSH_PORT} "uname -m")
        info_msg "node ${ipaddr} <${arch}>\n"
        case "${arch}" in
            x86_64)    minio_bin=minio.amd64; mc_bin=mc.amd64;;
            aarch64)   minio_bin=minio.arm64; mc_bin=mc.arm64;;
            *)         exit_msg "unsupport arch ${arch}\n";;
        esac
        upload "minio.cfg" ${ipaddr} ${SSH_PORT} "root" "/etc/default/minio"
        upload "${minio_bin}" ${ipaddr} ${SSH_PORT} "root" "/usr/bin/minio"
        upload "${mc_bin}" ${ipaddr} ${SSH_PORT} "root" "/usr/bin/mc"
        ssh_func "root@${ipaddr}" ${SSH_PORT} "chmod 755 /usr/bin/minio /usr/bin/mc"
        ssh_func "root@${ipaddr}" ${SSH_PORT} init_minio_server "${user}" "${group}" "${store_path}"
        info_msg "init node ${ipaddr} OK.\n"
    done
    info_msg "ALL DONE!\n"
    return 0
}
main "$@"
