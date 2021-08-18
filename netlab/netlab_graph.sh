#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("netlab_graph.sh - a263b1d - 2021-01-31T16:16:09+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -c|--conf <conf>    *     netlab config file
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}

gen_dot() {
    local conf="$1"
    local node= _lval= _rval= lnode= lcidr= rnode= rcidr=

    source "${conf}"

    echo "graph G {"
    echo 'graph [penwidth=0, labelloc="b", fontname=simsun, fontcolor=dodgerblue3, fontsize=10]'
    for node in $(array_print_label MAP_NODES)
    do
        _lval=$(array_get MAP_NODES ${node})
        case "${_lval}" in
            R ) echo "subgraph ${node} {label=ROUTER ${node}[image=\"router.jpg\"];}" ;;
            S ) echo "subgraph ${node} {label=SWITCH ${node}[image=\"switch.jpg\"];}" ;;
            N ) echo "subgraph ${node} {label=SERVER ${node}[image=\"server.jpg\"];}" ;;
            *)  error_msg "node ${node} unknow type ${_lval}\n"; return 4;;
        esac
    done
    for _lval in $(array_print_label MAP_LINES)
    do
        _rval=$(array_get MAP_LINES ${_lval})
        lnode=${_lval%:*}
        lcidr=${_lval##*:}
        rnode=${_rval%:*}
        rcidr=${_rval##*:}
        echo "${lnode} -- ${rnode}"
    done
    echo "}"
}

main() {
    local conf= node= _lval=
    local opt_short="c:"
    local opt_long="conf:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -c | --conf)  shift; conf=${1}; shift;;
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
    [ -z "${conf}" ] && usage "need <config file>"
    require dot mktemp
    local dot_file="$(mktemp)"
    gen_dot "${conf}" > "${dot_file}" || exit_msg "dot gen failed\n"
    try dot -T ps  -o "${conf}.ps" "${dot_file}"
    try rm -f "${dot_file}"
    return 0
}
main "$@"
