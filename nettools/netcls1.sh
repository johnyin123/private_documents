#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2024-08-06T13:25:23+08:00]:netcls1.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}, cgroup v1 version
        -m|--fwmark   <int>   *  *  fwmark, 1 to 2147483647
        -p|--pid      <int>   *     pid, support multi input
        --remove                 x  remove pid from netcls
        -g|--gw       <ipv4>  x  *  gateway, ipv4 gateway address
        --classid     <int>   x     netcls classid, default equal fwmark
        --rule        <int>   x     ip rule table id, default fwmark%251+1
        --destroy             x     destroy netcls and ip rules !!!
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
    The Network classifier cgroup provides an interface to
tag network packets with a class identifier (classid).
/proc/sys/net/ipv4/conf/all/rp_filter=0/2
    exam:
        # # list all fwmark
        ip rule | grep fwmark | grep -o "0x[^ ]*" | xargs -I@  printf "FWMARK: %d\n" @
        # create netcls via gateway 192.168.41.1, fwmark 44
        ./${SCRIPTNAME} --fwmark 44 -g 192.168.41.1
        # add pid in netcls
        ./${SCRIPTNAME} --fwmark 44 -p <p1> --pid <p2>
        # remove pid out netcls
        ./${SCRIPTNAME} --fwmark 44 -p <p1> --pid <p2> --remove
        # destroy netcls fwmark 44
        ./${SCRIPTNAME} --fwmark 44 --destroy
EOF
    exit 1
}

create_netcls() {
    local netcls_name=${1}
    local classid=${2}
    directory_exists /sys/fs/cgroup/net_cls/${netcls_name} && { warn_msg "netcls: ${netcls_name} already exists!!!\n"; return 1; }
    info_msg "create cgroup-v1/net_cls ${netcls_name}\n"
    try mkdir -p /sys/fs/cgroup/net_cls 2>/dev/null
    # # or check /sys/fs/cgroup/net_cls/tasks exist
    mountpoint -q /sys/fs/cgroup/net_cls || try mount -t cgroup -onet_cls net_cls /sys/fs/cgroup/net_cls
    try mkdir -p /sys/fs/cgroup/net_cls/${netcls_name}
    try "echo ${classid} > /sys/fs/cgroup/net_cls/${netcls_name}/net_cls.classid"
}

addin_netcls() {
    local netcls_name=${1}
    local pid=${2}
    local process="$(cat /proc/${pid}/comm 2>/dev/null)"
    info_msg "add pid: ${pid}(${process:-N/A}) in ${netcls_name}\n"
    try "echo ${pid} > /sys/fs/cgroup/net_cls/${netcls_name}/tasks" 2>/dev/null || true
}

delout_netcls() {
    local netcls_name=${1}
    local pid=${2}
    local process="$(cat /proc/${pid}/comm 2>/dev/null)"
    info_msg "del pid: ${pid}(${process:-N/A}) out ${netcls_name}\n"
    try "echo ${pid} > /sys/fs/cgroup/net_cls/tasks" 2>/dev/null || true
}

create_netrule() {
    local fwmark=${1}
    local rule_table=${2}
    local classid=${3}
    local gateway=${4}
    try ip rule show fwmark ${fwmark} | grep -qe "lookup\s*${rule_table}" && { warn_msg "netrule: ${rule_table} already exists!!!\n"; return 1; }
    info_msg "create new ip rule ${rule_table}\n"
    try ip route flush table ${rule_table} 2>/dev/null || true
    try ip rule delete fwmark ${fwmark} table ${rule_table} 2>/dev/null || true
    # iptables -t mangle -D OUTPUT -m cgroup --cgroup ${classid} -j MARK --set-mark ${fwmark} 2>/dev/null || true
    # iptables -t nat -D POSTROUTING -m cgroup --cgroup ${classid} -j MASQUERADE 2>/dev/null || true
    try iptables -t mangle -A OUTPUT -m cgroup --cgroup ${classid} -j MARK --set-mark ${fwmark}
    try iptables -t nat -A POSTROUTING -m cgroup --cgroup ${classid} -j MASQUERADE
    # # iptables -A OUTPUT -m cgroup ! --cgroup ${CLASSID} -j DROP
    try ip rule add fwmark ${fwmark} table ${rule_table}
    try ip route replace default via ${gateway} table ${rule_table}
    local default_route=$(ip -4 route show default | awk '{ print $3 }')
    info_msg "private ipaddress use ${default_route}\n"
    try ip route replace 10.0.0.0/8     via ${default_route} || true
    try ip route replace 172.16.0.0/12  via ${default_route} || true
    try ip route replace 192.168.0.0/16 via ${default_route} || true
}

