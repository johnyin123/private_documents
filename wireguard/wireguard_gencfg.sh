#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("9910793[2024-08-13T12:43:18+08:00]:wireguard_gencfg.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################

gen_wg_interface() {
    local prikey="${1}"
    local notable="${2}"
    local pubport="${3:-}"
    local addr="${4:-}"
    echo "[Interface]"
    echo "PrivateKey = ${prikey}"
    ${addr:+echo "Address = ${addr}"}
    ${pubport:+echo "ListenPort = ${pubport}"}
    [ -z "${notable}" ] || {
        echo "Table = off"
        echo "#disable wg-quick firewall rule"
    }
}

gen_wg_peer() {
    local peer_pubkey="${1}"
    local allow_addr="${2}"
    local endpoint="${3:-}"
    echo "[Peer]"
    echo "PublicKey = ${peer_pubkey}"
    echo "AllowedIPs = ${allow_addr}"
    ${endpoint:+echo "Endpoint = ${endpoint}"}
    echo "PersistentKeepalive = 10"
}

usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -k|--pkey          <key>          prikey, default auto generate.
        -t|--notable                      no firewall and routes
        -p|--pubport       <int>          public port
        -a|--addr          <address>      exam: 192.168.1.1/24
        --onlypeer                        only gen peer config
        -P|--pubkey        <key>          peer public key
        --endpoint         <ipaddr:port>  peer public ipaddress:port
        --allows           <allow>        peer allows network, 
                                          1:<allow> 2:<address> network 3:0.0.0.0/0
                                          exam: 1.1.1.0/23,2.2.2.0/23

        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
  ${SCRIPTNAME} -a 10.1.1.1/16 -p 9988 -k \$(wg genkey) --notable > srv1.conf
  ${SCRIPTNAME} -a 10.1.1.2/16 -p 9988 -k \$(wg genkey) --notable > srv2.conf
  ${SCRIPTNAME} -a 10.1.1.2/16 -p 9988 --allows 1.2.3.0/24 -P <server public key> >srv3.conf
  # wg genkey | tee /dev/stderr | wg pubkey
EOF
    exit 1
} >&2

main() {
    local prikey= notable= pubport= addr= onlypeer= peer_pubkey= endpoint= allows=
    local opt_short="k:tp:a:P:"
    local opt_long="pkey:,notable,pubport:,addr:,onlypeer,pubkey:,endpoint:,allows:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -k | --pkey)    shift; prikey=${1}; shift;;
            -t | --notable) shift; notable=1;;
            -p | --pubport) shift; pubport=${1}; shift;;
            -a | --addr)    shift; addr=${1}; shift;;
            --onlypeer)     shift; onlypeer=1;;
            -P | --pubkey)  shift; peer_pubkey=${1}; shift;;
            --endpoint)     shift; endpoint=${1}; shift;;
            --allows)       shift; allows=${1}; shift;;
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
    [ -z ${addr} ] || is_ipv4_subnet ${addr} || usage "addr not ipv4/mask"

    [ -z ${onlypeer} ] && {
        [ -z ${prikey} ] && prikey=$(try wg genkey)
        vinfo_msg<<EOF
prikey      :${prikey}
pubkey      :$(try echo -n ${prikey} \| wg pubkey)
pubport     :${pubport}
addr        :${addr}
EOF
        gen_wg_interface "${prikey}" "${notable}" "${pubport}" "${addr}"
    }
    [ -z ${peer_pubkey} ] || {
        vinfo_msg<<EOF
peer_pubkey :${peer_pubkey}
endpoint    :${endpoint}
allows      :${allows}
EOF
        [ -z ${addr} ] && {
            allows=${allows:-0.0.0.0/0}
        } || {
            local tip= tmask=
            IFS='/' read -r tip tmask <<< "${addr}"
            allows=${allows:-$(get_ipv4_network ${tip} $(cidr2mask ${tmask}))/${tmask}}
        }
        gen_wg_peer "${peer_pubkey}" "${allows}" "${endpoint}"
    }
    return 0
}
main "$@"

: <<'EOF'
auto wg0
iface wg0 inet static
  address xxxxxxx
  pre-up ip link add wg0 type wireguard
  pre-up wg setconf wg0 /etc/wireguard/wg0.conf
  up ip link set wg0 up
  down ip link delete wg0

#!/usr/bin/env bash
# # add new peer
srv_interface=client
ipaddr=192.168.169.100/24
prikey=$(wg genkey)
pubkey=$(echo ${prikey} | wg pubkey)
srv_pubkey="$(wg show ${srv_interface} | grep 'public key:' | awk -F: '{print $2}')"

# # add new peer
cat <<EOF
wg set ${srv_interface} peer ${pubkey} allowed-ips $(echo ${ipaddr} | sed "s|/.*|/32|g")
# #  server config
[Peer]
PublicKey = ${pubkey}
AllowedIPs = $(echo ${ipaddr} | sed "s|/.*|/32|g")

# # client config
[Interface]
PrivateKey = ${prikey}
Address = ${ipaddr}
Table = off

[Peer]
PublicKey = ${srv_pubkey}
AllowedIPs = 0.0.0.0/0
Endpoint = srv_ip:port

# # server as router alllow other traffic to 192.168.2.53/32,10.170.6.0/24
wg set <interface> peer <pubkey> allowed-ips 192.168.32.2/32,192.168.2.53/32,10.170.6.0/24
EOF
EOF
