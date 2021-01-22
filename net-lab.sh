#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("net-lab.sh - 65733ca - 2021-01-17T04:30:24+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
startup() {
    local conf="$1" tmux="$2"
    local ns_name= _lval= _rval= lnode= lcidr= rnode= rcidr=
    declare -A MAP_NODES
    declare -A MAP_LINES
    declare -A NODES_ROUTES

    source "${conf}"
    #try sysctl -q -w net.ipv4.ip_forward=1
    for ns_name in $(array_print_label MAP_NODES)
    do
        setup_ns "${ns_name}"
        maybe_netns_run "sysctl -q -w net.ipv4.ip_forward=1" "${ns_name}"
        info_msg "ip netns exec ${ns_name} /bin/bash --rcfile <(echo \"PS1='${ns_name}[$(array_get MAP_NODES ${ns_name})] $ '\")\\n"
    done

    for _lval in $(array_print_label MAP_LINES)
    do
        _rval=$(array_get MAP_LINES ${_lval})
        lnode=${_lval%:*}
        lcidr=${_lval##*:}
        rnode=${_rval%:*}
        rcidr=${_rval##*:}
        maybe_netns_setup_veth "${lnode}-${rnode}" "${rnode}-${lnode}" ""
        maybe_netns_addlink "${lnode}-${rnode}" "${lnode}"
        maybe_netns_run "ip addr add ${lcidr} dev ${lnode}-${rnode}" "${lnode}"
        maybe_netns_addlink "${rnode}-${lnode}" "${rnode}" 
        maybe_netns_run "ip addr add ${rcidr} dev ${rnode}-${lnode}" "${rnode}"
    done

    for ns_name in $(array_print_label NODES_ROUTES)
    do
        while read -rd "," _lval; do
            maybe_netns_run "ip route add $_lval" "${ns_name}"
        done <<< "$(array_get NODES_ROUTES ${ns_name}),"
    done
    ${tumx:+info_msg"tmux not suppport\n"}
}

cleanup() {
    local conf="$1" tmux="$2" ns_name=
    declare -A MAP_NODES
    declare -A MAP_LINES
    declare -A NODES_ROUTES
    source "${conf}"

    for ns_name in $(array_print_label MAP_NODES)
    do
        cleanup_ns "${ns_name}" || true
        debug_msg "destroy ${ns_name}[$(array_get MAP_NODES ${ns_name})]\n"
    done
    ${tumx:+info_msg"tmux not suppport\n"}
    #try sysctl -q -w net.ipv4.ip_forward=0
}

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
cat <<EO_CFG>lab.conf
#       ------------------------------
#       |                            |
#     ------        ------        ------
#     | g1 |--------| g2 |--------| g3 |
#     ------        ------        ------
#     /   \          /   \        /    \ 
#    /     \        /     \      /      \ 
#  ------ ------ ------ ------ ------ ------
#  | h1 | | j1 | | h2 | | j2 | | h3 | | j3 |
#  ------ ------ ------ ------ ------ ------
# MAP_NODES: [host]="desc"
MAP_NODES=(
    [g1]="switch-1"
    [g2]="switch-2"
    [g3]="switch-3"
    [h1]="host-h1"
    [j1]="host-j1"
    [h2]="host-h2"
    [j2]="host-j2"
    [h3]="host-h3"
    [j3]="host-j3"
    )
#MAP_LINES [peer1:ip/prefix]=peer2:ip/prefix
MAP_LINES=(
    [g1:10.1.0.101/30]=g2:10.1.0.102/30
    [g1:10.1.0.105/30]=g3:10.1.0.106/30
    [g2:10.1.0.109/30]=g3:10.1.0.110/30
    [g1:10.0.2.1/24]=h1:10.0.2.100/24
    [g1:10.0.3.1/24]=j1:10.0.3.100/24
    [g2:10.0.4.1/24]=h2:10.0.4.100/24
    [g2:10.0.5.1/24]=j2:10.0.5.100/24
    [g3:10.0.6.1/24]=h3:10.0.6.100/24
    [g3:10.0.7.1/24]=j3:10.0.7.100/24
    )
NODES_ROUTES=(
    [h1]="default via 10.0.2.1,1.1.1.0/24 via 10.0.2.2"
    [j1]="default via 10.0.3.1" 
    [h2]="default via 10.0.4.1"
    [j2]="default via 10.0.5.1"
    [h3]="default via 10.0.6.1"
    [j3]="default via 10.0.7.1"
)
EO_CFG

EOF
    exit 1
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
        startup)  info_msg "startup ${conf}\n";;
        cleanup)  info_msg "cleanup ${conf}\n";;
        *)        usage "start/clean";;
    esac
    ${action} "${conf}" "${tmux}"|| exit_msg "${action} ${conf} error $?\n"
    info_msg "Exit\n"
}
main "$@"
