#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("1ef68a4d[2026-06-29T09:36:15+08:00]:wireguard_gencfg.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
usage() {
    R='\e[1;31m' G='\e[1;32m' Y='\e[33;1m' W='\e[0;97m' N='\e[m' usage_doc="$(cat <<EOF
${*:+${Y}$*${N}\n}${R}${SCRIPTNAME}${N}
      env: MTU=1300, default 1300
        -s             *  ${G}<cidr>${N}        server wg ipaddr, exam: 172.16.100.1/24
        --spubip       *  ${G}<ipaddr>${N}      server udp public ipaddress
        --sport        *  ${G}<int>${N}         server udp port
        -c             *  ${G}<cidr>${N}        client wg ipaddr, multi input
        -q|--quiet
        -l|--log ${G}<int>${N} log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
)"; echo -e "${usage_doc}"
    exit 1
}
main() {
    local srv="" spubip="" sport="" cli=()
    local opt_short="s:c:"
    local opt_long="spubip:,sport:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -s)             shift; srv=${1}; shift;;
            --spubip)       shift; spubip=${1}; shift;;
            --sport)        shift; sport=${1}; shift;;
            -c)             shift; cli+=(${1}); shift;;
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
    [ -z "${srv}" ] && usage "server wg ipaddr is required"
    [ -z "${spubip}" ] && usage "spubip is required"
    [ -z "${sport}" ] && usage "sport is required"
    local srv_prikey=$(try wg genkey)
    local srv_pubkey=$(try echo -n ${srv_prikey} \| wg pubkey)
    cat <<EOF > srv.conf
[Interface]
PrivateKey = ${srv_prikey}
Address = ${srv}
ListenPort = ${sport}
MTU = ${MTU:-1300}
Table = off
# PreUp =
# PostDown =

EOF
    for cli_cidr in ${cli[@]}; do
        local cli_ipaddr=${cli_cidr%/*}
        local cli_prikey=$(try wg genkey)
        local cli_pubkey=$(try echo -n ${cli_prikey} \| wg pubkey)
        cat <<EOF >>srv.conf
[Peer]
PublicKey = ${cli_pubkey}
AllowedIPs = ${cli_cidr}
PersistentKeepalive = 25

EOF
        cat <<EOF > cli_${cli_ipaddr}.conf
[Interface]
PrivateKey = ${cli_prikey}
Address = ${cli_cidr}
MTU = ${MTU:-1300}
Table = off
# PreUp =
# PostDown =

[Peer]
PublicKey = ${srv_pubkey}
AllowedIPs = 0.0.0.0/0
Endpoint = ${spubip}:${sport}
PersistentKeepalive = 25
EOF
    done
    return 0
}
main "$@"
