#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("e0a823a[2024-09-05T16:43:39+08:00]:wireguard_via_websocket.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
IP_PREFIX=${IP_PREFIX:-192.168.32}
KEEPALIVE=${KEEPALIVE:-25}
gen_all() {
    local dir=${1}
    local srv_cert=${2}
    local srv_key=${3}
    local cli_ca=${4}
    local cli_cert=${5}
    local cli_key=${6}
    local nclients=${7}
    local ngx_port=${NGX_PORT:-443}
    local wgsrv_addr=${NGX_SRV:-tunl.wgserver.org}
    local wgsrv_port=$(random 65000 65500)
    local srv_prikey=$(wg genkey)
    local srv_pubkey=$(echo -n ${srv_prikey} | wg pubkey)
    local PREFIX="${dir}"
    # # clients
    local ip_cli=2
    local clients=()
    for cli in $(random 60000 64999 ${nclients} | sort -n); do
        eval "declare -A peer${cli}=()"
        array_set "peer${cli}" prikey "$(wg genkey)"
        array_set "peer${cli}" uri_prefix "$(uuid)"
        array_set "peer${cli}" wstunl_port "${cli}"
        array_set "peer${cli}" address "${IP_PREFIX}.${ip_cli}/24"
        clients+=(peer${cli})
        let "ip_cli++"
    done

    info_msg "# # server start # #\n"
    PREFIX="${dir}/server"
    info_msg "# nginx configuration\n"
    cfg_file="${PREFIX}/etc/nginx/http-available/wgngx.conf"
    try mkdir -p $(dirname "${cfg_file}") && try cat <<EOF \> "${cfg_file}"
server {
    listen ${ngx_port} ssl http2;
    server_name ${wgsrv_addr};
    ssl_certificate /etc/nginx/ssl/ngxsrv.pem;
    ssl_certificate_key /etc/nginx/ssl/ngxsrv.key;
    ssl_client_certificate /etc/nginx/ssl/ngx_verifyclient_ca.pem;
    ssl_verify_client on;
    access_log off;
    proxy_buffering off;
    proxy_intercept_errors on;
    error_page 400 495 496 497 = @400;
    location @400 { return 500 "bad boy"; }
    location / { default_type text/html; return 444; }
$(for peer in ${clients[@]}; do
cat <<EOCFG
    location /$(array_get "${peer}" uri_prefix)/ {
        proxy_pass http://127.0.0.1:$(array_get "${peer}" wstunl_port);
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_connect_timeout 10m;
        proxy_send_timeout    10m;
        proxy_read_timeout    90m;
        send_timeout          10m;
    }
EOCFG
done)
}
EOF
    try mkdir -p ${PREFIX}/etc/nginx/ssl
    try cat ${srv_cert} \> ${PREFIX}/etc/nginx/ssl/ngxsrv.pem
    try cat ${srv_key} \> ${PREFIX}/etc/nginx/ssl/ngxsrv.key
    try cat ${cli_ca} \> ${PREFIX}/etc/nginx/ssl/ngx_verifyclient_ca.pem

    info_msg "# wireguard configuration\n"
    cfg_file="${PREFIX}/etc/wireguard/server.conf"
    try mkdir -p -m 0700 $(dirname "${cfg_file}") && try cat <<EOF \> "${cfg_file}"
[Interface]
PrivateKey = ${srv_prikey}
Address = ${IP_PREFIX}.1/24
MTU=1420
Table = off
ListenPort = ${wgsrv_port}
# %i is wireguard interface, see wg-quick->execute_hooks
$(for peer in ${clients[@]}; do
echo "PreUp = /bin/bash -c 'ns_name=\$(ip netns identify \$\$);systemd-run --unit $(array_get "${peer}" uri_prefix) \${ns_name:+-p NetworkNamespacePath=/run/netns/\${ns_name} }-p DynamicUser=yes wstunnel server --no-color 1 --restrict-to 127.0.0.1:${wgsrv_port} ws://127.0.0.1:$(array_get ${peer} wstunl_port)'"
echo "PostDown = systemctl stop $(array_get "${peer}" uri_prefix).service"
done)
    info_msg "systemctl reset-failed $(array_get "${peer}" uri_prefix).service\n"
$(for peer in ${clients[@]}; do
cat <<EOCFG
[Peer]
# $(array_get "${peer}" uri_prefix):$(array_get ${peer} wstunl_port)
PublicKey = $(array_get "${peer}" prikey | wg pubkey)
AllowedIPs = $(array_get "${peer}" address | sed "s|/.*|/32|g")
PersistentKeepalive = ${KEEPALIVE}

EOCFG
done)
EOF
    try chmod 0600 "${cfg_file}"
    cat <<EOF | vinfo2_msg
# # server as router alllow other traffic to 192.168.2.53/32,10.170.6.0/24
wg set <interface> peer <32.2 pubkey> allowed-ips 192.168.32.2/32,192.168.2.53/32,10.170.6.0/24
ip r a 192.168.2.53/32 via 192.168.32.2
ip r a 10.170.6.0/24 via 192.168.32.2
# # other peers add
ip r a 192.168.2.53 via 192.168.32.1
ip r a 10.170.6.0/24 via 192.168.32.1
EOF
    info_msg "# # server end # #\n"

    info_msg "# # client start # #\n"
    for peer in ${clients[@]}; do
        PREFIX="${dir}/${peer}"
        info_msg "# wstunnel ssl key\n"
        try mkdir -p -m 0755 ${PREFIX}/etc/wstunnel/ssl
        try cat ${cli_cert} \> ${PREFIX}/etc/wstunnel/ssl/cli.pem
        try cat ${cli_key} \> ${PREFIX}/etc/wstunnel/ssl/cli.key
        try chmod 0733 ${PREFIX}/etc/wstunnel/ssl/cli.pem ${PREFIX}/etc/wstunnel/ssl/cli.key
        info_msg "# wireguard configuration\n"
        local cli_uuid="$(array_get "${peer}" uri_prefix)"
        cfg_file="${PREFIX}/etc/wireguard/client.conf"
        try mkdir -p -m 0700 $(dirname "${cfg_file}") && try cat <<EOF \> "${cfg_file}"
[Interface]
PrivateKey = $(array_get "${peer}" prikey)
Address = $(array_get "${peer}" address)
MTU=1420
Table = off
PreUp = /bin/bash -c 'ns_name=\$(ip netns identify \$\$);systemd-run --unit ${cli_uuid} \${ns_name:+-p NetworkNamespacePath=/run/netns/\${ns_name} }-p DynamicUser=yes wstunnel client --no-color 1 -P ${cli_uuid} -L udp://127.0.0.1:${wgsrv_port}:127.0.0.1:${wgsrv_port} ${cli_cert:+--tls-certificate /etc/wstunnel/ssl/cli.pem }${cli_key:+--tls-private-key /etc/wstunnel/ssl/cli.key} --tls-sni-disable wss://${wgsrv_addr}:${ngx_port}'
PostDown = systemctl stop ${cli_uuid}.service

[Peer]
PublicKey = ${srv_pubkey}
AllowedIPs = 0.0.0.0/0
Endpoint = 127.0.0.1:${wgsrv_port}
PersistentKeepalive = ${KEEPALIVE}
EOF
        info_msg "systemctl reset-failed  ${cli_uuid}.service\n"
        try chmod 0600 "${cfg_file}"
    done
    info_msg "# # client end # #\n"

    cat <<EOF | vinfo2_msg
==============================================
SERVER: ${wgsrv_addr}:${ngx_port}
create package:
fpm --package `pwd` --architecture all -s dir -t deb -C server --name wg_wstunl_server --version 1.0 --iteration 1 --description 'wg wstunnel' .
# ln -s ../http-available/wgngx.conf /etc/nginx/http-enabled/
# systemctl enable nginx --now
# # copy wstunnel /usr/bin/
# wg-quick up server

$(for peer in ${clients[@]}; do
echo "fpm --package `pwd` --architecture all -s dir -t deb -C ${peer} --name wg_wstunl_${peer} --version 1.0 --iteration 1 --description 'wg wstunnel $(array_get "${peer}" address | sed "s|/.*||g")' ."
done)
# echo '<wg server ipaddr> tunl.wgserver.org' >> /etc/hosts
# wg-quick up client
==============================================
EOF
}
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        https://github.com/erebe/wstunnel, download wstunnel
        env: KEEPALIVE, PersistentKeepalive default 25
        env: IP_PREFIX, default 192.168.32
        env: NGX_SRV, default tunl.wgserver.org,
        env: NGX_PORT, default 443
             nginx & wireguard same server
        --ngxcert   *   <file>      TLS nginx cert file
        --ngxkey    *   <file>      TLS nginx key file
        --ca        *   <file>      TLS nginx verify client ca file
        --clicert   *   <file>      TLS client cert file
        --clikey    *   <file>      TLS client key file
        -n | --num      <int>       wg clients number, default 1
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
        multi peers, AllowedIPs must different!!
        DEBUG:
        modprobe wireguard && echo module wireguard +p > /sys/kernel/debug/dynamic_debug/control
        # # gretap over wireguard use linux bridge L2
        ip l a gretap0 type gretap local <ip> remote <ip2>
        ip link set gretap0 master <bridge>
        ............
