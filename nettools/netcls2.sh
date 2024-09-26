#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("60b10b5[2024-09-26T13:27:01+08:00]:netcls2.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}, cgroup v2 version
        env: FW=nft, default nftables, other iptables
        -m|--fwmark   <int>   *  *  fwmark, 1 to 2147483647
        -p|--pid      <int>   *     pid, support multi input
        --remove                 x  remove pid from netcls
        -g|--gw       <ipv4>  x  *  gateway, ipv4 gateway address
        --slice       <str>   x     slice name for cgroup2 netcls
        --rule        <int>   x     ip rule table id, default fwmark%251+1
        --destroy             x     destroy netcls and ip rules !!!
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        net.ipv4.conf.all.rp_filter=0/2
        # # multi hole address, if not default interface, maybe need snat
        iptables -t nat -A POSTROUTING -o client -j SNAT --to-source 192.168.32.2
        nft add rule nat postrouting oif client snat to 192.168.32.2
        OR: nft add rule nat postrouting oif client masquerade
        # # use ip route not work!!!
        # # ip route replace default via 192.168.32.1 src 192.168.32.2 table xxx
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
        ##################
        ./${SCRIPTNAME} --fwmark 44 --slice test -g 192.168.41.1
        systemd-run -q --user --scope --unit chrome --slice test.slice -- google-chrome
EOF
    exit 1
}

addin_netcls() {
    local slice=${1}
    local pid=${2}
    local process="$(cat /proc/${pid}/comm 2>/dev/null)"
    info_msg "add pid: ${pid}(${process:-N/A}) in ${slice}\n"
    try "echo ${pid} > /sys/fs/cgroup/${slice}.slice/cgroup.procs" 2>/dev/null || true
}

delout_netcls() {
    local slice=${1}
    local pid=${2}
    local process="$(cat /proc/${pid}/comm 2>/dev/null)"
    try "echo ${pid} > /sys/fs/cgroup/${slice}.slice/cgroup.procs" 2>/dev/null || true
    try "echo ${pid} > /sys/fs/cgroup/cgroup.procs" 2>/dev/null || true
}
setup_fw() {
    local fwmark=${1}
    local slice=${2}
    local type=${FW:-nft}
    case "${type}" in
        nft)
            cat <<EONFT | try nft -f /dev/stdin
# flush table ip ${slice}_svc
# delete table ip ${slice}_svc
table ip ${slice}_svc {
    # # Only for local mode
    chain output {
        type route hook output priority mangle; policy accept;
        socket cgroupv2 level 1 "${slice}.slice" counter meta l4proto { tcp, udp } meta mark set ${fwmark}
    }
	chain postrouting {
		type nat hook postrouting priority srcnat; policy accept;
        meta mark ${fwmark} counter masquerade
    }
}
EONFT
            ;;
        *)
            # # Only for local mode
            try iptables -t mangle -A OUTPUT -m cgroup --path ${slice}.slice -j MARK --set-mark ${fwmark}
            # # Only for router mode
            try iptables -t nat -A POSTROUTING -m cgroup --path ${slice}.slice -j MASQUERADE
            ;;
    esac
}
create_netrule() {
    local fwmark=${1}
    local rule_table=${2}
    local slice=${3}
    local gateway=${4}
    try ip rule show fwmark ${fwmark} | grep -qe "lookup\s*${rule_table}" && { warn_msg "netrule: ${rule_table} already exists!!!\n"; return 1; }
    info_msg "create new ip rule ${rule_table}\n"
    try ip route flush table ${rule_table} 2>/dev/null || true
    try ip rule delete fwmark ${fwmark} table ${rule_table} 2>/dev/null || true

    try mkdir -p /sys/fs/cgroup/${slice}.slice
    setup_fw "${fwmark}" "${slice}" || { error_msg "firewall setup error\n"; return 2; }

    try ip rule add fwmark ${fwmark} table ${rule_table}
    try ip route replace default via ${gateway} table ${rule_table}
    local default_route=$(ip -4 route show default | awk '{ print $3 }')
    info_msg "private ipaddress use ${default_route}\n"
    ip route | grep kernel | while read line; do
        try ip route add $line table ${rule_table} || true
    done
    # try ip route replace 10.0.0.0/8     via ${default_route} table ${rule_table} || true
    # try ip route replace 172.16.0.0/12  via ${default_route} table ${rule_table} || true
    # try ip route replace 192.168.0.0/16 via ${default_route} table ${rule_table} || true
}

main() {
    # # FWMARK 1 to 2147483647
    # # RULE_TABLE 1 to 252
    # # CLASSID 0x00000001 to 0xFFFFFFFF
    local pid=() gateway="" fwmark=""
    local slice="" rule="" remove="" destroy=""
    local opt_short="p:g:m:"
    local opt_long="pid:,gw:,fwmark:,slice:,rule:,remove,destroy,"
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
            --slice)        shift; slice=${1}; shift;;
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
    rule=${rule:-$((fwmark%251+1))}
    slice="${slice:-JOHNYIN-${fwmark}}"
    local cgroup_v2_root="$(mount -t cgroup2 | head -n1 | grep -oP '^cgroup2 on \K\S+')"
    [ -f "${cgroup_v2_root}/cgroup.procs" ] || exit_msg "only cgroup2 support!\n"
    info_msg "FWMARK=${fwmark}.............\n"
    [ "$(array_size pid)" -gt "0" ] && {
        for _pid in ${pid[@]}; do
            [ -z "${remove}" ] && {
                addin_netcls "${slice}" "${_pid}"
            } || {
                delout_netcls "${slice}" "${_pid}"
            }
        done
        for _pid in $(cat /sys/fs/cgroup/${slice}.slice/cgroup.procs); do
            local process="$(cat /proc/${_pid}/comm 2>/dev/null)"
            info_msg "${slice} contains: ${_pid}(${process})\n"
        done
        info_msg "ALL DONE!\n"
        return 0
    }
    [ -z "${destroy}" ] || {
        try "ip route flush table ${rule} 2>/dev/nul"l || true
        try "ip rule delete fwmark ${fwmark} table ${rule} 2>/dev/null" || true
        try "iptables -t mangle -D OUTPUT -m cgroup --path ${slice}.slice -j MARK --set-mark ${fwmark} 2>/dev/null || true"
        try "iptables -t nat -D POSTROUTING -m cgroup --path ${slice}.slice -j MASQUERADE 2>/dev/null || true"
        try "nft flush table ip ${slice}_svc 2>/dev/null || true"
        try "nft delete table ip ${slice}_svc 2>/dev/null || true"
        for _pid in $(cat /sys/fs/cgroup/${slice}.slice/cgroup.procs); do
            delout_netcls "${slice}" "${_pid}"
        done
        try rmdir /sys/fs/cgroup/${slice}.slice || true
        # # rm all sub dir so can purge /sys/fs/cgroup/net_cls
        # umount /sys/fs/cgroup/net_cls && rmdir /sys/fs/cgroup/net_cls
        info_msg "ALL DONE!\n"
        return 0
    }
    create_netrule "${fwmark}" "${rule}" "${slice}" "${gateway}" || {
        ip rule show fwmark ${fwmark}
        ip route show table ${rule}
    }
    return 0
}
auto_su "$@"
main "$@"
