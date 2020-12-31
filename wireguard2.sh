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
################################################################################
append() {
    local var="$1"
    local value="$2"
    local sep="${3:- }"
    eval "export ${NO_EXPORT:+-n} -- \"$var=\${$var:+\${$var}\${value:+\$sep}}\$value\""
}

gen_wireguard() {
    #    name      WG_IP          MASK  PUBLIC_IP         PUBLIC_PORT
    nodes=" \
        node1    172.16.16.1    24    202.111.11.111    50055 \
        node2    172.16.16.2    24    ''                '' \
        node3    172.16.16.3    24    ''                '' \
        "
    set $nodes
    local i=0
    while [ "$#" != 0 ]; do
        NAME=${1}
        IP=${2}
        MASK=${3}
        PUB_IP=${4}
        PUB_PORT=${5}
        PRI_KEY=$(wg genkey)
        PUB_KEY=$(echo -n "${PRI_KEY}" | wg pubkey)
        shift 5
        let i=i+1
        echo "[Interface]"
        echo "# $NAME interface info"
        echo "Address = ${IP}/${MASK}"
        [ "${PUB_PORT}" = "''" ] || echo "ListenPort = ${PUB_PORT}"
        echo "PrivateKey = ${PRI_KEY}"
        echo "##################################################"
        echo "[Peer]"
        echo "# $NAME peer info"
        echo "PublicKey = ${PUB_KEY}"
        echo "AllowedIPs = ${IP}/32"
        [ "${PUB_IP}" = "''" ] || echo "Endpoint = ${PUB_IP}:${PUB_PORT}"
        echo "PersistentKeepalive = 10"
        echo "##################################################"
    done
}

main() {
    gen_wireguard
    return 0
}
main "$@"
