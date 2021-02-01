#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("wireguard_netns.sh - 7ef7607 - 2021-01-29T16:01:58+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
setup_wg() {
    local wg_if="$1"
    local CONFIG_FILE="$2"
    local ns_name="${3:-}"
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
    vinfo_msg <<< "$WG_CONFIG"
    try wg setconf "${wg_if}" <(echo "$WG_CONFIG")
    maybe_netns_addlink "${wg_if}" "${ns_name}"
    local x=
    for x in "${ADDRESSES[@]}"; do
        maybe_netns_run "ip addr add ${x} dev ${wg_if}" "${ns_name}" || return 1
    done
    maybe_netns_run "ip link set mtu ${MTU} up dev ${wg_if}" "${ns_name}" || return 2
    # deal routes
    for x in $(while read -r _ x; do for x in $x; do [[ $x =~ ^[0-9a-z:.]+/[0-9]+$ ]] && echo "$x"; done; done < <(maybe_netns_run "wg show ${wg_if} allowed-ips" "${ns_name}") | sort -nr -k 2 -t /); do
        [[ -n $(maybe_netns_run "ip route show match $x" "${ns_name}" 2>/dev/null) ]] && {
            warn_msg "${wg_if} route skip: $(ip route show match $x)($x)\n"
            continue
        }
        maybe_netns_run "ip route add $x dev ${wg_if}" "${ns_name}" || return 3
    done
#    while read -rd "," -r x; do
#        maybe_netns_run "ip route add $x dev ${wg_if}" "${ns_name}" || return 3
#    done <<< "${routes},"
    return 0
}

cleanup_wg() {
    local wg_if="$1"
    local ns_name="${2:-}"
    maybe_netns_run "ip link set ${wg_if} down" "${ns_name}"
    maybe_netns_run "ip link del ${wg_if}" "${ns_name}"
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -w|--wg    *  wireguard ifname
        -c|--conf  *  wireguard conf file
        -n|--ns       net namespace
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}

main() {
    local wg_if= wg_conf= ns_name=
    local opt_short="w:c:n:i:g:"
    local opt_long="wg:,conf:,ns:,ip:,gw:,"
    opt_short+="ql:dVh"
    opt_long+="quite,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -w | --wg)      shift; wg_if=${1}; shift;;
            -c | --conf)    shift; wg_conf=${1}; shift;;
            -n | --ns)      shift; ns_name=${1}; shift;;
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
    [[ -z "${wg_if}" ]] && usage "wireguard ifname must input"
    [[ ${wg_if} =~ ^[a-zA-Z0-9_=+.-]{1,15}$ ]] || usage "wireguard ifname wrong"
    [[ -z "${wg_conf}" ]] && usage "wireguard config file must input"
    is_user_root || exit_msg "root user need!!\n"
    file_exists "${wg_conf}" || exit_msg "file ${wg_conf} no found!!\n"
    directory_exists "/sys/class/net/${wg_if}" && exit_msg "interface ${wg_if} already exists!!\n"
    require env bash ip wg
    [[ -z "${ns_name}" ]] || {
        netns_exists "${ns_name}" && exit_msg "netns ${ns_name} exist!!\n"
        setup_ns "${ns_name}" || { cleanup_ns "${ns_name}"||true; exit_msg "netns ${ns_name} setup error!\n"; }
    }
    setup_wg "${wg_if}" "${wg_conf}" "${ns_name}" || {
        cleanup_wg "${wg_if}" "${ns_name}" || true
        [[ -z "${ns_name}" ]] || cleanup_ns "${ns_name}" || true
        exit_msg "wireguard ${wg_if} setup error!\n"
    }
    try mkdir -p "/etc/netns/${ns_name}"
    try echo "nameserver 114.114.114.114" \> "/etc/netns/${ns_name}/resolv.conf"
    info_msg "wireguard ${wg_if}${ns_name:+@"${ns_name}"} OK\n"
    trap "echo 'CTRL+C!!!!'" SIGINT
    maybe_netns_shell "${wg_if}" "${ns_name}"
    cleanup_wg "${wg_if}" "${ns_name}" || true
    [[ -z "${ns_name}" ]] || cleanup_ns "${ns_name}" || true
    return 0
}
main "$@"
