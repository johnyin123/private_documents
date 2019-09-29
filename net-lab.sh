#!/usr/bin/env bash
set -o nounset -o pipefail
#set -o errexit

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
################################################################################
################################################################################
################################################################################
check_cfg() {
    local cfg_file=$1
    [[ -r "${cfg_file}" ]] || {
        cat >"${cfg_file}" <<-'CFGEOF'
#       ------------------------------
#       |                            |
#     ------        ------        ------
#     | g1 |--------| g2 |--------| g3 |
#     ------        ------        ------
#     /   \          /   \        /    \ 
#    /     \        /     \      /      \ 
#  ------ ------ ------ ------ ------ ------
#  | h1 | | j1 | | h2 | | j2 | | h3 | | j3 |
#  ------ ------ ------ ------ ------ ------
# MAP_NODES: [host]="desc"
declare -A MAP_NODES=(
    [g1]="switch-1"
    [g2]="switch-2"
    [g3]="switch-3"
    [h1]="host-h1"
    [j1]="host-j1"
    [h2]="host-h2"
    [j2]="host-j2"
    [h3]="host-h3"
    [j3]="host-j3"
    )

#MAP_LINES [peer1:ip/prefix]=peer2:ip/prefix
declare -A MAP_LINES=(
    [g1:10.1.0.101/30]=g2:10.1.0.102/30
    [g1:10.1.0.105/30]=g3:10.1.0.106/30
    [g2:10.1.0.109/30]=g3:10.1.0.110/30
    [g1:10.0.2.1/24]=h1:10.0.2.100/24
    [g1:10.0.3.1/24]=j1:10.0.3.100/24
    [g2:10.0.4.1/24]=h2:10.0.4.100/24
    [g2:10.0.5.1/24]=j2:10.0.5.100/24
    [g3:10.0.6.1/24]=h3:10.0.6.100/24
    [g3:10.0.7.1/24]=j3:10.0.7.100/24
    )

declare -A NODES_ROUTES=(
    [h1]="default via 10.0.2.1 
          1.1.1.0/24 via 10.0.2.2 
          "
    [j1]="
        default via 10.0.3.1
          " 
    [h2]="default via 10.0.4.1"
    [j2]="default via 10.0.5.1"
    [h3]="default via 10.0.6.1"
    [j3]="default via 10.0.7.1"
)

CFGEOF
    exit_msg "Created ${cfg_file} using defaults.  Please review it/configure before running again.\n"
    }
}

del_ns() {
    local ns_name="$1"
    try ip netns del ${ns_name}
    try rm -rf "/etc/netns/${ns_name}"
}

add_ns() {
    local ns_name="$1"
    try mkdir -p /etc/quagga/ /etc/netns/${ns_name}/quagga/
    try ip netns add ${ns_name}
    try ip netns exec ${ns_name} ip addr add 127.0.0.1/8 dev lo
    try ip netns exec ${ns_name} ip link set lo up
    try ip netns exec ${ns_name} sysctl -q -w net.ipv4.ip_forward=1
}

add_route() {
    local MATCH='^[[:space:]]*(\#.*)?$'
    local ns="$1"
    local routes="$2"
    { printf "$routes" ; echo ; } | while read line
    do
        if [[ ! "$line" =~ $MATCH ]]; then
            try ip netns exec ${ns} ip route add $line
        fi
    done
}

connect_ns() {
    local ns1="$1"
    local ip1=$2
    local ns2="$3"
    local ip2=$4 

    try ip link add ${ns1}-${ns2} type veth peer name ${ns2}-${ns1}
    try ip link set ${ns1}-${ns2} netns ${ns1}
    try ip netns exec ${ns1} ip link set ${ns1}-${ns2} up
    try ip netns exec ${ns1} ip addr add ${ip1} dev ${ns1}-${ns2}

    try ip link set ${ns2}-${ns1} netns ${ns2}
    try ip netns exec ${ns2} ip link set ${ns2}-${ns1} up
    try ip netns exec ${ns2} ip addr add ${ip2} dev ${ns2}-${ns1}
}

start() {
    try sysctl -q -w net.ipv4.ip_forward=1
    for node in $(array_print_label MAP_NODES)
    do
        add_ns ${node}
        info_msg "ip netns exec ${node} /bin/bash --rcfile <(echo \"PS1='${node}[$(array_get MAP_NODES ${node})] $ '\")\\n"
    done

    for _lval in $(array_print_label MAP_LINES)
    do
        _rval=$(array_get MAP_LINES ${_lval})
        lnode=${_lval%:*}
        lcird=${_lval##*:}
        rnode=${_rval%:*}
        rcird=${_rval##*:}
        connect_ns ${lnode} ${lcird} ${rnode} ${rcird}
    done

    for node in $(array_print_label NODES_ROUTES)
    do
        add_route ${node} "$(array_get NODES_ROUTES ${node})"
    done
}
clean() {
    for node in $(array_print_label MAP_NODES)
    do
        del_ns ${node}
        debug_msg "destroy ${node}[$(array_get MAP_NODES ${node})]\n"
    done
    try sysctl -q -w net.ipv4.ip_forward=0
}

usage() {
    cat <<EOF
${SCRIPTNAME} --start/--clean filename
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}

main() {
    while test $# -gt 0
    #while test -n "${1:-}"
    do
        opt="$1"
        shift
        case "${opt}" in
            -s | --start)
                check_cfg ${1:?You need to enter a file name!}
                source "${1}"; shift
                start
                ;;

            -c | --clean)
                source "${1}"; shift
                clean
                ;;
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
    done
    #ip -all netns exec ip r
    exit 0
}
[[ ${BASH_SOURCE[0]} = $0 ]] && main "$@"
# touch /tmp/utsns1
# unshare --uts=/tmp/uts-ns1 hostname testhostname
# nsenter --uts=/tmp/uts-ns1 hostname
# umount /tmp/utsns1

