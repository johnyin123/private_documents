#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("7af84c0[2023-04-23T09:42:15+08:00]:openvpn.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -s|--ssh      *    ssh info (user@host)
        -p|--port          ssh port (default 60022)
        -c|--client    *   create client cert keys
        --ca          *   create client cert keys
        --dh          *   create client cert keys
        --cert        *   create client cert keys
        --key         *   create client cert keys
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        gen ca & server cert:
            ./newssl.sh -i "openvpn ca"  -c "vpnsrv1"
            ./openvpn.sh -s root@server1 -c --ca ca.pem --dh ca/dh2048.pem --cert vpnsrv1.pem --key vpnsrv1.key
        centos:
            yum -y install epel-release
            yum -y install openvpn gnutls-utils
        debian:
            apt -y install openvpn
EOF
    exit 1
}

upload() {
    local lfile=${1}
    local ssh=${2}
    local port=${3}
    local rfile=${4}
    warn_msg "upload ${lfile} ====> ${ssh}:${port}${rfile}\n"
    try scp -P${port} ${lfile} ${ssh}:${rfile}
}

init_server() {
    echo "Generate a random key to be used as a shared secret" 
    openvpn --genkey --secret /etc/openvpn/server/ta.key
    echo "apply nat rules"
    iptables -t nat -A POSTROUTING  -j MASQUERADE
    sysctl net.ipv4.ip_forward=1
    # INLINE FILE SUPPORT
    # OpenVPN allows including files in the main configuration for the --ca, --cert, --dh, --extra-certs, --key, --pkcs12, --secret, --crl-verify, --http-proxy-user-pass, --tls-auth, --auth-gen-token-secret, --tls-crypt and --tls-crypt-v2 options.
    # <cert>
    # -----BEGIN CERTIFICATE-----
    # -----END CERTIFICATE-----
    # </cert>
    grep -v -E "^port |^proto |^dev |^ca |^cert |^key |^dh |^server |^push |^keepalive |^tls-auth |^status |^log |^log-append |^verb |^comp-lzo$|^persist-key$|^persist-tun$" /usr/share/doc/openvpn/*/sample-config-files/server.conf > /etc/openvpn/server/server.conf
    tee -a /etc/openvpn/server/server.conf <<EOF
port 1194
proto udp
dev tun
ca       ca.crt
cert     server.crt
key      server.key
dh       dh2048.pem
tls-auth ta.key 0
server 10.8.0.0 255.255.255.0
keepalive 10 120
status      /var/log/openvpn-status.log
log         /var/log/openvpn.log
log-append  /var/log/openvpn.log
verb 3
comp-lzo
persist-key
persist-tun
# push "route 10.0.0.0 255.255.255.0"
EOF
    echo "enable openvpn-server@server.service"
    systemctl enable --now openvpn-server@server
}

gen_clent_cert() {
    echo "change client.conf remote & ca && cert && key && tls-auth && comp-lzo"
    echo "Generates the custom file client.ovpn"
    {
        echo "client"
        echo "dev tun"
        echo "proto udp"
        echo "remote ########SRV ADDRESS######## 1194"
        echo "resolv-retry infinite"
        echo "nobind"
        echo "persist-key"
        echo "persist-tun"
        echo "remote-cert-tls server"
        echo "cipher AES-256-CBC"
        echo "verb 3"
        echo "<ca>"
        echo "########CA FILE INLINE HERE########"
        echo "</ca>"
        echo "<cert>"
        echo 'sed -ne '/BEGIN CERTIFICATE/,$ p' ${caroot}/client.crt'
        echo "</cert>"
        echo "<key>"
        echo "########CLIENT KEY INLINE HERE########"
        echo "</key>"
        echo "<tls-crypt>"
        echo 'sed -ne '/BEGIN OpenVPN Static key/,$ p' ta.key'
        echo "</tls-crypt>"
    } | tee client.vpn
}

main() {
    local ssh="" port=60022 client=""
    local ca="" dh="" cert="" key=""
    local opt_short="s:p:c"
    local opt_long="ssh:,port:,client,ca:,dh:,cert:,key:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -s | --ssh)     shift; ssh=${1}; shift;;
            -p | --port)    shift; port=${1}; shift;;
            -c | --client)  shift; client=1;;
            --ca)           shift; ca=${1}; shift;;
            --dh)           shift; dh=${1}; shift;;
            --cert)         shift; cert=${1}; shift;;
            --key)          shift; key=${1}; shift;;
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
    [ -z "${client}" ] || gen_clent_cert
    [ -z "${ssh}" ] || {
        info_msg "init openvpn server ${ssh}\n"
        info_msg "  ca   = ${ca:?ca file need}\n"
        info_msg "  dh   = ${dh:?dh file need}\n"
        info_msg "  cert = ${cert:?cert file need}\n"
        info_msg "  key  = ${key:?key file need}\n"
        [ -z "${ca}" ] || [ -z "${dh}" ] || [ -z "${cert}" ] || [ -z "${key}" ] || {
            upload "${ca}" "${ssh}" "${port}" "/etc/openvpn/server/ca.crt"
            upload "${dh}" "${ssh}" "${port}" "/etc/openvpn/server/dh2048.pem"
            upload "${cert}" "${ssh}" "${port}" "/etc/openvpn/server/server.crt"
            upload "${key}" "${ssh}" "${port}" "/etc/openvpn/server/server.key"
            ssh_func "${ssh}" "${port}" "chmod 600 /etc/openvpn/server/server.key"
            ssh_func "${ssh}" "${port}" init_server
        }
    }
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
