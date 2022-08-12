#!/usr/bin/env bash
set -o nounset   ## set -u : exit the script if you try to use an uninitialised variable
set -o errexit   ## set -e : exit the script if any statement returns a non-true return value
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("initver[2022-08-12T14:20:27+08:00]:init_loadblance.sh")
################################################################################
LOGFILE=""
TIMESPAN=$(date '+%Y%m%d%H%M%S')

log() {
    echo "######$*" | tee ${LOGFILE} >&2
}

backup() {
    src=${1}
    cat ${src} 2>/dev/null > ${src}.orig.${TIMESPAN} || true
}

init_keepalived() {
    local id=${1}
    local vip=${2}
    shift 2
    local real_ips="${*}"
    local ip=""
    log "Init keepalived for virtual server(TCP/UDP)"
    log "id=${id}, vip=${vip}, rip=${real_ips}"
    log "INIT /etc/modprobe.d/ipvs.conf"
    echo "options ip_vs conn_tab_bits=15" | tee ${LOGFILE} | tee /etc/modprobe.d/ipvs.conf
    log "INIT /etc/keepalived/keepalived.conf"
    backup /etc/keepalived/keepalived.conf
cat <<EOF | tee ${LOGFILE} | tee /etc/keepalived/keepalived.conf
global_defs {
   router_id ${id}
}
virtual_server ${vip} {
    delay_loop 2
    lb_algo rr
    lb_kind DR
    persistence_timeout 360
    protocol TCP
$(for ip in ${real_ips}; do
echo "    real_server ${ip} {"
echo "        weight 1"
echo "        PING_CHECK {"
echo "            retry 2"
echo "        }"
echo "    }"
done)
}
virtual_server ${vip} {
    delay_loop 2
    lb_algo rr
    lb_kind DR
    persistence_timeout 360
    protocol UDP
$(for ip in ${real_ips}; do
echo "    real_server ${ip} {"
echo "        weight 1"
echo "        PING_CHECK {"
echo "            retry 2"
echo "        }"
echo "    }"
done)
}
EOF
    systemctl restart keepalived || true
}

gen_zebra() {
    local interface=${1}
    local vip=${2}
    local password="password"
    log "INIT /etc/frr/frr.conf"
    backup /etc/frr/frr.conf
    cat <<EOF | tee ${LOGFILE} | tee /etc/frr/frr.conf
hostname $(cat /etc/hostname)
password ${password}
enable password ${password}
log file /var/log/frr/zebra.log
service password-encryption
interface ${interface}
 ip address ${vip}/32
EOF
    systemctl restart frr || true
}

init_lo_vip() {
    local vip=${1}
    log "INIT /etc/network/interfaces.d/lvs"
    cat<<EOF | tee ${LOGFILE} | tee /etc/network/interfaces.d/lvs
auto lo:0
iface lo:0 inet static
    address ${vip}/32
EOF
}

init_real_srv() {
    log "INIT /etc/sysctl.d/99-lvs.conf"
    cat<<EOF | tee ${LOGFILE} | tee /etc/sysctl.d/99-lvs.conf
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.eth0.arp_ignore = 1
net.ipv4.conf.eth1.arp_ignore = 1
net.ipv4.conf.all.arp_announce = 2
net.ipv4.conf.eth0.arp_announce = 2
net.ipv4.conf.eth1.arp_announce = 2
EOF
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
              REAL  Director
        --rid       *  <str> keepalive router_id
        --vip    *  *  <ip> virtual ipaddress
        --rip       *  <ip> real ipaddress, support multi args
        --frr               Director use frr
        -q|--quiet
        -l|--log <str>  log file
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
wget -q -O- 'https://deb.frrouting.org/frr/keys.asc' | gpg --dearmor > /etc/apt/trusted.gpg.d/frr-archive-keyring.gpg
# possible values for FRRVER: frr-6 frr-7 frr-8 frr-stable
FRRVER="frr-stable"
echo "deb https://deb.frrouting.org/frr bullseye \$FRRVER" > /etc/apt/sources.list.d/frr.list
apt update && apt -y install frr keepalived
EOF
    exit 1
}
main() {
    local rid="" vip="" frr=""
    local rip=()
    local opt_short=""
    local opt_long="rid:,vip:,rip:,frr,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            --rid)          shift; rid=${1}; shift;;
            --vip)          shift; vip=${1}; shift;;
            --rip)          shift; rip+=(${1}); shift;;
            --frr)          shift; frr=1;;
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; LOGFILE="-a ${1}"; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    [ -z "${rid}" ] || [ -z "${vip}" ] || ((${#rip[@]} == 0)) || {
        log "INIT LB DIRECTOR SERVER"
        init_keepalived "${rid}" "${vip}" ${rip[@]}
        [ -z "${frr}" ] && init_lo_vip "${vip}" || gen_zebra "lo" "${vip}"
    }
    [ -z "${rid}" ] && ((${#rip[@]} == 0)) && {
        [ -z "${vip}" ] || {
            log "INIT LB REAL SERVER"
            init_real_srv
            init_lo_vip "${vip}"
        }
    }
    log "ALL DONE"
    return 0
}
main "$@"
