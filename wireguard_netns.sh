#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
setup_wg() {
    local wg_if="$1"
    local CONFIG_FILE="$2"
    local routes="$3" #0.0.0.0/0 via 1.1.1.1,192.168.0.0/16 via 1.1.1.2
    local ns_name="$4"
    # fork from wg-quick begin
    local line= stripped= key= value= interface_section=0
    local ADDRESSES=() MTU=1420 WG_CONFIG=""
    shopt -s nocasematch
    shopt -s extglob
    while read -r line || [[ -n $line ]]; do
        stripped="${line%%\#*}"
        key="${stripped%%=*}"; key="${key##*([[:space:]])}"; key="${key%%*([[:space:]])}"
        value="${stripped#*=}"; value="${value##*([[:space:]])}"; value="${value%%*([[:space:]])}"
        [[ $key == "["* ]] && interface_section=0
        [[ $key == "[Interface]" ]] && interface_section=1
        if [[ $interface_section -eq 1 ]]; then
            case "$key" in
                Address) ADDRESSES+=( ${value//,/ } ); continue ;;
                MTU) MTU="$value"; continue ;;
                DNS) continue ;;
                Table) continue ;;
                PreUp) continue ;;
                PreDown) continue ;;
                PostUp) continue ;;
                PostDown) continue ;;
                SaveConfig) continue ;;
            esac
        fi
        WG_CONFIG+="$line"$'\n'
    done < "$CONFIG_FILE"
    shopt -u extglob
    shopt -u nocasematch
    # fork from wg-quick end
    try ip link add ${wg_if} type wireguard
    [ ${DRYRUN:-0} = 0 ] || vinfo_msg <<< "$WG_CONFIG"
    try wg setconf "${wg_if}" <(echo "$WG_CONFIG")
    [[ -z "${ns_name}" ]] || try ip link set "${wg_if}" netns "${ns_name}"
    local x=
    for x in "${ADDRESSES[@]}"; do
        try ${ns_name:+ip netns exec "${ns_name}"} ip addr add "${x}" dev "${wg_if}" || return 1
    done
    try ${ns_name:+ip netns exec "${ns_name}"} ip link set mtu "${MTU}" up dev "${wg_if}"
    # deal routes
    while read -rd "," -r x; do
        try ${ns_name:+ip netns exec ${ns_name}} ip route add $x dev ${wg_if} || return 2
    done <<< "${routes},"
    return 0
}

cleanup_wg() {
    local wg_if="$1"
    local ns_name="$2"
    try ${ns_name:+ip netns exec "${ns_name}"} ip link set "${wg_if}" down
    try ${ns_name:+ip netns exec "${ns_name}"} ip link del "${wg_if}"
}

setup_ns() {
    local ns_name="$1"
    try ip netns add ${ns_name}
    try ip netns exec ${ns_name} ip addr add 127.0.0.1/8 dev lo
    try ip netns exec ${ns_name} ip link set lo up
}

netns_exists() {
    local ns_name="$1"
    # Check if a namespace named $ns_name exists.
    # Note: Namespaces with a veth pair are listed with '(id: 0)' (or something). We need to remove this before lookin
    ip netns list | sed 's/ *(id: [0-9]\+)$//' | grep --quiet --fixed-string --line-regexp "${ns_name}"
}

cleanup_ns() {
    local ns_name="$1"
    try ip netns del ${ns_name} || true
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -w|--wg    *  wireguard ifname
        -c|--conf  *  wireguard conf file
        -n|--ns       net namespace
        -g|--gw       gateway 
                      example: "0.0.0.0/0 via 1.1.1.1,192.168.0.0/26,192.167.0.0/16 via 1.1.1.2"
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}

main() {
    is_user_root || exit_msg "root user need!!\n"
    local wg_if= wg_conf= ns_name= gateway=
    local opt_short="w:c:n:i:g:"
    local opt_long="wg:,conf:,ns:,ip:,gw:,"
    opt_short+="ql:dVh"
    opt_long+="quite,log:,dryrun,version,help"
    readonly local __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -w | --wg)      shift; wg_if=${1}; shift;;
            -c | --conf)    shift; wg_conf=${1}; shift;;
            -n | --ns)      shift; ns_name=${1}; shift;;
            -g | --gw)      shift; gateway=${1}; shift;;
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; set_loglevel ${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; exit_msg "${SCRIPTNAME} version\n";;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    [[ -z "${wg_if}" ]] && usage "wireguard ifname must input"
    [[ ${wg_if} =~ ^[a-zA-Z0-9_=+.-]{1,15}$ ]] || usage "wireguard ifname wrong"
    [[ -z "${wg_conf}" ]] && usage "wireguard config file must input"
    file_exists "${wg_conf}" || exit_msg "file ${wg_conf} no found!!\n"
    require env bash ip wg
    [[ -z "${ns_name}" ]] || {
        netns_exists "${ns_name}" && exit_msg "netns ${ns_name} exist!!\n"
        setup_ns "${ns_name}" || { cleanup_ns "${ns_name}"||true; exit_msg "netns ${ns_name} setup error!\n"; }
    }
    setup_wg "${wg_if}" "${wg_conf}" "${gateway}" "${ns_name}" || {
        cleanup_wg "${wg_if}" "${ns_name}" || true
        [[ -z "${ns_name}" ]] || cleanup_ns "${ns_name}" || true
        exit_msg "wireguard ${wg_if} setup error!\n"
    }
    info_msg "wireguard ${wg_if}${ns_name:+@"${ns_name}"} OK\n"
    trap "echo 'CTRL+C!!!!'" SIGINT
    ${DRYRUN:+echo }$(truecmd env) -i \
        SHELL=$(truecmd bash) \
        HOME=/root \
        TERM=${TERM} \
        ${ns_name:+$(truecmd ip) netns exec "${ns_name}"} \
        $(truecmd bash) --rcfile <(echo "PS1=\"(${wg_if}${ns_name:+@${ns_name}})\$PS1\"") || true
    cleanup_wg "${wg_if}" "${ns_name}" || true
    [[ -z "${ns_name}" ]] || cleanup_ns "${ns_name}" || true
    return 0
}
main "$@"
