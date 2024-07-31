#!/usr/bin/env bash
set -o errtrace
set -o nounset
set -o errexit

# REMOTE: opevpn-server & nginx-connect
# client: openvpn-client & stunnel
# client-->stunnel(https_proxy)===(internet)===>nginx-connect-->openvpn-server

REMOTE=${REMOTE:-you_sec_vpn_srv.com}
REMOTE_NGX_PORT=${REMOTE_NGX_PORT:-443}
STUNNEL_PORT=${STUNNEL_PORT:-8888}

LOGFILE=""
# LOGFILE="-a log.txt"
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }

log "need:dh2048.pem, ta.key, ovnsrv.pem, ovnsrv.key, ovncli.pem, ovncli.key, ovn_verifyclient_ca.pem"
log "nginx need :/etc/nginx/ssl/ngxsrv.pem, /etc/nginx/ssl/ngxsrv.key, /etc/nginx/ssl/ngx_verifyclient_ca.pem"
log "copy ngx_connect.conf, openvpn-server.conf to remote"
log "copy stunnel.conf, stunnel.pem, stunnel.key, openvpn-client.conf to local"
cat <<EOF
    /etc/nginx/ssl/ngx_verifyclient_ca.pem ----> ssl_verify_client stunnel.pem

# # all cert can user same ca !!
./newssl.sh -i myca --caroot myca
./newssl.sh  --caroot myca -c ngxsrv
cat myca/ngxsrv.key > ngxsrv.key
cat myca/ngxsrv.pem > ngxsrv.pem
./newssl.sh  --caroot myca -c stunnel
cat myca/stunnel.key > stunnel.key
cat myca/stunnel.pem > stunnel.pem
cat myca/ca.pem > ngx_verifyclient_ca.pem
# cat myca/ca.pem > ovn_verifyclient_ca.pem
# # # # # # # # # # # # # # # # # # # # # # # #
# # or openvpn user another ca
./newssl.sh -i ovnca --caroot ovnca
./newssl.sh  --caroot ovnca -c ovnsrv
cat ovnca/ovnsrv.key > ovnsrv.key
cat ovnca/ovnsrv.pem > ovnsrv.pem
./newssl.sh  --caroot ovnca -c ovncli
cat ovnca/ovncli.key > ovncli.key
cat ovnca/ovncli.pem > ovncli.pem
cat ovnca/ca.pem > ovn_verifyclient_ca.pem

openvpn --genkey --secret /dev/stdout > ta.key
cat myca/dh2048.pem > dh2048.pem

REMOTE=test.server.org REMOTE_NGX_PORT=4400 STUNNEL_PORT=8999 ./openvpn-stunnel-nginx-connect.sh
!!! openvpn server: mkdir -p /etc/openvpn/ccd
scp ngxsrv.pem ngxsrv.key ngx_verifyclient_ca.pem ngx_connect.conf openvpn-server.conf root@vpnserver:~/
scp stunnel.conf stunnel.pem stunnel.key openvpn-client.conf root@vpnclient:~/
systemctl enable stunnel@stunnel --now
EOF
cat <<EOF > stunnel.conf
syslog=no
foreground=yes
debug=info
output=/var/log/stunnel.log
pid=/var/run/stunnel.pid
cert=/etc/stunnel/stunnel.pem
key=/etc/stunnel/stunnel.key
[secretopenvpn]
client=yes
accept=127.0.0.1:${STUNNEL_PORT}
connect=${REMOTE}:${REMOTE_NGX_PORT}
EOF
log "start stunnel command: systemctl enable stunnel@aws --now"
cat << EOF > ngx_connect.conf
# load_module modules/ngx_http_proxy_connect_module.so;
server {
    listen ${REMOTE_NGX_PORT} ssl http2;
    # # nginx version > 1.25.1
    # http2 on;
    server_name _;
    ssl_certificate /etc/nginx/ssl/ngxsrv.pem;
    ssl_certificate_key /etc/nginx/ssl/ngxsrv.key;
    ssl_client_certificate /etc/nginx/ssl/ngx_verifyclient_ca.pem;
    ssl_verify_client on;
    access_log off;
    proxy_intercept_errors on;
    error_page 400 495 496 497 = @400;
    location @400 { return 500 "bad boy"; }
    # resolver 192.168.107.11 ipv6=off;
    proxy_connect;
    proxy_connect_connect_timeout 10s;
    proxy_connect_read_timeout 10s;
    proxy_connect_send_timeout 10s;
    # only can connect to localhost opevpn port 1194
    proxy_connect_allow 1194;
    if (\$connect_host !~ ^(|127.0.0.1)$) { return "403"; }
    location / { default_type text/html; return 444; }
    location /wssvc {
        # v2ray can here!!
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    }
}
EOF
vpn_common() {
    local log=${1:-openvpn.log}
    local ca=${2}
    local ta=${3}
    local cert=${4}
    local key=${5}
    exec 2> /dev/null
    cat <<EOF
verb 3
log /var/log/${log}
cipher AES-256-GCM
auth SHA256
persist-key
persist-tun
<ca>
$(cat ${ca})
</ca>
<tls-auth>
$(cat ${ta})
</tls-auth>
<cert>
$(cat ${cert})
</cert>
<key>
$(cat ${key})
</key>
EOF
}
cat << EOF > openvpn-server.conf
# management localhost 7505
# management /run/openvpn/server.sock unix
local 127.0.0.1
port 1194
proto tcp
dev tun
server 10.8.0.0 255.255.255.0
# topology net30/p2p/subnet
# # static client config dir, mkdir -p /etc/openvpn/ccd
client-config-dir ccd
# # [seconds] 0 mean ipp.txt is readonly, default 600
ifconfig-pool-persist ipp.txt 600
status ovn-srv.status
# # 允许客户端与客户端相连接，默认情况下客户端只能与服务器相连接
client-to-client
# # 允许同一个客户端证书多次登录
duplicate-cn
# # max clients connect
max-clients 10
# # 每10秒ping一次，连接超时时间设为120秒
keepalive 10 120
# crl-verify crl.pem
$(vpn_common "ovn_srv.log" "ovn_verifyclient_ca.pem" "ta.key" "ovnsrv.pem" "ovnsrv.key")
<dh>
$(exec 2> /dev/null; cat dh2048.pem)
</dh>
EOF
cat << EOF > openvpn-client.conf
client
remote 127.0.0.1 1194
proto tcp
dev tun
resolv-retry infinite
nobind
http-proxy-retry
http-proxy 127.0.0.1 ${STUNNEL_PORT}
http-proxy-option AGENT curl
http-proxy-option VERSION 1.1
# script-security 2
# up "/etc/openvpn/uproute.sh"
# pull-filter ignore "route"
$(vpn_common "ovn_cli.log" "ovn_verifyclient_ca.pem" "ta.key" "ovncli.pem" "ovncli.key")
EOF
