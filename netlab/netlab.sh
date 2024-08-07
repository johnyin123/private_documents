#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("netlab.sh - b5bad3a - 2021-10-22T13:24:25+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
post_create() { return 0; } #all netns created!!
pre_cleanup() { return 0; } #all netns exists!!
check() {
    error_msg "NO CHECK FUNC HERE\n"
    return 1;
}

checkup() {
    local conf="$1"
    source "${conf}"
    defined DRYRUN || ( check )
}

startup() {
    local conf="$1"
    local ns_name="" _lval="" _rval="" lnode="" lcidr="" rnode="" rcidr=""
    source "${conf}"
    #try sysctl -q -w net.ipv4.ip_forward=1
    for ns_name in $(array_print_label MAP_NODES)
    do
        setup_ns "${ns_name}" || { error_msg "node ${ns_name} init netns error\n"; return 1; }
        _lval=$(array_get MAP_NODES ${ns_name})
        case "${_lval}" in
            R ) maybe_netns_run "sysctl -q -w net.ipv4.ip_forward=1" "${ns_name}" || return 2 ;;
            S ) maybe_netns_setup_bridge "br0" "${ns_name}" || { error_msg "switch ${ns_name} bridge error\n"; return 3; } ;;
            N ) ;;
            *)  error_msg "node ${ns_name} unknow type ${_lval}\n"; return 4;;
        esac
    done

    for _lval in $(array_print_label MAP_LINES)
    do
        _rval=$(array_get MAP_LINES ${_lval})
        lnode=${_lval%:*}
        lcidr=${_lval##*:}
        rnode=${_rval%:*}
        rcidr=${_rval##*:}
        debug_msg "line: ${_lval}|${_rval}\n"
        maybe_netns_setup_veth "${lnode}-${rnode}" "${rnode}-${lnode}" "" || { error_msg "${lnode}-${rnode} line error\n"; return 5; }
        case "$(array_get MAP_NODES "${lnode}")" in
            R|N ) maybe_netns_addlink "${lnode}-${rnode}" "${lnode}" && {
                    while read -rd "," _lval && [ -n "${_lval}" ]; do
                        debug_msg "${lnode} set dev [${lnode}-${rnode}] addr [$_lval]\n"
                        0</dev/null maybe_netns_run "ip addr add ${_lval} dev ${lnode}-${rnode}" "${lnode}" || { error_msg "node ${lnode} error\n"; return 6; }
                    done <<< "${lcidr},"
                }
                ;;
            S ) maybe_netns_addlink "${lnode}-${rnode}" "${lnode}" \
                && maybe_netns_bridge_addlink "br0" "${lnode}-${rnode}" "${lnode}" \
                || { error_msg "switch ${lnode} error\n"; return 7; }
                ;;
            * ) error_msg "lnode ${lnode} type error\n"; return 10;;
        esac
        case "$(array_get MAP_NODES "${rnode}")" in
            R|N ) maybe_netns_addlink "${rnode}-${lnode}" "${rnode}" && {
                    while read -rd "," _lval && [ -n "${_lval}" ]; do
                        debug_msg "${rnode} set dev [${rnode}-${lnode}] addr [$_lval]\n"
                        0</dev/null maybe_netns_run "ip addr add ${_lval} dev ${rnode}-${lnode}" "${rnode}" || { error_msg "node ${rnode} error\n"; return 8; }
                    done <<< "${rcidr},"
                }
                ;;
            S ) maybe_netns_addlink "${rnode}-${lnode}" "${rnode}" \
                && maybe_netns_bridge_addlink "br0" "${rnode}-${lnode}" "${rnode}" \
                || { error_msg "switch ${rnode} error\n"; return 9; }
                ;;
            * ) error_msg "rnode ${rnode} type error\n"; return 10;;
        esac
   done

    for ns_name in $(array_print_label NODES_ROUTES)
    do
        while read -rd "," _lval && [ -n "${_lval}" ]; do
            debug_msg "${ns_name} add route [$_lval]\n"
            0</dev/null maybe_netns_run "ip route add $_lval" "${ns_name}" || { error_msg "node ${ns_name} add route error\n"; return 11; }
        done <<< "$(array_get NODES_ROUTES ${ns_name}),"
    done
    defined DRYRUN || ( post_create )
}

cleanup() {
    local conf="$1" ns_name=
    declare -A MAP_NODES
    declare -A MAP_LINES
    declare -A NODES_ROUTES
    source "${conf}"
    defined DRYRUN || ( pre_cleanup ) || error_msg "${ns_name} pre_cleanup error\n"
    for ns_name in $(array_print_label MAP_NODES)
    do
        cleanup_ns "${ns_name}" || true
        debug_msg "destroy ${ns_name}[$(array_get MAP_NODES ${ns_name})]\n"
    done
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME} <-s/-c> conf
        -s|--start    start all namespace
        -c|--clean    cleanup all namespace
        -f|--conf  *  config files
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
    ${SCRIPTNAME} -s -f labfile # startup lab
    ${SCRIPTNAME} -f labfile    # check lab
    ${SCRIPTNAME} -c -f labfile # cleanup lab
tmux tip:
        tmux ls
        tmux a -t <session>
        C-b d     - Detach the lab
        C-b w     - Select a window

config file example:
cat <<'EO_CFG'>lab.conf
#[name]="type" type:R/S/N (router,switch,node)
declare -A MAP_NODES=( )
#[node:ip/prefix,ip/prefix]=node:ip/prefix,ip/prefix
declare -A MAP_LINES=( )
#[name]="route1,route2"
declare -A NODES_ROUTES=( )

post_create() { return 0; } #all netns created!!
pre_cleanup() { return 0; } #all netns exists!!
check() { return 0; } # check function
EO_CFG
EOF
    exit 1
}

main() {
    local action="checkup" conf=""
    local opt_short="scf:"
    local opt_long="start,clean,conf:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -s | --start)   shift; action=startup;;
            -c | --clean)   shift; action=cleanup;;
            -f | --conf)    shift; conf=${1}; shift;;
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
    [ -z "${conf}" ] && usage "<start/clean> -f <config file>"
    file_exists "${conf}" || exit_msg "${conf} not exists\n"
    info_msg "${action} ${conf}\n"
    ${action} "${conf}" || exit_msg "${action} ${conf} error exit $?\n"
    info_msg "${action} ${conf} success exit\n"
}
main "$@"
