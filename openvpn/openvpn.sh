#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("3a6bc32[2024-04-10T07:30:23+08:00]:openvpn.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -s|--ssh      *    ssh info (user@host)
        -p|--port          ssh port (default 60022)
        -c|--client    *   create client config
        --ca          **  ca cert
        --dh          *   dh2048.pem
        --cert        **  create client cert
        --key         **  create client key
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
            apt -y install openvpn gnutls-bin
EOF
    exit 1
}

init_server() {
    echo "apply nat rules"
    iptables -t nat -A POSTROUTING  -j MASQUERADE
    sysctl net.ipv4.ip_forward=1
    echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/99-openvpn-forward.conf
    # INLINE FILE SUPPORT
    # OpenVPN allows including files in the main configuration for the --ca, --cert, --dh, --extra-certs, --key, --pkcs12, --secret, --crl-verify, --http-proxy-user-pass, --tls-auth, --auth-gen-token-secret, --tls-crypt and --tls-crypt-v2 options.
    # <cert>
    # -----BEGIN CERTIFICATE-----
    # -----END CERTIFICATE-----
    # </cert>
    grep -v -E "^port |^proto |^dev |^ca |^cert |^key |^dh |^server |^push |^keepalive |^tls-auth |^status |^log |^log-append |^verb |^comp-lzo$|^persist-key$|^persist-tun$" /usr/share/doc/openvpn/*/sample-config-files/server.conf > /etc/openvpn/server/server.conf
    tee -a /etc/openvpn/server/vpnsrv.conf <<EOF
management localhost 7505
# # shaper n, Restrict output to peer to n bytes per second.
# shaper 2097152 # 2Mb
# mode p2p # # Major mode, m = 'p2p' (default, point-to-point) or 'server'.
# max-clients n # # max clients connect
#监听本机ip地址
local 0.0.0.0
port 1194
proto udp
# proto tcp
# explicit-exit-notify 0
dev tun
# 指定虚拟局域网占用的IP段
server 10.8.0.0 255.255.255.0
#服务器自动给客户端分配IP后，客户端下次连接时，仍然采用上次的IP地址
ifconfig-pool-persist ipp.txt
#自动推送客户端上的网关
#Redirect All Traffic through the VPN
push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 114.114.114.114"
# # use client gw
# push "route 10.0.0.0    255.0.0.0     net_gateway"
# push "route 172.16.0.0  255.240.0.0   net_gateway"
# push "route 192.168.0.0 255.255.0.0   net_gateway"
# # use vpn gw
# push "route 10.8.1.0    255.255.255.0 vpn_gateway"
#允许客户端与客户端相连接，默认情况下客户端只能与服务器相连接
client-to-client
#允许同一个客户端证书多次登录
#duplicate-cn
#最大连接用户
max-clients 100
#每10秒ping一次，连接超时时间设为120秒
keepalive 10 120
status      /var/log/openvpn-status.log
log         /var/log/openvpn.log
log-append  /var/log/openvpn.log
verb 3
cipher AES-256-GCM
# auth SHA256
comp-lzo
persist-key
persist-tun
# # Enable multiple clients to connect with the same certificate key
# duplicate-cn
# crl-verify crl.pem
<ca>
$(cat /etc/openvpn/server/ca.crt)
</ca>
<cert>
$(sed -ne '/BEGIN CERTIFICATE/,$ p' /etc/openvpn/server/server.crt)
</cert>
<key>
$(sed -ne '/BEGIN RSA PRIVATE KEY/,$ p' /etc/openvpn/server/server.key)
</key>
<dh>
$(cat /etc/openvpn/server/dh2048.pem)
</dh>
<tls-auth>
$(sed -ne '/BEGIN OpenVPN Static/,$ p' /etc/openvpn/server/ta.key)
</tls-auth>
EOF
    echo "enable openvpn-server@server.service"
    systemctl enable --now openvpn-server@vpnsrv
}

gen_clent_cert() {
    local ca="${1}"
    local cert="${2}"
    local key="${3}"
    local tlsauth="${4:-/dev/null}"
    echo "change client.conf remote & ca && cert && key && tls-auth && comp-lzo"
    cat <<EOF | tee client.ovpn
client
dev tun
proto udp
remote ########SRV ADDRESS######## 1194
# 使客户端中所有流量经过VPN,所有网络连接都使用vpn
# redirect-gateway def1
resolv-retry infinite
nobind
persist-key
persist-tun
# pull-filter ignore "route" ; ignore pull routers
# remote-cert-tls server # check server cert valid
# cipher AES-256-CBC
# # when up run script, add route etc..
# script-security 2
# up "/etc/openvpn/uproute.sh"
cipher AES-256-GCM
# fix: signature digest algorithm too weak
tls-cipher DEFAULT:@SECLEVEL=0
verb 3
comp-lzo
log         /var/log/openvpn_client.log
<ca>
$(cat ${ca})
</ca>
<cert>
$(sed -ne '/BEGIN CERTIFICATE/,$ p' ${cert})
</cert>
<key>
$(cat ${key})
</key>
<tls-auth>
$(sed -ne '/BEGIN OpenVPN Static/,$ p' ${tlsauth})
</tls-auth>
EOF
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
    [ -z "${ssh}" ] || {
        info_msg "init openvpn server ${ssh}\n"
        info_msg "  ca   = ${ca:?ca file need}\n"
        info_msg "  dh   = ${dh:?dh file need}\n"
        info_msg "  cert = ${cert:?cert file need}\n"
        info_msg "  key  = ${key:?key file need}\n"
        [ -z "${ca}" ] || [ -z "${dh}" ] || [ -z "${cert}" ] || [ -z "${key}" ] || {
            ssh_func "${ssh}" "${port}" "openvpn --genkey --secret /dev/stdout" > ta.key
            upload "ta.key" "${ssh}" "${port}" "/etc/openvpn/server/ta.key"
            upload "${ca}" "${ssh}" "${port}" "/etc/openvpn/server/ca.crt"
            upload "${dh}" "${ssh}" "${port}" "/etc/openvpn/server/dh2048.pem"
            upload "${cert}" "${ssh}" "${port}" "/etc/openvpn/server/server.crt"
            upload "${key}" "${ssh}" "${port}" "/etc/openvpn/server/server.key"
            ssh_func "${ssh}" "${port}" "chmod 600 /etc/openvpn/server/server.key"
            echo "Generate a random key to be used as a shared secret" 
            ssh_func "${ssh}" "${port}" init_server
        }
    }
    [ -z "${client}" ] || [ -z "${ca}" ] || [ -z "${cert}" ] || [ -z "${key}" ] || gen_clent_cert "${ca}" "${cert}" "${key}" "ta.key"
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
