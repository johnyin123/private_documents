#!/usr/bin/env bash
set -o nounset -o pipefail
#set -o errexit

# Disable unicode.
LC_ALL=C
LANG=C

readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
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
	_log_msg "${BLUE}Begin:${ENDCLR} %s ... " "$*"
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
	eval ${*} || failure && success
    log_end_msg
}

success()
{
    log_success_msg "OK"
    return 0
}

failure ()
{
    log_failure_msg "ERR"
    return 1
}
##################################################
cleanup() {
    err=$?
    echo "Cleaning " $err " stuff up..."
    trap '' EXIT INT TERM
    exit $err
}

trap cleanup EXIT
trap cleanup TERM
#CTRL+C, SIGINT
trap cleanup INT
##################################################
add_vxlan() {
    local dev=$1
    local id=$2
    local dstport=$3
    local mac=$4
    local ip_mask=$5
    log_warning_msg "nolearning -> need add fdb manual"
    log_warning_msg "proxy      -> need add arp manual"
    try ip link add ${dev} type vxlan id ${id} dstport ${dstport} nolearning proxy 
    try ifconfig ${dev} hw ether ${mac}
    try ip addr add ${ip_mask} dev ${dev}
    try ip link set ${dev} up
}
add_fdb() {
    local dev=$1
    local mac=$2
    local dst=$3
    log_warning_msg "Create ${dev} forwarding table entry: ${mac} -> ${dst}"
    try bridge fdb append ${mac} dev ${dev} dst ${dst}
}
add_arp() {
    local dev=$1
    local mac=$2
    local ip=$3
    log_warning_msg "Add ${dev} arp table entry: ${ip} -> ${mac}"
    try ip neigh add ${ip} lladdr ${mac} dev ${dev}
}
show_vxlan() {
    local dev=$1
    try bridge fdb show dev ${dev}
    try ip -d link show ${dev}
}
main() {
    local dev="vxlan100"
    local id=100
    local port=50000 

    local node="${HOSTNAME:-$(hostname)}"
    case "${node}" in
        *"gvpe-bj"*)
            add_vxlan ${dev} ${id} ${port} "9e:08:90:00:00:01" "172.16.16.2/24"
            add_fdb ${dev} "9e:08:90:00:00:02" "59.46.22.56"
            add_arp ${dev} "9e:08:90:00:00:02" "172.16.16.3"
            ;;

        "usb950d" | "yinzh")
            add_vxlan ${dev} ${id} ${port} "9e:08:90:00:00:02" "172.16.16.3/24"
            add_fdb ${dev} "9e:08:90:00:00:01" "119.254.158.141"
            add_arp ${dev} "9e:08:90:00:00:01" "172.16.16.2"
            ;;
        *)
            log_failure_msg "Unknown node detected, aborting..."
            exit 1
            ;;
    esac
    show_vxlan ${dev}
    return 0
}

main "$@"

