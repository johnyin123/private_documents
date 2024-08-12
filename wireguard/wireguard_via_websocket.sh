#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("c5eace0[2024-08-12T13:31:14+08:00]:wireguard_via_websocket.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
# https://github.com/erebe/wstunnel
IP_PREFIX=${IP_PREFIX:-192.168.32}
gen_wstunnel_svc() {
    # # ERROR # ExecStart=/usr/bin/wstunnel ${DAEMON_ARGS}
    cat <<'EOF'
[Unit]
Description=websocket tunnel
After=network.target

[Service]
Type=simple
# User=nobody
DynamicUser=yes
EnvironmentFile=-/etc/wstunnel/%i.conf
ExecStart=/usr/bin/wstunnel $DAEMON_ARGS
Restart=no

[Install]
WantedBy=multi-user.target
EOF
}

gen_all() {
    local dir=${1}
    local srv_cert=${2}
    local srv_key=${3}
    local cli_ca=${4}
    local cli_cert=${5}
    local cli_key=${6}
    local nclients=${7}
    local ngx_port=${NGX_PORT:-443}
    local wgsrv_addr=${NGX_SRV:-1.2.3.4}
    local wgsrv_port=$(random 65000 65500)
    local srv_prikey=-$(try wg genkey)
    local srv_pubkey=$(try echo -n ${srv_prikey} \| wg pubkey)
    local PREFIX="${dir}"
    # # clients
    ip_cli=2 
    clients=()
    for cli in $(random 60000 64999 ${nclients});  do
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
    info_msg "# wstunnel service configuration\n"
    cfg_file="${PREFIX}/usr/lib/systemd/system/wstunnel@.service"
    mkdir -p $(dirname "${cfg_file}") && gen_wstunnel_svc > "${cfg_file}"

    for peer in ${clients[@]}; do
        cfg_file="${PREFIX}/etc/wstunnel/${peer}.conf"
        mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
DAEMON_ARGS="server --restrict-to 127.0.0.1:${wgsrv_port} ws://127.0.0.1:$(array_get "${peer}" wstunl_port)
EOF
    done

    info_msg "# nginx configuration\n"
    cfg_file="${PREFIX}/etc/nginx/http-available/wgngx.conf"
    mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
server {
    listen ${ngx_port} ssl http2;
    server_name _;
    ssl_certificate /etc/nginx/ssl/ngxsrv.pem;
    ssl_certificate_key /etc/nginx/ssl/ngxsrv.key;
    ssl_client_certificate /etc/nginx/ssl/ngx_verifyclient_ca.pem;
    ssl_verify_client on;
    access_log off;
$(for peer in ${clients[@]}; do
cat <<EOCFG
    location /$(array_get "${peer}" uri_prefix)/ {
        proxy_pass http://127.0.0.1:$(array_get "${peer}" wstunl_port);
        proxy_http_version  1.1;
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
    mkdir -p ${PREFIX}/etc/nginx/ssl
    cat ${srv_cert} > ${PREFIX}/etc/nginx/ssl/ngxsrv.pem
    cat ${srv_key} > ${PREFIX}/etc/nginx/ssl/ngxsrv.key
    cat ${cli_ca}   > ${PREFIX}/etc/nginx/ssl/ngx_verifyclient_ca.pem

    info_msg "# wireguard configuration\n"
    cfg_file="${PREFIX}/etc/wireguard/server.conf"
    mkdir -p -m 0700 $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
[Interface]
PrivateKey = ${srv_prikey}
Address = ${IP_PREFIX}.1/24
MTU=1420
Table = off
# %i is wireguard interface, see wg-quick->execute_hooks 
# PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o ens3 -j MASQUERADE
# PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o ens3 -j MASQUERADE
ListenPort = ${wgsrv_port}
$(for peer in ${clients[@]}; do
cat <<EOCFG
[Peer]
PublicKey = $(array_get "${peer}" prikey | wg pubkey)
AllowedIPs = $(array_get "${peer}" address | sed "s|/.*|/32|g")
PersistentKeepalive = 25
EOCFG
done)
EOF
    chmod 0600  "${cfg_file}"
    info_msg "# # server end # #\n" 

    info_msg "# # client start # #\n"
    for peer in ${clients[@]}; do
        PREFIX="${dir}/${peer}"
        info_msg "# wstunnel service configuration\n"
        cfg_file="${PREFIX}/usr/lib/systemd/system/wstunnel@.service"
        mkdir -p $(dirname "${cfg_file}") && gen_wstunnel_svc > "${cfg_file}"
        cfg_file="${PREFIX}/etc/wstunnel/wireguard.conf"
        mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
DAEMON_ARGS="client -P $(array_get "${peer}" uri_prefix) -L udp://127.0.0.1:${wgsrv_port}:127.0.0.1:${wgsrv_port} ${cli_cert:+--tls-certificate /etc/wstunnel/ssl/cli.pem }${cli_key:+--tls-private-key /etc/wstunnel/ssl/cli.key} wss://${wgsrv_addr}:${ngx_port}"
EOF
        mkdir -p ${PREFIX}/etc/wstunnel/ssl
        cat ${cli_cert} > ${PREFIX}/etc/wstunnel/ssl/cli.pem
        cat ${cli_key} > ${PREFIX}/etc/wstunnel/ssl/cli.key
        info_msg "# wireguard configuration\n"
        cfg_file="${PREFIX}/etc/wireguard/client.conf"
        mkdir -p -m 0700 $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
[Interface]
PrivateKey = $(array_get "${peer}" prikey)
Address = $(array_get "${peer}" address)
Table = off

[Peer]
PublicKey = ${srv_pubkey}
AllowedIPs = 0.0.0.0/0
Endpoint = 127.0.0.1:${wgsrv_port}
EOF
        chmod 0600  "${cfg_file}"
    done
    info_msg "# # client end # #\n"

    cat <<EOF | vinfo2_msg
==============================================
SERVER:   ${wgsrv_addr}
NGX PORT: ${ngx_port}
create package:
# # modify ${dir}/client/etc/wireguard/server.conf, add more peer
fpm --package `pwd` --architecture all -s dir -t deb -C server --name wg_wstunl_server --version 1.0 --iteration 1 --description 'wg wstunnel' .
# ln -s ../http-available/wgngx.conf /etc/nginx/http-enabled/
# systemctl enable nginx --now
# # copy wstunnel /usr/bin/
# systemctl enable wstunnel@wireguard --now
# wg-quick up server

$(for peer in ${clients[@]}; do
echo "fpm --package `pwd` --architecture all -s dir -t deb -C ${peer} --name wg_wstunl_${peer} --version 1.0 --iteration 1 --description 'wg wstunnel' ."
done)
# echo '<wg server ipaddr> tunl.wgserver.org' >> /etc/hosts
# systemctl enable wstunnel@wireguard --now
# wg-quick up client
==============================================
EOF
}
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        env: NGX_SRV, default 1.2.3.4,
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
