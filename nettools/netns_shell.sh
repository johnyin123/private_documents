#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("f6a904e[2023-12-07T07:42:46+08:00]:netns_shell.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
setup_nameserver() {
    ns_name=$1
    nameserver=$2

    try mkdir -p "/etc/netns/$ns_name"
    try echo "nameserver ${nameserver}" \> "/etc/netns/$ns_name/resolv.conf"
    try cat \> /etc/netns/$ns_name/bash.bashrc <<EOF
export PROMPT_COMMAND=""
alias ll='ls -lh --group-directories-first'
export LANG=zh_CN.UTF-8
export LANGUAGE=zh_CN:zh
export LC_CTYPE="zh_CN.UTF-8"
export LC_NUMERIC="zh_CN.UTF-8"
export LC_TIME="zh_CN.UTF-8"
export LC_COLLATE="zh_CN.UTF-8"
export LC_MONETARY="zh_CN.UTF-8"
export LC_MESSAGES="zh_CN.UTF-8"
export LC_PAPER="zh_CN.UTF-8"
export LC_NAME="zh_CN.UTF-8"
export LC_ADDRESS="zh_CN.UTF-8"
export LC_TELEPHONE="zh_CN.UTF-8"
export LC_MEASUREMENT="zh_CN.UTF-8"
export LC_IDENTIFICATION="zh_CN.UTF-8"
# DISPLAY=:0.0 su johnyin -c /opt/google/chrome/google-chrome>/dev/null 2>&1 &
EOF
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -i|--ipaddr <cidr> * ipaddress for netns eth0
        -n|--nsname <name> * netns name
        -b|--bridge <br>   * host bridge for connect
        -g|--gw <gateway>    ns gateway, default .1
        -r|--dns <ipaddr>    dns server
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
# ip rule add from 192.168.169.0/24 table 200 || true
# ip route add default via <GW> dev <DEV> table 200 || true
# ip route add 192.168.169.0/24 dev br-ext scope link table 200 || true
# # iptables -t nat -A POSTROUTING -s 192.168.169.0/24 -j MASQUERADE || true
# #
# ip route delete 192.168.169.0/24 table 200 || true
# ip route delete default table 200 || true
# ip rule delete from 192.168.169.0/24 || true
EOF
    exit 1
}

main() {
    local ipaddr= ns_name= host_br= gateway= dns=
    local opt_short="i:n:b:g:r:"
    local opt_long="ipaddr:,nsname:,bridge:,gw:,dns:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -a -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -i | --ipaddr)  shift; ipaddr=${1}; shift;;
            -n | --nsname)  shift; ns_name=${1}; shift;;
            -b | --bridge)  shift; host_br=${1}; shift;;
            -g | --gw)      shift; gateway=${1}; shift;;
            -r | --dns)     shift; dns=${1}; shift;;
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
    is_user_root || exit_msg "root need!!\n"
    [ -z "${ipaddr}"  ] && usage "ipaddr must input"
    [ -z "${ns_name}" ] && usage "nsname must input"
    [ -z "${host_br}" ] && usage "bridge must input"
    is_ipv4_subnet "${ipaddr}" || usage "ipaddr ip/mask"
    gateway=${gateway:-"${ipaddr%.*}.1"}
    dns=${dns:-"114.114.114.114"}
    info_msg "IPADDR=${ipaddr}\n"
    netns_exists "${ns_name}" && exit_msg "${ns_name} exist!!\n"
    bridge_exists "${host_br}" || exit_msg "${host_br} no found!!\n"
    setup_ns "${ns_name}" || { cleanup_ns "${ns_name}"; exit_msg "netns ${ns_name} setup error!\n"; }
    maybe_netns_setup_veth ${ns_name}-eth0 ${ns_name}-eth1 "" || { cleanup_ns "${ns_name}"; exit_msg "setup veth error!\n"; }
    maybe_netns_bridge_addlink "${host_br}" "${ns_name}-eth1" "" || { maybe_netns_bridge_dellink "${ns_name}-eth1" ""; cleanup_ns "${ns_name}"; exit_msg "bridge add link error!\n"; }
    maybe_netns_addlink "${ns_name}-eth0" "${ns_name}" "eth0" || { maybe_netns_bridge_dellink "${ns_name}-eth1" ""; cleanup_ns "${ns_name}"; exit_msg "netns add link error!\n"; }
    maybe_netns_run "ip address add ${ipaddr} dev eth0" "${ns_name}" ||  true
    maybe_netns_run "ip route add default via ${gateway}" "${ns_name}" || true
    setup_nameserver "${ns_name}" "${dns}" || true
    #( nsenter --net=/var/run/netns/${ns_name} su johnyin /opt/google/chrome/google-chrome || true ) &>/dev/null &
    info_msg "DISPLAY=:0.0 su johnyin -c /opt/google/chrome/google-chrome\n"
    maybe_netns_shell "${host_br}" "${ns_name}" || true

    maybe_netns_bridge_dellink "${ns_name}-eth1" ""
    cleanup_link "${ns_name}-eth1"
    cleanup_ns "${ns_name}"
    info_msg "Exit success\n"
    return 0
}
main "$@"
