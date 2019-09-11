#!/usr/bin/env bash
set -o nounset -o pipefail
set -o errexit

# Disable unicode.
LC_ALL=C
LANG=C

readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
#readonly DIRNAME="$(dirname "$(readlink -e "$0")")"
readonly SCRIPTNAME=${0##*/}

if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
##################################################
# print "$(convertsecs $TOTALTIME)"
# To compute the time it takes a script to run use tag the start and end times with
#   STARTTIME=$(date +"%s")
#   ENDTIME=$(date +"%s")
#   TOTALTIME=$(($ENDTIME-$STARTTIME))
# ------------------------------------------------------
convertsecs() {
  ((h=${1}/3600))
  ((m=(${1}%3600)/60))
  ((s=${1}%60))
  printf "%02d:%02d:%02d\n" $h $m $s
}
##################################################
readonly RED="\033[1;31m"
readonly GREEN="\033[1;32m"
readonly YELLOW="\033[1;33m"
readonly BLUE="\033[1;34m"
readonly ENDCLR="\033[0m"
_log_msg()
{
	if [ "${quiet:-n}" = "y" ]; then return; fi
	# shellcheck disable=SC2059
	printf "$@"
}

log_success_msg()
{
	_log_msg "${GREEN}Success:${ENDCLR} %s\\n" "$*"
}

log_failure_msg()
{
	_log_msg "${RED}Failure:${ENDCLR} %s\\n" "$*"
}

log_warning_msg()
{
	_log_msg "${YELLOW}Warning:${ENDCLR} %s\\n" "$*"
}

log_begin_msg()
{
	_log_msg "${BLUE}Begin:${ENDCLR} %-24s " "$*"
}

log_end_msg()
{
	_log_msg "${BLUE}done.${ENDCLR}\\n"
}
##################################################
run_scripts()
{
	initdir=${1}
	[ ! -d "${initdir}" ] && return

	shift
    for i in ${initdir}/*; do
	    . "${initdir}/$i"
    done
}
##################################################
#******************************************************************************
# try: Execute a command with error checking.  Note that when using this, if a piped
# command is used, the '|' must be escaped with '\' when calling try (i.e.
# "try ls \| less").
#******************************************************************************
try ()
{
	# Execute the command and fail if it does not return zero.
    log_begin_msg "${*}"
    if [ "${quiet:-n}" = "y" ] ; then
        eval ${*} >/dev/null 2>&1 || failure && success
    else
        eval ${*} || failure && success
    fi
    log_end_msg
}

success()
{
    return 0
}

failure ()
{
    _log_msg "\033[5;49;39m"
    return 1
}
################################################################################
################################################################################
################################################################################
################################################################################
################################################################################
setup_ns() {
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

cleanup_ns() {
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
    case "${1:---start}" in
        --start)
            ;;
        clean)
            for peer in ${!PEERS[@]}
            do
                cleanup_ns ${peer}
            done             
            try ip link del ${OUTBRIDGE}
            try sysctl -q -w net.ipv4.ip_forward=0
            exit 0
            ;;
        -q)
            quiet=y
            shift
            ;;
        *)
            echo "$0 --start/clean/-q"
            exit 1
            ;;
    esac
    try sysctl -q -w net.ipv4.ip_forward=1
    try ip link add ${OUTBRIDGE} type bridge
    try ip link set ${OUTBRIDGE} up
    for peer in ${!PEERS[@]}
    do
        printf "%-18s%s\n" ${peer}  ${PEERS[$peer]}
        setup_ns ${peer} ${PEERS[$peer]} ${OUTBRIDGE}
        log_warning_msg 'ip netns exec ' ${peer} ' /bin/bash --rcfile <(echo "PS1=\"' ${peer} '$ \"")'
    done
    exit 0
}
[[ ${BASH_SOURCE[0]} = $0 ]] && main "$@"

