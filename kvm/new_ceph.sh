#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("new_ceph.sh - 1dc4937 - 2021-09-15T10:19:44+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
init_first_mon() {
    local cname=${1:-ceph}
    local name=${HOSTNAME:-$(hostname)}
    local ipaddr=$(hostname -i)
    local fsid=$(cat /proc/sys/kernel/random/uuid)
    local cluster_network=$(ip route | grep "${ipaddr}" | awk '{print $1}')
    cat <<EOF | tee /etc/ceph/${cname}.conf
[global]
fsid = ${fsid}
mon_initial_members = ${name}
mon_host = ${ipaddr}
cluster network = ${cluster_network}
public network = ${cluster_network}
osd pool default size = 2
osd pool default min size = 1
mon allow pool delete = true
mon clock drift allowed = 2
mon clock drift warn backoff = 30
EOF
    ceph-authtool --create-keyring /etc/ceph/ceph.mon.keyring \
        --gen-key -n mon. --cap mon 'allow *'
    ceph-authtool --create-keyring /etc/ceph/ceph.client.admin.keyring \
        --gen-key -n client.admin --cap mon 'allow *' --cap osd 'allow *' --cap mds 'allow *' --cap mgr 'allow *'
    ceph-authtool --create-keyring /var/lib/ceph/bootstrap-osd/ceph.keyring \
        --gen-key -n client.bootstrap-osd --cap mon 'profile bootstrap-osd' --cap mgr 'allow r'
    ceph-authtool /etc/ceph/ceph.mon.keyring --import-keyring /etc/ceph/ceph.client.admin.keyring
    ceph-authtool /etc/ceph/ceph.mon.keyring --import-keyring /var/lib/ceph/bootstrap-osd/ceph.keyring
    chown ceph:ceph \
        /etc/ceph/${cname}.conf \
        /etc/ceph/ceph.mon.keyring \
        /etc/ceph/ceph.client.admin.keyring \
        /var/lib/ceph/bootstrap-osd/ceph.keyring

    rm -rf /tmp/monmap && monmaptool --create --add ${name} ${ipaddr} --fsid ${fsid} /tmp/monmap
    sudo -u ceph mkdir -p /var/lib/ceph/mon/${cname}-${name}
    sudo -u ceph ceph-mon --cluster ${cname} --mkfs -i ${name} --monmap /tmp/monmap --keyring /etc/ceph/ceph.mon.keyring
    systemctl enable --now ceph-mon@${name}
    ceph -s
}

init_ceph_mgr() {
    local cname=${1}
    local name=${HOSTNAME:-$(hostname)}
    local ipaddr=$(hostname -i)
    ceph mon enable-msgr2
    ceph mgr module enable pg_autoscaler
    sudo -u ceph mkdir /var/lib/ceph/mgr/${cname}-${name}
    ceph auth get-or-create mgr.${name} mon 'allow profile mgr' osd 'allow *' mds 'allow *'
    ceph auth get-or-create mgr.${name} > /etc/ceph/ceph.mgr.admin.keyring
    sudo -u ceph cp /etc/ceph/ceph.mgr.admin.keyring /var/lib/ceph/mgr/${cname}-${name}/keyring
    systemctl enable --now ceph-mgr@${name}
    ceph -s
}

add_new_mon() {
    local cname=${1:-ceph}
    local name=${HOSTNAME:-$(hostname)}
    local ipaddr=$(hostname -i)
    mon_key=/tmp/mon.key
    mon_map=/tmp/mon.map
    sudo -u ceph ceph auth get mon. -o ${mon_key}
    sudo -u ceph ceph mon getmap -o ${mon_map}
    sudo -u ceph mkdir -p /var/lib/ceph/mon/${cname}-${name}
    sudo -u ceph ceph-mon --cluster ${cname} --mkfs -i ${name} --monmap ${mon_map} --keyring ${mon_key}
    systemctl enable --now ceph-mon@${name}
    ceph -s
}

add_osd_bluestore() {
    local disk=${1}
    # copy /var/lib/ceph/bootstrap-osd/ceph.keyring from monitor node to osd node
    [ -e "/var/lib/ceph/bootstrap-osd/ceph.keyring" ] && ceph-volume lvm create --data ${disk}
}

