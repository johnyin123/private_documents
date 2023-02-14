#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("58cb44d[2021-08-18T17:14:28+08:00]:game.sh")
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
dialog() {
    local title="${1}"
    local menu="${2}"
    declare -a items=("${!3}")
    local item=$(whiptail --notags \
        --title "${title}" \
        --menu "${menu}" \
        0  0 12 \
        "${items[@]}" 3>&1 1>&2 2>&3 || true)
    echo -n "${item}"
}
main() {
    local opt_short=""
    local opt_long=""
    opt_short+="ql:dVh"
    opt_long+="quite,log:,dryrun,version,help"
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
    games=(
        "/home/johnyin/aoe2/age2_x1.exe"   "age2_x1"
        "/home/johnyin/aoe2/empires2.exe"  "empires2"
        "/home/johnyin/ra2/ra2.exe"        "ra2"
        "/home/johnyin/ra2mod/ra2.exe"     "ra2mod"
    )
    id=$(dialog "title xxa" "menu xxx" games[@])
    [ -z ${id} ] && exit 0
#    --setenv=DISPLAY=${DISPLAY}
    systemd-nspawn -D "${DIRNAME}/game" \
        --bind-ro=/tmp/.X11-unix \
        --bind-ro=/home/johnyin/.Xauthority:/home/johnyin/.Xauthority \
        --network-veth \
        --network-bridge=br-ext \
        --bind-ro=/home/johnyin/.config/pulse/cookie \
        --bind-ro=/run/user/1000/pulse:/run/user/host/pulse \
        -u johnyin env LC_ALL=zh_CN.UTF-8 DISPLAY=:0 PULSE_SERVER=unix:/run/user/host/pulse/native bash -c "cd $(dirname ${id}) && wine ${id}"
#    --boot
    return 0
}
main "$@"