main() {
    # # FWMARK 1 to 2147483647
    # # RULE_TABLE 1 to 252
    # # CLASSID 0x00000001 to 0xFFFFFFFF
    local pid=() gateway="" fwmark=""
    local classid="" rule="" netcls_name="" remove="" destroy=""
    local opt_short="p:g:m:"
    local opt_long="pid:,gw:,fwmark:,classid:,rule:,remove,destroy,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -p | --pid)     shift; pid+=(${1}); shift;;
            --remove)       shift; remove=1;;
            -g | --gw)      shift; is_ipv4 ${1} || usage "gateway is ipv4"; gateway=${1}; shift;;
            -m | --fwmark)  shift; [[ "${1}" =~ ^[0-9]+$ ]] || usage "fwmark sould 1 to 2147483647"; fwmark=${1}; shift;;
            --classid)      shift; classid=${1}; shift;;
            --rule)         shift; rule=${1}; shift;;
            --destroy)      shift; destroy=1;;
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
    [ -z "${fwmark}"  ] && usage "fwmark null"
    classid=${classid:-${fwmark}}
    rule=${rule:-$((fwmark%251+1))}
    netcls_name="JOHNYIN-${fwmark}"
    info_msg "FWMARK=${fwmark}.............\n"
    [ "$(array_size pid)" -gt "0" ] && {
        for _pid in ${pid[@]}; do
            [ -z "${remove}" ] && {
                addin_netcls "${netcls_name}" "${_pid}"
            } || {
                delout_netcls "${netcls_name}" "${_pid}"
            }
        done
        info_msg "ALL DONE!\n"
        return 0
    }
    [ -z "${destroy}" ] || {
        try "ip route flush table ${rule} 2>/dev/nul"l || true
        try "ip rule delete fwmark ${fwmark} table ${rule} 2>/dev/null" || true
        try "iptables -t mangle -D OUTPUT -m cgroup --cgroup ${classid} -j MARK --set-mark ${fwmark} 2>/dev/null" || true
        try "iptables -t nat -D POSTROUTING -m cgroup --cgroup ${classid} -j MASQUERADE 2>/dev/null" || true

        for _pid in $(cat /sys/fs/cgroup/net_cls/${netcls_name}/tasks); do
            delout_netcls "${netcls_name}" "${_pid}"
        done
        try rmdir /sys/fs/cgroup/net_cls/${netcls_name} || true
        info_msg "remove private ipaddr route\n"
        try ip route del 10.0.0.0/8     || true
        try ip route del 172.16.0.0/12  || true
        try ip route del 192.168.0.0/16 || true
        # # rm all sub dir so can purge /sys/fs/cgroup/net_cls
        # umount /sys/fs/cgroup/net_cls && rmdir /sys/fs/cgroup/net_cls
        info_msg "ALL DONE!\n"
        return 0
    }
    create_netcls "${netcls_name}" "${classid}" || {
        for _pid in $(cat /sys/fs/cgroup/net_cls/${netcls_name}/tasks); do
            warn_msg "net_cls attached pid: ${_pid}: $(cat /proc/${_pid}/comm 2>/dev/null)\n"
        done
        exit_msg "create netcls error\n"
    }
    create_netrule "${fwmark}" "${rule}" "${classid}" "${gateway}" || {
        ip rule show fwmark ${fwmark}
        ip route show table ${rule}
    }
    return 0
}
auto_su "$@"
main "$@"
