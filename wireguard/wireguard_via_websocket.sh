#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("ff39de8[2024-08-12T16:49:14+08:00]:wireguard_via_websocket.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
IP_PREFIX=${IP_PREFIX:-192.168.32}

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
#    local cli2_pubkey=$(try echo -n ${cli2_prikey} \| wg pubkey)

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
$(for peer in ${clients[@]}; do
cat <<EOCFG
    location /$(array_get "${peer}" uri_prefix)/ {
        proxy_pass http://127.0.0.1:$(array_get "${peer}" wstunl_port);
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$http_host;
        proxy_set_header X-Real-IP \$remote_addr;
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
echo "PreUp = systemd-run --unit $(array_get "${peer}" uri_prefix) -p DynamicUser=yes wstunnel server --restrict-to 127.0.0.1:${wgsrv_port} ws://127.0.0.1:$(array_get ${peer} wstunl_port)"
echo "PostDown = systemctl stop $(array_get "${peer}" uri_prefix).service"
done)

$(for peer in ${clients[@]}; do
cat <<EOCFG
[Peer]
# $(array_get "${peer}" uri_prefix):$(array_get ${peer} wstunl_port)
PublicKey = $(array_get "${peer}" prikey | wg pubkey)
AllowedIPs = $(array_get "${peer}" address | sed "s|/.*|/32|g")
PersistentKeepalive = 25

EOCFG
done)
EOF
    try chmod 0600 "${cfg_file}"
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
Table = off
PreUp = systemd-run --unit ${cli_uuid} -p DynamicUser=yes wstunnel client -P ${cli_uuid} -L udp://127.0.0.1:${wgsrv_port}:127.0.0.1:${wgsrv_port} ${cli_cert:+--tls-certificate /etc/wstunnel/ssl/cli.pem }${cli_key:+--tls-private-key /etc/wstunnel/ssl/cli.key} --tls-sni-disable wss://${wgsrv_addr}:${ngx_port}
PostDown = systemctl stop ${cli_uuid}.service

[Peer]
PublicKey = ${srv_pubkey}
AllowedIPs = 0.0.0.0/0
Endpoint = 127.0.0.1:${wgsrv_port}
EOF
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
        env: IP_PREFIX, default 192.168.32
        env: NGX_SRV, default tunl.wgserver.org,
        env: NGX_PORT, default 443
             nginx & wireguard same server
        --srvcert   *   <file>      TLS nginx cert file
        --srvkey    *   <file>      TLS nginx key file
        --ca        *   <file>      TLS nginx verify client ca file
        --clicert   *   <file>      TLS client cert file
        --clikey    *   <file>      TLS client key file
        -n | --num      <int>       wg clients number, default 1
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
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
    local opt_long="srvcert:,srvkey:,ca:,clicert:,clikey:,num:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            --srvcert)      shift; valid_tls_file "${1}" "rror nginx server cert file" && srv_cert=${1}; shift;;
            --srvkey)       shift; valid_tls_file "${1}" "error nginx server key file" && srv_key=${1}; shift;;
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