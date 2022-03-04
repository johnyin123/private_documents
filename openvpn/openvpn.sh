#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("7e26349[2021-10-14T09:54:39+08:00]:openvpn.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -s|--ssh      *    ssh info (user@host)
        -p|--port          ssh port (default 60022)
        -i|--init          init openvpn server
        -c|--client        create client cert keys
        --caroot           CA root(default /root/ca)
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
EOF
    exit 1
}

init_server() {
    local caroot=${1}
    [ -d "${caroot}" ] && return 1
    mkdir -p ${caroot}
    echo "generate ca"
    cat << EOF > ${caroot}/ca.info
cn = openvpn ca
ca
cert_signing_key
expiration_days = $((365*5))
EOF
    certtool --generate-privkey --bits=2048 > ${caroot}/ca.key
    certtool --generate-self-signed --load-privkey ${caroot}/ca.key \
        --template ${caroot}/ca.info \
        --outfile ${caroot}/ca.crt
    certtool -i --infile=${caroot}/ca.crt || true
    #openssl x509 -text -noout -in ${caroot}/ca.crt || true
    echo "gen openvpn server cert"
    cat << EOF > ${caroot}/server.info
organization = openvpn server
cn = openvpn-srv
signing_key
expiration_days = $((365*5))
EOF
    certtool --generate-privkey --bits=2048 > ${caroot}/server.key
    certtool --generate-certificate --load-privkey ${caroot}/server.key \
        --load-ca-certificate ${caroot}/ca.crt \
        --load-ca-privkey ${caroot}/ca.key \
        --template ${caroot}/server.info \
        --outfile ${caroot}/server.crt
    echo "generate dh 2048"
    certtool --generate-dh-params --outfile ${caroot}/dh2048.pem --sec-param medium
    echo "Generate a random key to be used as a shared secret" 
    openvpn --genkey --secret ${caroot}/ta.key
    echo "copy generated certs"
    cp ${caroot}/ca.crt ${caroot}/ta.key ${caroot}/dh2048.pem \
       ${caroot}/server.crt ${caroot}/server.key \
       /etc/openvpn/server/
    chmod 600 /etc/openvpn/server/server.key 
    echo "apply nat"
    iptables -t nat -A POSTROUTING  -j MASQUERADE
    sysctl net.ipv4.ip_forward=1
}

modify_openvpn_cfg() {
    # INLINE FILE SUPPORT
    # OpenVPN allows including files in the main configuration for the --ca, --cert, --dh, --extra-certs, --key, --pkcs12, --secret, --crl-verify, --http-proxy-user-pass, --tls-auth, --auth-gen-token-secret, --tls-crypt and --tls-crypt-v2 options.
    # <cert>
    # -----BEGIN CERTIFICATE-----
    # -----END CERTIFICATE-----
    # </cert>
    grep -v -E "^port |^proto |^dev |^ca |^cert |^key |^dh |^server |^push |^keepalive |^tls-auth |^status |^log |^log-append |^verb |^comp-lzo$|^persist-key$|^persist-tun$" /usr/share/doc/openvpn*/sample/sample-config-files/server.conf > /etc/openvpn/server/server.conf
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
    local caroot=${1}
    local cid=${2}
    [ -e "${caroot}/client_${cid}.info" ] && return 1
    cat << EOF > ${caroot}/client_${cid}.info
organization = ${cid} 
cn = ${cid}
signing_key
EOF
    certtool --generate-privkey > ${caroot}/client_${cid}.key
    certtool --generate-certificate --load-privkey ${caroot}/client_${cid}.key \
        --load-ca-certificate ${caroot}/ca.crt \
        --load-ca-privkey ${caroot}/ca.key \
        --template ${caroot}/client_${cid}.info \
        --outfile ${caroot}/client_${cid}.crt
    tar -C ${caroot} -cv ca.crt client_${cid}.key client_${cid}.crt ta.key | gzip > ${caroot}/${cid}.tar.gz
    echo "${caroot}/${cid}.tar.gz --> TO CLIENT"
    echo "change client.conf remote & ca && cert && key && tls-auth && comp-lzo"
}

main() {
    local ssh="" port=60022 init="" client=""  caroot="/root/ca"
    local opt_short="s:p:ic:"
    local opt_long="ssh:,port:,init,client:,caroot:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -s | --ssh)     shift; ssh=${1}; shift;;
            -p | --port)    shift; port=${1}; shift;;
            -i | --init)    shift; init=1;;
            -c | --client)  shift; client=${1}; shift;;
            --caroot)       shift; caroot=${1}; shift;;
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
    [ -z "${init}" ] || {
        info_msg "install package\n"
        ssh_func "${ssh}" "${port}" "yum -y install epel-release"
        ssh_func "${ssh}" "${port}" "yum -y install openvpn"
        ssh_func "${ssh}" "${port}" "yum -y install gnutls-utils"
        # apt -y install gnutls-bin
        info_msg "init openvpn server env\n"
        ssh_func "${ssh}" "${port}" init_server "${caroot}"
        ssh_func "${ssh}" "${port}" modify_openvpn_cfg
    }
    [ -z "${client}" ] || {
        info_msg "generate client [${client}] openvpn cert\n"
        ssh_func "${ssh}" "${port}" gen_clent_cert "${caroot}" "${client}"
    }
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
