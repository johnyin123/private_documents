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
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true

##################################################
cleanup() {
    echo "EXIT!!!"
}

trap cleanup EXIT
trap cleanup TERM
trap cleanup INT
##################################################
dummy() {
    echo "MY DUMMY"
}
main() {
    case "${1:---start}" in
        --start)
            ;;
        -q)
            quiet=y
            shift
            ;;
        *)
            echo "$0 --start/-q"
            exit 1
            ;;
    esac
    list_func
    dummy
    echo "MAIN!!!"
    return 0
}

main "$@"

