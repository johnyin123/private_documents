#!/usr/bin/env bash
# remote_srv: opevpn-server & nginx-connect
# client: openvpn-client & stunnel
# client-->stunnel(https_proxy)===(internet)===>nginx-connect-->openvpn-server
echo "need:dh2048.pem, ta.key, server.pem, server.key, client.pem, client.key"
echo "nginx need :/etc/nginx/ssl/srv.pem, /etc/nginx/ssl/srv.key, /etc/nginx/ssl/ca.pem"
remote_srv=192.168.168.111
remote_port=443
stunnel_port=8888
cat <<EOF > stunnel.conf
syslog=no
debug=7
output=/var/log/stunnel.log
pid=/var/run/stunnel.pid
cert=/etc/stunnel/stunnel.pem
key=/etc/stunnel/stunnel.pem
client=no
[socks5]
accept=${stunnel_port}
connect=${remote_srv}:${remote_port}
EOF

cat << EOF > ngx_connect.conf
# load_module modules/ngx_http_proxy_connect_module.so;
server {
    listen ${remote_port} ssl http2;
    server_name _;
    ssl_certificate /etc/nginx/ssl/srv.pem;
    ssl_certificate_key /etc/nginx/ssl/srv.key;
    ssl_client_certificate /etc/nginx/ssl/ca.pem;
    ssl_verify_client on;
    # resolver 192.168.107.11 ipv6=off;
    proxy_connect;
    proxy_connect_connect_timeout 10s;
    proxy_connect_read_timeout 10s;
    proxy_connect_send_timeout 10s;
    # only can connect to localhost opevpn port 1194
    proxy_connect_allow 1194;
    if (\$connect_host != "127.0.0.1") { return "403"; }
    location / { default_type text/html; return 444; }
}
EOF
cat << EOF > openvpn-server.conf
local 127.0.0.1
port 1194
proto tcp
dev tun
# 指定虚拟局域网占用的IP段
server 10.8.0.0 255.255.255.0
#服务器自动给客户端分配IP后，客户端下次连接时，仍然采用上次的IP地址
ifconfig-pool-persist ipp.txt
#允许客户端与客户端相连接，默认情况下客户端只能与服务器相连接
client-to-client
#允许同一个客户端证书多次登录
#duplicate-cn
#最大连接用户
max-clients 10
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
# push "route 10.0.0.0 255.255.255.0"
# push "dhcp-option DNS 114.114.114.114"
# crl-verify crl.pem
<ca>
$(cat ca.crt)
</ca>
<cert>
$(sed -ne '/BEGIN CERTIFICATE/,$ p' server.crt)
</cert>
<key>
$(sed -ne '/BEGIN RSA PRIVATE KEY/,$ p' server.key)
</key>
<dh>
$(cat dh2048.pem)
</dh>
<tls-auth>
$(sed -ne '/BEGIN OpenVPN Static/,$ p' ta.key)
</tls-auth>
EOF
cat << EOF > openvpn-client.conf
client
dev tun
proto tcp
remote 127.0.0.1 1194
resolv-retry infinite
nobind
persist-key
# persist-tun
http-proxy-retry
http-proxy 127.0.0.1 ${stunnel_port}
http-proxy-option AGENT curl
http-proxy-option VERSION 1.1
# script-security 2
# up "/etc/openvpn/uproute.sh"
# pull-filter ignore "route"
tls-cipher DEFAULT:@SECLEVEL=0
verb 3
comp-lzo
log         /var/log/openvpn_client.log
<ca>
$(cat ca.crt)
</ca>
<tls-auth>
$(sed -ne '/BEGIN OpenVPN Static/,$ p' ta.key)
</tls-auth>
<cert>
$(sed -ne '/BEGIN CERTIFICATE/,$ p' client.crt)
</cert>
<key>
$(sed -ne '/BEGIN RSA PRIVATE KEY/,$ p' client.key)
</key>
EOF
