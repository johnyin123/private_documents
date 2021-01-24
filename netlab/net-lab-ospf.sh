#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("net-lab-ospf.sh - initversion - 2021-01-25T07:29:48+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################

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

gen_zebra() {
    local ns=$1
    local lo_ip=$2
    local password="password"
    cat <<EOF > /etc/netns/${ns}/quagga/zebra.conf
hostname ${ns}
password ${password}
enable password ${password}
log file /tmp/${ns}_zebra.log
service password-encryption

interface lo
  ip address 127.0.0.1/8
  ip address ${lo_ip}
EOF
    try chown quagga:quagga /etc/netns/${ns}/quagga/zebra.conf
}

gen_ospfd() {
    local ns=$1;shift
    local route_id=$1;shift
    local interface=$1;shift
    local password="password"

    cat <<EOF > /etc/netns/${ns}/quagga/ospfd.conf
hostname ${ns}
password ${password}
enable password ${password}
log file /tmp/${ns}-ospf.log
log stdout
log syslog
interface lo
 ip ospf hello-interval 10
 ip ospf dead-interval 40
 ip ospf priority 0
 ip ospf authentication message-digest
 ip ospf message-digest-key 1 md5 10P@SSW)rd00

router ospf
 ospf router-id ${route_id}
 redistribute connected
 log-adjacency-changes
! auto-cost reference-bandwidth 100000
 network ${route_id}/32 area 0.0.0.0
$(while test $# -gt 0
do
echo " network ${1} area 0.0.0.1"
shift
done
)
 area 0.0.0.0 authentication message-digest
EOF
    try chown quagga:quagga /etc/netns/${ns}/quagga/ospfd.conf
}
main() {
    while test $# -gt 0
    do
        opt="$1"
        shift
        case "${opt}" in
            -q | --quiet) QUIET=1 ;;
            -l | --log) set_loglevel ${1}; shift ;;
            -V | --version) for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0 ;;
            -d | --dryrun) DRYRUN=1 ;;
            -h | --help | *) usage ;;
        esac
    done
    gen_zebra "g1" "1.1.1.1/32"
    gen_ospfd "g1" "1.1.1.1" "g1-g2" "10.1.0.101/30" "10.1.0.105/30" "10.0.2.0/24" "10.0.3.0/24"
    gen_zebra "g2" "1.1.1.2/32"
    gen_ospfd "g2" "1.1.1.2" "g2-g3" "10.1.0.102/30" "10.1.0.109/30" "10.0.4.0/24" "10.0.5.0/24"
    gen_zebra "g3" "1.1.1.3/32"
    gen_ospfd "g3" "1.1.1.3" "g3-g1" "10.1.0.106/30" "10.1.0.110/30" "10.0.6.0/24" "10.0.7.0/24"
    try mkdir -p /run/quagga && chown quagga:quagga /run/quagga
    echo "zebra -d -i /tmp/g1.pid"
    echo "ospfd -d -i /tmp/ospfg1.pid"

    exit 0
}
[[ ${BASH_SOURCE[0]} = $0 ]] && main "$@"
