#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
################################################################################
# https://github.com/UmeLabs/node.umelabs.dev
# V2Ray:https://raw.githubusercontent.com/umelabs/node.umelabs.dev/master/Subscribe/v2ray.md
# geosite/geoip: https://github.com/Loyalsoldier/v2ray-rules-dat/releases
cat <<'EOF'
curl -kv -x http://srv:port http://www
# remove single line /**/ common
sed -E 's/\/\*([^*]|\*+[^/*])*\*+\///g'
# list all vars
grep -o "\${[^}]*}" proxy.json
EOF
CLI_WST_PORT=${CLI_WST_PORT:-}

PROXY_SRV=${PROXY_SRV:-UNDEF}
PROXY_PORT=${PROXY_PORT:-UNDEF}
PROXY_USER=${PROXY_USER:-UNDEF}
PROXY_PASS=${PROXY_PASS:-UNDEF}
VLESS_IP=${VLESS_IP:-UNDEF}
VLESS_PORT=${VLESS_PORT:-UNDEF}
VLESS_UUID=${VLESS_UUID:-UNDEF}
VLESS_ALTERID=${VLESS_ALTERID:-UNDEF}
URI_PATH=${URI_PATH:-UNDEF}
VLESS_VHOST=${VLESS_VHOST:-outgoing.org}
WST_URI_PATH=${WST_URI_PATH:-/api/wst/login}
WST_PORT=${WST_PORT:-60999}

[ -z "${CLI_WST_PORT}" ] || cat > v2_cli_wstunnel.sh <<EOF
#!/usr/bin/env bash
#LOG="--log-lvl OFF --no-color 1"
PROXY="--http-proxy http://${PROXY_USER}:${PROXY_PASS}@${PROXY_SRV}:${PROXY_PORT}"
PREFIX=${WST_URI_PATH}
./wstunnel client ${LOG:-} --connection-retry-max-backoff 1s \${PROXY:-} -P \${PREFIX} -L tcp://127.0.0.1:${CLI_WST_PORT}:127.0.0.1:10000 --tls-certificate /etc/wstunnel/ssl/cli.pem --tls-private-key /etc/wstunnel/ssl/cli.key --tls-sni-disable wss://${VLESS_IP}:${VLESS_PORT}
EOF
cat > v2_cli.json <<EOF
{
  "log": { "access": "", "error": "", "loglevel": "debug" },
  "inbounds": [
    { "listen": "127.0.0.1", "port": 8080, "protocol": "http" }
  ],
  "outbounds": [
    {"tag": "direct-out", "protocol": "freedom"},
    {"tag": "block-out", "protocol": "blackhole", "settings": { "response": { "type": "http" } } },
    {"tag": "via-proxy-out", "protocol": "http",
      "settings": { "servers": [ { "address": "${PROXY_SRV}", "port": ${PROXY_PORT}, "users": [ { "user": "${PROXY_USER}", "pass": "${PROXY_PASS}" } ] } ] }
    },
    {"tag": "vless-out", "protocol": "vless",
      /* "proxySettings": { "tag": "via-proxy-out" },  // not worked ws, maybe tcp work */
      /* socat -v -x  TCP-LISTEN:18080,bind=0.0.0.0,reuseaddr,fork TCP:192.168.2.78:8080 */
      "settings": { "vnext": [  "address": "$([ -z "${CLI_WST_PORT}" ] && echo -n ${VLESS_IP} || echo -n 127.0.0.1)", "port": $([ -z "${CLI_WST_PORT}" ] && echo -n ${VLESS_PORT} || echo ${CLI_WST_PORT}),
      "users": [ { "encryption": "none", "id": "${VLESS_UUID}", "alterId": ${VLESS_ALTERID} } ] } ] },
      "streamSettings": { "network": "ws", "security": "tls",
        "tlsSettings": {
          /* "certificates": [ { "certificate": [ ], "key": [ ], "usage": "encipherment" } ], */
          "allowInsecure": true, "disableSystemRoot": true
        },
        "wsSettings": { "headers": { "Host": "${VLESS_VHOST}", "User-Agent": "curl" }, "path": "${URI_PATH}" },
        "sockopt": { "tcpKeepAliveInterval": 5, "tcpKeepAliveIdle": 10 }
      }
    }
  ],
  "dns": {
    "hosts": { "test.com": "127.0.0.1" }
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      /* via-proxy-out tag here work ok */
      {"type": "field", "outboundTag": "block-out",
        "domain": ["domain:taobao.com", "geosite:category-ads-all" ]
      },
      {"type": "field", "outboundTag": "direct-out",
        "domain": [ "domain:baidu.com", "geosite:cn" ]
      },
      {"type": "field", "outboundTag": "direct-out",
        "ip": [ "geoip:private", "geoip:cn" ]
      },
      {"type": "field", "outboundTag": "vless-out",
        "network": "tcp,udp"
      }
    ]
  }
}
EOF
################################################################################
# ./nginx -g 'daemon off;'
# ./v2ray run -config v2_srv.json
cat > v2_srv_wstunnel.service <<EOF
[Unit]
After=network-online.target
[Service]
Type=simple
DynamicUser=true
ExecStart=wstunnel server --restrict-to 127.0.0.1:10000 ws://127.0.0.1:${WST_PORT}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat > v2_srv_ngx.conf <<EOF
server {
    listen ${VLESS_PORT} ssl; default_server reuseport;
    http2 on;
    server_name _;
    ssl_certificate        srv1.pem;
    ssl_certificate_key    srv1.key;
    ssl_client_certificate ca.pem;
    location / { access_log off; default_type text/html; root /var/www/; }
}
server {
    listen ${VLESS_PORT} ssl;
    http2 on;
    server_name ${VLESS_VHOST};
    ssl_certificate        srv1.pem;
    ssl_certificate_key    srv1.key;
    ssl_client_certificate ca.pem;
    # ssl_verify_client on;
    proxy_intercept_errors on;
    error_page 400 495 496 497 = @400;
    location @400 { return 500 "bad request"; }
    location ${WST_URI_PATH} {
        if (\$request_method != "GET") { return 404; }
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${WST_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_buffering off;
    }
    location ${URI_PATH} {
        if (\$request_method != "GET") { return 404; }
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:10000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_buffering off;
    }
}
EOF
cat > v2_srv.json <<EOF
{
  "log": { "access": "", "error": "", "loglevel": "debug" },
  "inbounds": [
    { "listen":"127.0.0.1", "port": 10000, "protocol": "vless",
      "settings": {
        "decryption": "none",
        "clients": [
          { "id": "${VLESS_UUID}", "alterId": ${VLESS_ALTERID} }
        ]
      },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "${URI_PATH}" } }
    }
  ],
  "outbounds": [ { "protocol": "freedom" } ]
}
EOF
