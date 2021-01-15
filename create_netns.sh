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
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME} start/clean
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}

init_ns_env() {
    ns_name="$1"
    ip="$2"
    out_br=$3

    #ip netns del ${ns_name} 2> /dev/null
    try ip netns add ${ns_name}
    try ip netns exec ${ns_name} ip addr add 127.0.0.1/8 dev lo
    try ip netns exec ${ns_name} ip link set lo up

    try ip link add ${ns_name}0 type veth peer name ${ns_name}1
    try ip link set ${ns_name}0 master ${out_br}
    try ip link set ${ns_name}0 up

    try ip link set ${ns_name}1 netns ${ns_name}
    try ip netns exec ${ns_name} ip link set ${ns_name}1 name eth0 up
    try ip netns exec ${ns_name} ip addr add ${ip} dev eth0
}

deinit_ns_env() {
    ns_name="$1"
    try ip netns del ${ns_name}
    try ip link delete ${ns_name}0
}

declare -A PEERS
PEERS=( \
    ["M1"]=192.168.168.101/24 \
    ["M2"]=192.168.168.102/24 \
    ["M3"]=192.168.168.103/24 \
    )
OUTBRIDGE=br-test

main() {
    is_user_root || exit_msg "root user need!!\n"
    local opt_short=""
    local opt_long=""
    opt_short+="ql:dVh"
    opt_long+="quite,log:,dryrun,version,help"
    readonly local __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
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
    case "${1:-}" in
        start)
            ;;
        clean)
            for peer in ${!PEERS[@]}
            do
                deinit_ns_env ${peer}
            done             
            try ip link del ${OUTBRIDGE}
            try sysctl -q -w net.ipv4.ip_forward=0
            return 0
            ;;
        *)
            usage "action <start/clean> must input"
            ;;
    esac
    try sysctl -q -w net.ipv4.ip_forward=1
    try ip link add ${OUTBRIDGE} type bridge
    try ip link set ${OUTBRIDGE} up
    for peer in ${!PEERS[@]}
    do
        printf "%-18s%s\n" ${peer}  ${PEERS[$peer]}
        init_ns_env ${peer} ${PEERS[$peer]} ${OUTBRIDGE}
        info_msg "ip netns exec ${peer} /bin/bash"
    done
    return 0
}
main "$@"
