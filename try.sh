#!/bin/bash
set -o nounset -o pipefail
set -o errexit

readonly DIRNAME="$(dirname "$(readlink -e "$0")")"
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
    echo "EXIT!!!"
}

trap cleanup EXIT
trap cleanup TERM
trap cleanup INT
##################################################

function main {
    echo "MAIN!!!"
    return 0
}

main "$@"

