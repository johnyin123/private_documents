#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> ${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log
    BASH_XTRACEFD="5"
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

cat <<EOF | sudo tee /dev/null
	'append STDOUT and STDERR'            : ' &>> <CURSOR>',
	'close input from file descr n'       : ' <CURSOR><&- ',
	'close output from file descr n'      : ' <CURSOR>>&- ',
	'close STDIN'                         : ' <&- <CURSOR>',
	'close STDOUT'                        : ' >&- <CURSOR>',
	'direct file descr n to file, append' : ' <CURSOR>>> ',
	'direct file descr n to file'         : ' <CURSOR>> ',
	'direct STDERR to STDOUT'             : ' 2>&1<CURSOR>',
	'direct STDOUT and STDERR to file'    : ' &> <CURSOR>',
	'direct STDOUT to file, append'       : ' >> <CURSOR>',
	'direct STDOUT to file'               : ' > <CURSOR>',
	'direct STDOUT to STDERR'             : ' >&2<CURSOR>',
	'duplicate STDIN from file descr n'   : ' <CURSOR><& ',
	'duplicate STDOUT to file descr n'    : ' <CURSOR>>& ',
	'take file descr n from file'         : ' <CURSOR>< ',
	'take STDIN from file'                : ' < <CURSOR>',
EOF
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
    local opt_short+="u:n:"
    local opt_long+="uuid:,name:"
    opt_short+="ql:dVh"
    opt_long+="quite,log:,dryrun,version,help"
    readonly local __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -u | --uuid)    shift; uuid=${1}; shift;;
            -n | --name)    shift; name=${1}; shift;;
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; set_loglevel ${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; exit_msg "${SCRIPTNAME} version\n";;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              error_msg "Unexpected option: $1.\n"; usage;;
        esac
    done

# ./xtrace.sh ./try.sh 
__trace_ON__
    list_func
__trace_OFF__
    dummy
    exit_msg "$0 --start/--clean filename\n"
    echo "MAIN!!!"
    # echo > aa.txt
    # ${EDITOR:-${VISUAL:-vi}}  aa.txt
    netstat -tulpn | grep nginx
    echo "${PIPESTATUS[@]}"
    true | true
    echo "The exit status of first command ${PIPESTATUS[0]}, and the second command ${PIPESTATUS[1]}"
    true | false
    echo "The exit status of first command ${PIPESTATUS[0]}, and the second command ${PIPESTATUS[1]}"
    false | false | true
    echo "The exit status of first command ${PIPESTATUS[0]}, second command ${PIPESTATUS[1]}, and third command ${PIPESTATUS[2]}"
    return 0
}
main "$@"
