#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("game.sh - 2962856 - 2021-03-12T17:33:59+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
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
    require dialog systemd-nspawn 
    games=(
        "/aoe2/age2_x1.exe"   "age2_x1"
        "/aoe2/empires2.exe"  "empires2"
        "/ra2/ra2.exe"        "ra2"
        "/ra2mod/ra2.exe"     "ra2mod"
    )
    id=$(dialog "title xxa" "menu xxx" games[@])
    [ -z ${id} ] && exit 0
    local HOST_XAUTH=/home/johnyin/.Xauthority
    local HOST_PULSE=/run/user/1000/pulse
    local HOST_PULSE_COOKIE=/home/johnyin/.config/pulse/cookie
#    --setenv=DISPLAY=${DISPLAY}
    systemd-nspawn -D "${DIRNAME}/game" \
        --bind-ro=/tmp/.X11-unix \
        --bind-ro=${HOST_XAUTH}:/home/johnyin/.Xauthority \
        --network-veth \
        --network-bridge=br-ext \
        --bind-ro=${HOST_PULSE_COOKIE}:/home/johnyin/.config/pulse/cookie \
        --bind-ro=${HOST_PULSE}:/run/user/host/pulse \
        -u johnyin env DISPLAY=:0 PULSE_SERVER=unix:/run/user/host/pulse/native wine /home/johnyin/${id}
#    --boot
    return 0
}
main "$@"