teardown() {
    local name=${HOSTNAME:-$(hostname)}
    systemctl disable --now ceph-mon@${name}
    systemctl disable --now ceph-mgr@${name}
    pkill -9 ceph-osd
    rm -fr \
    /etc/ceph/* \
    /var/lib/ceph/bootstrap-osd/ceph.keyring \
    /var/lib/ceph/mon/* \
    /var/lib/ceph/mgr/*
}
# remote execute function end!
################################################################################
SSH_PORT=${SSH_PORT:-60022}
remote_func() {
    local ipaddr=${1}
    local port=${2}
    local user=${3}
    local func_name=${4}
    shift 4
    local args=("$@")
    debug_msg "run ${func_name}@${ipaddr}:${port} as ${user}\n"
    local ssh_opt="-o StrictHostKeyChecking=no -o ServerAliveInterval=60 -p${port} ${user}@${ipaddr}"
    try ssh ${ssh_opt} /bin/bash -s << EOF
$(typeset -f "${func_name}" 2>/dev/null)
${func_name} ${args[@]}
EOF
}

remove_ceph_cfg() {
    local ipaddr=${1}
    info_msg "${ipaddr} teardown all ceph config!\n"
    remote_func ${ipaddr} ${SSH_PORT} "root" "teardown"
}

download() {
    local ipaddr=${1}
    local port=${2}
    local user=${3}
    local rfile=${4}
    local lfile=${5}
    try scp -P${port} ${user}@${ipaddr}:${rfile} ${lfile}
}

upload() {
    local lfile=${1}
    local ipaddr=${2}
    local port=${3}
    local user=${4}
    local rfile=${5}
    try scp -P${port} ${lfile} ${user}@${ipaddr}:${rfile}
}

inst_ceph_mon() {
    local cname=${1}
    shift 1
    local mon=("$@")
    local ipaddr=${mon[0]}
    mon[0]=
    info_msg "${ipaddr} ceph mgr install the first mon node!\n"
    remote_func ${ipaddr} ${SSH_PORT} "root" init_first_mon "${cname}"
    remote_func ${ipaddr} ${SSH_PORT} "root" init_ceph_mgr "${cname}"
    download ${ipaddr} ${SSH_PORT} "root" "/etc/ceph/${cname}.conf" "${DIRNAME}/${cname}.conf"
    download ${ipaddr} ${SSH_PORT} "root" "/etc/ceph/ceph.client.admin.keyring" "${DIRNAME}/ceph.client.admin.keyring"
    download ${ipaddr} ${SSH_PORT} "root" "/var/lib/ceph/bootstrap-osd/ceph.keyring" "${DIRNAME}/ceph.keyring"
    #now add other mons
    for ipaddr in ${mon[@]}; do
        info_msg "****** $ipaddr init mon.\n" 
        upload "${DIRNAME}/${cname}.conf" ${ipaddr} ${SSH_PORT} "root" "/etc/ceph/${cname}.conf"
        upload "${DIRNAME}/ceph.client.admin.keyring" ${ipaddr} ${SSH_PORT} "root" "/etc/ceph/ceph.client.admin.keyring"
        upload "${DIRNAME}/ceph.keyring" ${ipaddr} ${SSH_PORT} "root" "/var/lib/ceph/bootstrap-osd/ceph.keyring"
        remote_func ${ipaddr} ${SSH_PORT} "root" "chmod 644 /etc/ceph/ceph.client.admin.keyring"
        remote_func ${ipaddr} ${SSH_PORT} "root" "chown ceph:ceph /var/lib/ceph/bootstrap-osd/ceph.keyring"
        remote_func ${ipaddr} ${SSH_PORT} "root" add_new_mon "${cname}"
    done
}

inst_ceph_osd() {
    local cname=${1}
    shift 1
    local osd=("$@")
    local ipaddr= dev=
    [ -e "${DIRNAME}/${cname}.conf" ] || exit_msg "nofound ${DIRNAME}/${cname}.conf\n"
    [ -e "${DIRNAME}/ceph.client.admin.keyring" ] || exit_msg "nofound ${DIRNAME}/ceph.client.admin.keyring\n"
    [ -e "${DIRNAME}/ceph.keyring" ] || exit_msg "nofound ${DIRNAME}/ceph.keyring\n"
    for ipaddr in ${osd[@]}; do
        dev=${ipaddr##*:}
        [ -z "${dev}" ] && continue
        ipaddr=${ipaddr%:*}
        info_msg "****** ${ipaddr}:${dev} init osd.\n"
        upload "${DIRNAME}/${cname}.conf" ${ipaddr} ${SSH_PORT} "root" "/etc/ceph/${cname}.conf"
        upload "${DIRNAME}/ceph.client.admin.keyring" ${ipaddr} ${SSH_PORT} "root" "/etc/ceph/ceph.client.admin.keyring"
        upload "${DIRNAME}/ceph.keyring" ${ipaddr} ${SSH_PORT} "root" "/var/lib/ceph/bootstrap-osd/ceph.keyring"
        remote_func ${ipaddr} ${SSH_PORT} "root" "chmod 644 /etc/ceph/ceph.client.admin.keyring"
        remote_func ${ipaddr} ${SSH_PORT} "root" "chown ceph:ceph /var/lib/ceph/bootstrap-osd/ceph.keyring"
        remote_func ${ipaddr} ${SSH_PORT} "root" add_osd_bluestore "${dev}"
    done
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -c|--cluster   <cluster name> ceph cluster name, default "ceph"
        -m|--mon       <ceph mon ip>  ceph mon node, (first mon is mon/mgr)
        -o|--osd       <ceph osd ip>  ceph osd node
        --teardown     <ip>           remove all ceph config
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
    Example:
        SSH_PORT default is 60022
        SSH_PORT=22 ${SCRIPTNAME} -c ceph -m 192.168.168.101 -m 192.168.168.102 -o 192.168.168.101:/dev/vda2 \
               -o 192.168.168.102:/dev/vda2 -o 192.168.168.103:/dev/sda
        ceph node hosts:
               127.0.0.1       localhost
               192.168.168.101 server1
               .....
               192.168.168.... servern
EOF
    exit 1
}
main() {
    local mon=() osd=() cluster=ceph
    local opt_short="c:m:o:"
    local opt_long="cluster:,mon:,osd:,teardown:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -c | --cluster) shift; cluster=${1}; shift;;
            -m | --mon)     shift; mon+=(${1}); shift;;
            -o | --osd)     shift; osd+=(${1}); shift;;
            --teardown)     shift; remove_ceph_cfg ${1}; shift;;
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
    [ "$(array_size mon)" -gt "0" ] && inst_ceph_mon "${cluster}" "${mon[@]}"
    [ "$(array_size osd)" -gt "0" ] && inst_ceph_osd "${cluster}" "${osd[@]}"
    info_msg "ALL DONE\n"
    echo "mon is allowing insecure global_id reclaim,"
    echo "ceph config set mon auth_allow_insecure_global_id_reclaim false"
    return 0
}
main "$@"
