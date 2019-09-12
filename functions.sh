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

