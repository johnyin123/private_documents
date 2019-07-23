#!/bin/bash
set -o nounset -o pipefail
set -o errexit

readonly DIRNAME="$(dirname "$(readlink -e "$0")")"
readonly SCRIPTNAME=${0##*/}

if [ "${DEBUG:=false}" = "true" ]; then
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi

# Set color variables.
readonly GREEN='\e[0;32m'
readonly RED='\e[0;31m'
readonly BLUE='\e[0;34m'
readonly endColor='\e[0m'
msg()
{
	m_prefix="$1"
    beginColor=""
	case "$2" in
		GREEN) beginColor="$GREEN";;
		BLUE) beginColor="$BLUE";;
		RED) beginColor="$RED";;
        *) beginColor="";;
	esac
	shift 2
	echo -e "${m_prefix}${beginColor}$*${endColor}"; >&2
}
#******************************************************************************
# try: Execute a command with error checking.  Note that when using this, if a piped
# command is used, the '|' must be escaped with '\' when calling try (i.e.
# "try ls \| less").
#******************************************************************************
try ()
{
	# Execute the command and fail if it does not return zero.
    msg "[ * ]" RED "${*}"
	eval ${*} || failure && success
}

success()
{
    msg "" GREEN " OK"
    return 0
}

failure ()
{
    msg "" RED " ERR"
    return 1
}

cleanup() {
    echo "EXIT!!!"
}

trap cleanup EXIT
trap cleanup TERM
trap cleanup INT

function main {
    echo "MAIN!!!"
    return 0
}

main "$@"

