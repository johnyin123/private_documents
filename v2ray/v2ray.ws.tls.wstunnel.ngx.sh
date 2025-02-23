#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
VERSION+=("initver[2025-02-23T13:42:09+08:00]:v2ray.ws.tls.wstunnel.ngx.sh")
################################################################################
# FILTER_CMD="cat"
################################################################################
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }
random() { shuf -i ${1:-1}-${2:-65535} -n ${3:-1}; }
################################################################################
# # v2ray server configurations
V2RAY_UUID=$(cat /proc/sys/kernel/random/uuid)
V2RAY_ALTERID=0
V2RAY_WSPATH=/wssvc
V2RAY_PORT=$(random 60000 64000)
NGX_SRVNAME=${NGX_SRVNAME:-tunl.wgserver.org}
NGX_WSPATH=$(cat /proc/sys/kernel/random/uuid)
################################################################################
# # v2ray server inner wstunnel port
wstunnel_port=$(random 50000 54000)
log "Gen client:" && cat <<EOF
V2RAY_UUID=${V2RAY_UUID} \\
V2RAY_ALTERID=${V2RAY_ALTERID} \\
V2RAY_WSPATH=${V2RAY_WSPATH} \\
V2RAY_PORT=${V2RAY_PORT} \\
NGX_SRVNAME=${NGX_SRVNAME} \\
NGX_WSPATH=${NGX_WSPATH} \\
./v2ray.ipset.transprant.wstunnel.sh
EOF
#V2Ray自4.18.1后支持TLS1.3
log "Gen v2srv.config.json" && cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'} > v2srv.config.json
{
  "inbounds": [
    {
      "port": ${V2RAY_PORT},
      "listen":"127.0.0.1",
      "protocol": "vless",
      "settings": {
        "decryption": "none",
        "clients": [
          {
            "id": "${V2RAY_UUID}",
            "alterId": ${V2RAY_ALTERID}
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "${V2RAY_WSPATH}"
        }
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "freedom",
      "settings": {}
    }
  ]
}
EOF
log "Gen v2srv.nginx.http" && cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'} > v2srv.nginx.http
server {
    listen 443 ssl;
    server_name ${NGX_SRVNAME};
    ssl_certificate /etc/nginx/ssl/test.pem;
    ssl_certificate_key /etc/nginx/ssl/test.key;
    # ssl_protocols       TLSv1 TLSv1.1 TLSv1.2;
    # ssl_protocols       TLSv1.3;
    ssl_client_certificate /etc/nginx/ssl/ca.pem;
    ssl_verify_client on;
    proxy_intercept_errors on;
    error_page 400 495 496 497 = @400;
    location @400 { return 500 "bad boy"; }
    #与V2Ray配置中的path保持一致
    location /${NGX_WSPATH}/ {
        proxy_pass http://127.0.0.1:${wstunnel_port};
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
}
EOF
log "Gen v2srv-wstunnel.service" && cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'} >v2srv-wstunnel.service
[Unit]
After=network-online.target
[Service]
Type=simple
DynamicUser=true
ExecStart=wstunnel server --restrict-to 127.0.0.1:${V2RAY_PORT} ws://127.0.0.1:${wstunnel_port}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
log "Gen v2srv.service" && cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'} >v2srv.service
[Unit]
Description=V2Ray Service
Documentation=https://www.v2ray.com/ https://www.v2fly.org/
After=network-online.target nss-lookup.target

[Service]
Type=simple
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
DynamicUser=true
NoNewPrivileges=true
Environment=V2RAY_LOCATION_ASSET=/etc/v2ray
ExecStart=/usr/bin/v2ray -config /etc/v2ray/config.json
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
log "all ok"
