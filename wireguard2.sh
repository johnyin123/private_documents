#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("wireguard2.sh - 7c9f7d7 - 2021-01-21T14:35:06+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################

gen_wg_server() {
    local srv_addr=$1
    local srv_pubport=$2
    local srv_prikey=$3
    echo "[Interface]"
    echo "Address = ${srv_addr}"
    echo "ListenPort = ${srv_pubport}"
    echo "PrivateKey = ${srv_prikey}"
    echo "#Table = off #disable iptable&nft&ip rule"
}

server_add_peer() {
    local cli_pubkey=$1
    local cli_addr=$2
    echo "[Peer]"
    echo "PublicKey = ${cli_pubkey}"
    echo "AllowedIPs = ${cli_addr%/*}/32"
    echo "PersistentKeepalive = 10"
}

gen_wg_client() {
    local srv_pubkey=$1
    local srv_pubaddr=$2
    local srv_pubport=$3
    local cli_prikey=$4
    local cli_addr=$5
    local cli_allow=$6
    echo "[Interface]"
    echo "Address = ${cli_addr}"
    echo "PrivateKey = ${cli_prikey}"
    echo "[Peer]"
    echo "PublicKey = ${srv_pubkey}"
    echo "AllowedIPs = ${cli_allow}"
    echo "Endpoint = ${srv_pubaddr}:${srv_pubport}"
    echo "PersistentKeepalive = 10"
    #cli-${cli_addr%/*}.conf
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME} [server/client]
                      s/c
        -p|--pkey       *  <key>      server prikey
        -a|--addr     * *  <address>  exam: 192.168.1.1/24
        -P|--pubport  * *  <int>      server public port
        -A|--pubaddr    *  <ipaddr>   server public ipaddress
        -c|--callow        <allow>    client allow network forward
                                    exam: 1.1.1.0/23,2.2.2.0/23

        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
  ${SCRIPTNAME} s -a 10.1.1.1/16 -P9988 -p\$(wg genkey) > srv.conf
  ${SCRIPTNAME} c -a 10.1.1.2/16 -P9988 -A1.2.3.4 -p<server prikey> >> srv.conf
EOF
    exit 1
} >&2

main() {
    local prikey=
    local srv_pubport=
    local srv_pubaddr=
    local addr=
    local cli_allow=

    local action="${1:-}"
    [[ ${action-} =~ ^c|client|s|server$ ]] || usage "select mode <server/client>"
    shift 1
    local opt_short="p:a:P:A:c:"
    local opt_long="pkey:,addr:,pubport:,pubaddr:,callow:,"
    opt_short+="ql:dVh"
    opt_long+="quite,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -p | --pkey)    shift; prikey=${1}; shift;;
            -a | --addr)    shift; addr=${1}; shift;;
            -P | --pubport) shift; srv_pubport=${1}; shift;;
            -A | --pubaddr) shift; srv_pubaddr=${1}; shift;;
            -c | --callow)  shift; cli_allow=${1}; shift;;

            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; set_loglevel ${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              error_msg "Unexpected option: $1.\n"; usage;;
        esac
    done
    require wg
    [ -z ${addr} ] && usage "<addr> must input"
    is_ipv4_subnet ${addr} || usage "addr not ipv4/mask"
    [ -z ${srv_pubport} ] && usage "port must input"
    is_integer ${srv_pubport} || usage "port wrong"
    [ -z ${prikey} ] && prikey=$(try wg genkey)
    local pubkey="$(echo -n ${prikey} | try wg pubkey)"
    echo "action      :${action}
PRI         :${prikey}
PUB         :${pubkey}
srv_pubport :${srv_pubport}
srv_pubaddr :${srv_pubaddr}
addr        :${addr}
cli_allow   :${cli_allow}" | vinfo_msg
    case "${action}" in
        c | client)
            local cli_prikey=$(try wg genkey)
            local cli_pubkey="$(echo -n ${cli_prikey} | try wg pubkey)"
            [ -z ${srv_pubaddr} ] && usage "srv_pubaddr must input"
            IFS='/' read -r tip tmask <<< "${addr}"
            cli_allow=$(get_ipv4_network ${tip} $(cidr2mask ${tmask}))/${tmask}${cli_allow:+,${cli_allow}}
            info_msg "gen client conf: ==============================================\n"
            gen_wg_client "${pubkey}" "${srv_pubaddr}" "${srv_pubport}" "${cli_prikey}" "${addr}" "${cli_allow}" | vinfo_msg
            info_msg "server conf add peer: =========================================\n"
            server_add_peer "${cli_pubkey}" "${addr}" | vinfo_msg
            ;;
        s | server)
            gen_wg_server "${addr}" "${srv_pubport}" "${prikey}" | vinfo_msg
            ;;
    esac
    return 0
}
main "$@"
