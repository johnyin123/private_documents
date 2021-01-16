#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("tunnel.sh - 65733ca - 2021-01-17T04:30:24+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
del_ns() {
    debug_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local ns_name="$1"
    #try brctl delif br-ext ${ns_name}-eth1
    try ip link set ${ns_name}-eth1 promisc off || true
    try ip link set ${ns_name}-eth1 down || true
    try ip link set dev ${ns_name}-eth1 nomaster || true
    try ip netns del ${ns_name} || true
    ip link delete ${ns_name}-eth1 || true
    try rm -rf "/etc/netns/${ns_name}" || true
    return 0
}

add_ns() {
    debug_msg "enter [%s]\n" "${FUNCNAME[0]} $*"
    local ns_name="$1"
    local host_br="$2"
    local ns_cidr="$3"
    try ip netns add ${ns_name} || return 4
    try ip netns exec ${ns_name} ip addr add 127.0.0.1/8 dev lo || return 4
    try ip netns exec ${ns_name} ip link set lo up || return 4
    try ip link add ${ns_name}-eth0 type veth peer name ${ns_name}-eth1 || return 4
    #try brctl addif br-ext ${ns_name}-eth1
    try ip link set dev ${ns_name}-eth1 promisc on || return 4
    try ip link set dev ${ns_name}-eth1 up || return 4
    try ip link set dev ${ns_name}-eth1 master ${host_br} || return 4
    try ip link set ${ns_name}-eth0 netns ${ns_name} || return 4
    try ip netns exec ${ns_name} ip link set dev ${ns_name}-eth0 name eth0 up || return 4
    try ip netns exec ${ns_name} ip address add ${ns_cidr} dev eth0 || return 4
    return 0
}

error_clean() {
    local ns_name="$1";shift 1
    del_ns ${ns_name} 1>/dev/null 2>&1 || true
    exit_msg "clean over! $* error\n";
}

setup_nameserver() {
    ns_name=$1
    nameserver=$2

    mkdir -p "/etc/netns/$ns_name"
    echo "nameserver ${nameserver}" > "/etc/netns/$ns_name/resolv.conf"
     cat > /etc/netns/$ns_name/bash.bashrc <<EOF
export PROMPT_COMMAND=""
alias ll='ls -lh'
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
EOF
}

cleanup_nameserver() {
    ns_name=$1
    rm -rf /etc/netns/$ns_name
}

usage() {
    cat <<EOF
${SCRIPTNAME}
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        -i|--ipaddr <cidr> ipaddress for netns eth0
        -n|--nsname <name> netns name
        -b|--bridge <br>   * host bridge for connect
        -g|--gw <gateway>  ns gateway, default .1
        -r|--dns <ipaddr>  dns server
EOF
    exit 1
}

main() {
    local opt_short="ql:dVhi:n:b:g:r:"
    local opt_long="quite,log:,dryrun,version,help,ipaddr:,nsname:,bridge:,gw:,dns:"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -a -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -i | --ipaddr) NS_CIDR=${2}; shift 2;;
            -n | --nsname) NS_NAME=${2}; shift 2;;
            -b | --bridge) HOST_BR=${2}; shift 2;;
            -g | --gw) GATEWAY=${2}; shift 2;;
            -r | --dns) DNS=${2}; shift 2;;
            -q | --quiet) QUIET=1; shift 1 ;;
            -l | --log) set_loglevel ${2}; shift 2 ;;
            -d | --dryrun) DRYRUN=1; shift 1 ;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0 ;;
            -h | --help) shift 1; usage ;;
            --) shift 1; break ;;
            *)  error_msg "Unexpected option: $1.\n"; usage ;;
        esac
    done
    is_user_root || { error_msg "root need!!\n"; usage; }
    local NS_CIDR=${NS_CIDR:-"10.32.149.223/24"}
    local NS_NAME=${NS_NAME:-"web_ns"}
    local HOST_BR=${HOST_BR:-}
    [ -z ${HOST_BR} ] && usage
    local GATEWAY=${GATEWAY:-"${NS_CIDR%.*}.1"}
    local DNS=${DNS:-"202.107.117.11"}
    info_msg "IPADDR=${NS_CIDR}\n"
    netns_exists "${NS_NAME}" && exit_msg "${ns_name} exist!!\n"
    add_ns ${NS_NAME} ${HOST_BR} "${NS_CIDR}" || error_clean "${NS_NAME}" "add netns $?"
    #ip netns exec ${NS_NAME} /bin/bash || true
    #su johnyin /opt/google/chrome/google-chrome
    # try ip netns exec ${NS_NAME} "ip link set eth0 mtu 1300" || true
    try ip netns exec ${NS_NAME} "ip route add default via ${GATEWAY}" || true
    setup_nameserver "${NS_NAME}" "${DNS}"
    #( nsenter --net=/var/run/netns/${NS_NAME} su johnyin /opt/google/chrome/google-chrome || true ) &>/dev/null &
    cat <<'EOF' | ip netns exec ${NS_NAME} /bin/bash -s
su johnyin /opt/google/chrome/google-chrome &> /dev/null &
EOF
    ip netns exec ${NS_NAME} /bin/bash --rcfile <(echo "PS1=\"(ns:${NS_NAME})\$PS1\"") || true
    del_ns ${NS_NAME}
    cleanup_nameserver "${NS_NAME}"
    info_msg "Exit success\n"
    return 0
}
main "$@"
