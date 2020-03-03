#!/usr/bin/env bash
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

#trap cleanup EXIT
trap cleanup TERM
trap cleanup INT
##################################################
dummy() {
    echo "MY DUMMY"
    source 'trap.sh'
    echo "doing something wrong now .."
    echo "$foo"
}

usage() {
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

#    echo='echo'
#    echo='printf %s\n'
#    echo_func () {
#        cat <<EOT
#$*
#EOT
#    }
#    echo='echo_func'

exec 2> >(tee "error_log_$(date -Iseconds).txt")
board=$1; shift || (echo "ERROR: Board must be specified"; exit 1;)
uboot=$1; shift || (echo "ERROR: u-boot.bin must be specified"; exit 1;)

test_lowercase()
{
	# Grab input.
	declare input=${1:-$(</dev/stdin)};

	# Use that input to do anything.
	echo "$input" | tr '[:upper:]' '[:lower:]'
}

echo "$(test_lowercase 'HELLO xx')"
echo "HELLO there, FRIEND!" | test_lowercase
# cat >>'EOF'
# {
#     "partitions": {
#         "boot_size": "67108864"
#     },
#     "debian": {
#         "release": "wheezy",
#         "packages": [ "openssh-server1", "openssh-server2", "openssh-server3" ]
#     }
# }
# EOF

# while read package ; do
#     echo ${package}
# done < <(json_config "debian.packages[]")

main() {
    while test -n "${1:-}"
    do
        case "${1:--h}" in
            -q | --quiet)
                QUIET=1
                ;;
            -l | --log)
                set_loglevel ${1}; shift
                ;;
            -V | --version)
                exit_msg "${SCRIPTNAME} version\n"
                ;;
            -d | --dryrun)
                DRYRUN=1
                ;;
            -h | --help | *)
                usage
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