EOF
    exit 1
}

valid_tls_file() {
    local file="${1}"
    local usage_msg="${2}"
    file_exists "${file}" && return 0
    usage "${usage_msg}, file ${file} nofound"
}

main() {
    local srv_cert="" srv_key="" cli_ca="" cli_cert="" cli_key="" nclients=1
    local opt_short="n:"
    local opt_long="ngxcert:,ngxkey:,ca:,clicert:,clikey:,num:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            --ngxcert)      shift; valid_tls_file "${1}" "error nginx server cert file" && srv_cert=${1}; shift;;
            --ngxkey)       shift; valid_tls_file "${1}" "error nginx server key file" && srv_key=${1}; shift;;
            --ca)           shift; valid_tls_file "${1}" "error client verify ca file" && cli_ca=${1}; shift;;
            --clicert)      shift; valid_tls_file "${1}" "error client cert file" && cli_cert=${1}; shift;;
            --clikey)       shift; valid_tls_file "${1}" "error client file file" && cli_key=${1}; shift;;
            -n | --num)     shift; nclients=${1} ; shift;;
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
    [ -z "${srv_cert}" ] || [ -z "${srv_key}" ] || [ -z "${cli_ca}" ] || [ -z "${cli_cert}" ] || [ -z "${cli_key}" ] && usage "cert/key/ca must input"
    gen_all "$(pwd)" "${srv_cert}" "${srv_key}" "${cli_ca}" "${cli_cert}" "${cli_key}" "${nclients}"
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
