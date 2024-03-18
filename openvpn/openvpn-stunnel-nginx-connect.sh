#!/usr/bin/env bash
# REMOTE: opevpn-server & nginx-connect
# client: openvpn-client & stunnel
# client-->stunnel(https_proxy)===(internet)===>nginx-connect-->openvpn-server
echo "need:dh2048.pem, ta.key, server.pem, server.key, client.pem, client.key"
echo "nginx need :/etc/nginx/ssl/srv.pem, /etc/nginx/ssl/srv.key, /etc/nginx/ssl/ca.pem"
echo "copy ngx_connect.conf, openvpn-server.conf to remote"
echo "copy stunnel.conf, stunnel.pem, stunnel.key, openvpn-client.conf to local"
REMOTE=${REMOTE:-192.168.168.111}
REMOTE_NGX_PORT=${REMOTE_NGX_PORT:-443}
STUNNEL_PORT=8888
cat <<EOF > aws.conf
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
echo "systemctl enable stunnel@aws --now"
cat << EOF > ngx_connect.conf
# load_module modules/ngx_http_proxy_connect_module.so;
server {
    listen ${REMOTE_NGX_PORT} ssl http2;
    server_name _;
    ssl_certificate /etc/nginx/ssl/srv.pem;
    ssl_certificate_key /etc/nginx/ssl/srv.key;
    ssl_client_certificate /etc/nginx/ssl/ca.pem;
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
management localhost 7505
local 127.0.0.1
port 1194
proto tcp
dev tun
# 指定虚拟局域网占用的IP段
server 10.8.0.0 255.255.255.0
#允许客户端与客户端相连接，默认情况下客户端只能与服务器相连接
client-to-client
#允许同一个客户端证书多次登录
duplicate-cn
#最大连接用户
max-clients 10
#每10秒ping一次，连接超时时间设为120秒
keepalive 10 120
status      /var/log/openvpn-status.log
# push "route 10.0.0.0 255.255.255.0"
# push "dhcp-option DNS 114.114.114.114"
# crl-verify crl.pem
$(vpn_common "ovn_srv.log" "ca.pem" "ta.key" "server.pem" "server.key")
<dh>
$(cat dh2048.pem)
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
$(vpn_common "ovn_cli.log" "ca.pem" "ta.key" "client.pem" "client.key")
EOF
