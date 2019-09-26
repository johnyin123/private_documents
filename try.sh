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
    while test -n "${1:-}"
    do
        case "$1" in
            -V | --version)
                echo ${SCRIPTNAME}
                exit 0
                ;;

            -h | --help)
                echo "help page"
                exit 0
                ;;

            -d | --dryrun)
                DRYRUN=1
                ;;

            -n | --node)
                shift
                NODE_NAME="$1"
                ;;

            *)
                exit_msg "$0 --start/--clean filename\n"
                break
                ;;
        esac
        shift
    done

    list_func
    dummy
    exit_msg "$0 --start/--clean filename\n"
    echo "MAIN!!!"
    return 0
}

main "$@"

