#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("cd89fd71[2024-12-19T13:44:36+08:00]:mini.sh")
################################################################################
FILTER_CMD="cat"
LOGFILE=
################################################################################
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}
main() {
    local opt_short=""
    local opt_long=""
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            ########################################
            -q | --quiet)   shift; FILTER_CMD=;;
            -l | --log)     shift; LOGFILE=${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    exec > >(${FILTER_CMD:-sed '/^\s*#/d'} | tee ${LOGFILE:+-i ${LOGFILE}})
    return 0
}
main "$@"
