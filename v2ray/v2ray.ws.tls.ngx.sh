#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("f0e72981[2025-02-22T14:54:56+08:00]:v2ray.ws.tls.ngx.sh")
################################################################################
# export FILTER_CMD=cat;;
# export FILTER_CMD=tee output.log
uuid=$(cat /proc/sys/kernel/random/uuid)
alterid=0
wspath=/wssvc
SERVER=${SERVER:-tunl.wgserver.org}
cat <<EOF
export UUID=${uuid}
export ALTERID=${alterid}
export WSPATH=${wspath}
export SERVER=${SERVER}
./v2ray.ipset.transprant.sh
EOF
#V2Ray自4.18.1后支持TLS1.3
cat <<EOF > v2ray.cli.hosts
# # add to /etc/hosts
<you ip address> ${SERVER}
EOF
cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'} > v2ray.srv.config.json
{
  "inbounds": [
    {
      "port": 10000,
      "listen":"127.0.0.1",
      "protocol": "vless",
      "settings": {
        "decryption": "none",
        "clients": [
          {
            "id": "${uuid}",
            "alterId": ${alterid}
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "wsSettings": {
          "path": "${wspath}"
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

cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'} > v2ray.srv.nginx.http
server {
    listen 443 ssl;
    server_name _;
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
    location ${wspath} {
        if (\$http_upgrade != "websocket") {
            # WebSocket协商失败时返回404
            return 404;
        }
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

cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'} > v2ray.cli.config.json
{
  "log": {
    "access": "/dev/null",
    "error": "",
    "loglevel": "warning"
  },
  "inbounds": [
    # #################测试inbound start
    # curl -Is -x 127.0.0.1:10888 https://www.google.com -vvvv
    # test v2ray is ok
    {
      "listen": "127.0.0.1",
      "port": 10888,
      "protocol": "http"
    },
    {
      "listen": "127.0.0.1",
      "port": 1080,
      "protocol": "socks",
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      },
      "settings": {
        "auth": "noauth",
        "udp": false
      }
    }
  ],
  "outbounds": [
    {
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "${SERVER}",
            "port": 443,
            "users": [
              {
                "encryption":"none",
                "id": "${uuid}",
                "alterId": ${alterid}
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "allowInsecure": true,
          "disableSystemRoot": true,
          "certificates": [
            {
              //"certificate": [
              //  "-----BEGIN CERTIFICATE-----",
              //  "YipvxqZhPN+vV9fH",
              //  "-----END CERTIFICATE-----"
              //],
              //"key": [
              //  "-----BEGIN RSA PRIVATE KEY-----",
              //  "ZJfmJdQWx/cV9NYdqZYOj5KJjA==",
              //  "-----END RSA PRIVATE KEY-----"
              //],
              "certificateFile": "cert.pem",
              "keyFile": "cert.key",
              "usage": "encipherment"
              # verify,encipherment,issue
            }
          ]
        },
        "wsSettings": {
          "path": "${wspath}"
        }
      }
    }
  ]
}
EOF
cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'} >lib.systemd.system.v2ray.service
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
