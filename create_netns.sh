#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("create_netns.sh - 67ac080 - 2021-01-22T10:45:31+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME} <-s/-c> conf
        -s|--start *  start all namespace
        -c|--clean  * cleanup all namespace
        -t|--tmux     tmux shell(in netns)
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help

config file example:
cat <<EO_CFG > conf.conf
OUTBRIDGE=br-test
PEERS=(
    ["M1"]=192.168.168.101/24
    ["M2"]=192.168.168.102/24
    ["M3"]=192.168.168.103/24
    )
EO_CFG
EOF
    exit 1
}

startup() {
    local conf="$1" tmux="$2" OUTBRIDGE= ns_name=
    declare -A PEERS
    source "${conf}"
    #try sysctl -q -w net.ipv4.ip_forward=1
    bridge_exists "${OUTBRIDGE}" "" &>/dev/null && { error_msg "${OUTBRIDGE} exists!\n"; return 1; } 
    maybe_netns_setup_bridge "${OUTBRIDGE}" ""
    for ns_name in ${!PEERS[@]}
    do
        info_msg "setup  ${ns_name}: ${PEERS[$ns_name]}\n"
        setup_ns "${ns_name}"
        maybe_netns_setup_veth "${ns_name}0" "${ns_name}1" ""
        maybe_netns_bridge_addlink "${OUTBRIDGE}" "${ns_name}0" ""
        #try ip link set ${ns_name}0 up
        maybe_netns_addlink "${ns_name}1" "${ns_name}" "eth0"
        maybe_netns_run "ip addr add "${PEERS[$ns_name]}" dev eth0" "${ns_name}"
        debug_msg "ip netns exec ${ns_name} /bin/bash\n"
    done
    ${tumx:+info_msg"tmux not suppport\n"}
    return 0
}

cleanup() {
    local conf="$1" tmux="$2" OUTBRIDGE= ns_name=
    declare -A PEERS
    source "${conf}"

    for ns_name in ${!PEERS[@]}
    do
        cleanup_ns "${ns_name}"
        cleanup_link "${ns_name}0" ""
    done
    ${tumx:+info_msg"tmux not suppport\n"}
    cleanup_link "${OUTBRIDGE}" ""
    return 0
}

main() {
    local action= conf= tmux=
    local opt_short="s:c:t"
    local opt_long="start:,clean:,tmux,"
    opt_short+="ql:dVh"
    opt_long+="quite,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -s | --start)   shift; action=startup; conf=${1}; shift;;
            -c | --clean)   shift; action=cleanup; conf=${1}; shift;;
            -t | --tmux)    shift; tmux=1;;
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
    is_user_root || exit_msg "root user need!!\n"
    [ -z "${conf}" ] && usage "start/clean <config file>"
    file_exists "${conf}" || exit_msg "${conf} not exists\n"
    case "${action}" in
        startup)    info_msg "startup ${conf}\n";;
        cleanup)    info_msg "cleanup ${conf}\n";;
        *)        usage "start/clean";;
    esac
    ${action} "${conf}" "${tmux}"|| exit_msg "${action} ${conf} error $?\n"
    info_msg "Exit\n"
}
main "$@"
