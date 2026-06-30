#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
################################################################################
# https://github.com/UmeLabs/node.umelabs.dev
# V2Ray:https://raw.githubusercontent.com/umelabs/node.umelabs.dev/master/Subscribe/v2ray.md
# geosite/geoip: https://github.com/Loyalsoldier/v2ray-rules-dat/releases
cat <<'EOF'
curl -kv -x http://srv:port http://www
EOF
CLI_WST_PORT=${CLI_WST_PORT:-60888}
CLI_WST_WG_PORT=$((${CLI_WST_PORT}+1))

PROXY_SRV=${PROXY_SRV:-UNDEF}
PROXY_PORT=${PROXY_PORT:-UNDEF}
PROXY_USER=${PROXY_USER:-UNDEF}
PROXY_PASS=${PROXY_PASS:-UNDEF}

VLESS_IP=${VLESS_IP:-UNDEF}
VLESS_PORT=${VLESS_PORT:-UNDEF}
VLESS_UUID=${VLESS_UUID:-UNDEF}
VLESS_ALTERID=${VLESS_ALTERID:-UNDEF}
VLESS_VHOST=${VLESS_VHOST:-outgoing.org}

SRV_WG_PORT=${SRV_WG_PORT:-65454}

SRV_V2RAY_PORT=${SRV_V2RAY_PORT:-10000}
SRV_URI_PATH=${SRV_URI_PATH:-UNDEF}

SRV_WST_PORT=${SRV_WST_PORT:-60999}
SRV_WST_URI_PATH=/wstsvc${SRV_URI_PATH}

SRV_WG_V2RAY_PORT=$((${SRV_V2RAY_PORT}+2))
SRV_WG_URI_PATH=/wgsvc${SRV_URI_PATH}

SRV_WST_WG_PORT=$((${SRV_WST_PORT}+1))
SRV_WST_WG_URI_PATH=/wstwgsvc${SRV_URI_PATH}

cat <<EOF
CLI_WST_PORT     =${CLI_WST_PORT}
PROXY_SRV        =${PROXY_SRV}
PROXY_PORT       =${PROXY_PORT}
PROXY_USER       =${PROXY_USER}
PROXY_PASS       =${PROXY_PASS}
VLESS_IP         =${VLESS_IP}
VLESS_PORT       =${VLESS_PORT}
VLESS_UUID       =${VLESS_UUID}
VLESS_ALTERID    =${VLESS_ALTERID}
SRV_URI_PATH     =${SRV_URI_PATH}
VLESS_VHOST      =${VLESS_VHOST}
SRV_WST_PORT     =${SRV_WST_PORT}
SRV_V2RAY_PORT   =${SRV_V2RAY_PORT}
SRV_WG_PORT      =${SRV_WG_PORT}
EOF
read -n 1 -p "Press any key continue ..." value

cat > v2_cli_wstunnel.sh <<EOF
#!/usr/bin/env bash
LOG="--log-lvl OFF --no-color 1"
# TLS="--tls-certificate /etc/wstunnel/ssl/cli.pem --tls-private-key /etc/wstunnel/ssl/cli.key"
# PROXY="--http-proxy http://${PROXY_USER}:${PROXY_PASS}@${PROXY_SRV}:${PROXY_PORT}"
# # http
# systemd-run --unit wst-srv
PREFIX="${SRV_WST_URI_PATH}"
./wstunnel client \${LOG:-} --connection-retry-max-backoff 1s \${PROXY:-} --http-upgrade-path-prefix \${PREFIX} --local-to-remote tcp://127.0.0.1:${CLI_WST_PORT}:127.0.0.1:${SRV_V2RAY_PORT} --http-headers "Host: ${VLESS_VHOST}" \${TLS:-} wss://${VLESS_IP}:${VLESS_PORT}
# # udp
# systemd-run --unit wst-srv
PREFIX=${SRV_WST_WG_URI_PATH}
./wstunnel client \${LOG:-} --connection-retry-max-backoff 1s \${PROXY:-} --http-upgrade-path-prefix \${PREFIX} --local-to-remote tcp://127.0.0.1:${CLI_WST_WG_PORT}:127.0.0.1:${SRV_WG_V2RAY_PORT} --http-headers "Host: ${VLESS_VHOST}" \${TLS:-} wss://${VLESS_IP}:${VLESS_PORT}
EOF

cat > v2_cli.json <<EOF
{
  "log": {"access": "", "error": "", "loglevel": "debug"},
  "inbounds": [
    {"tag":"cli-in-http", "listen": "127.0.0.1", "port": 8080, "protocol": "http"},
    {"tag":"cli-in-udp", "listen": "127.0.0.1", "port": ${SRV_WG_PORT}, "protocol": "dokodemo-door", "settings": { "address": "127.0.0.1", "port": ${SRV_WG_PORT}, "network": "udp" }}
  ],
  "outbounds": [
    {"tag": "direct-out", "protocol": "freedom"},
    {"tag": "block-out", "protocol": "blackhole", "settings": { "response": { "type": "http" } } },
    {"tag": "via-proxy-out", "protocol": "http", "settings": { "servers": [ { "address": "${PROXY_SRV}", "port": ${PROXY_PORT}, "users": [ { "user": "${PROXY_USER}", "pass": "${PROXY_PASS}" } ] } ] } },
    {"tag": "vless-out", "protocol": "vless",
      /* "proxySettings": { "tag": "via-proxy-out" },  // not worked ws, maybe tcp work */
      /* socat -v -x  TCP-LISTEN:18080,bind=0.0.0.0,reuseaddr,fork TCP:192.168.2.78:8080 */
      "settings": { "vnext": [ { /* "address": "127.0.0.1", "port": ${CLI_WST_PORT}, */"address": "${VLESS_IP}", "port": ${VLESS_PORT}, "users": [ { "encryption": "none", "id": "${VLESS_UUID}", "alterId": ${VLESS_ALTERID} } ] } ] },
      "streamSettings": { "network": "ws", "security": "tls",
        "tlsSettings": {
          /* "certificates": [ { "certificate": [ ], "key": [ ], "usage": "encipherment" } ], */
          "fingerprint": "chrome", "allowInsecure": true, "disableSystemRoot": true
        },
        "wsSettings": { "headers": { "Host": "${VLESS_VHOST}", "User-Agent": "curl" }, "path": "${SRV_URI_PATH}" },
        "sockopt": { "tcpKeepAliveInterval": 5, "tcpKeepAliveIdle": 10 }
      }
    },
    {"tag": "vless-out-udp", "protocol": "vless",
      "settings": { "vnext": [ { /* "address": "127.0.0.1", "port": ${CLI_WST_PORT}, */"address": "${VLESS_IP}", "port": ${VLESS_PORT}, "users": [ { "encryption": "none", "id": "${VLESS_UUID}", "alterId": ${VLESS_ALTERID} } ] } ] },
      "streamSettings": { "network": "ws", "security": "tls",
        "tlsSettings": {
          "fingerprint": "chrome", "allowInsecure": true, "disableSystemRoot": true
        },
        "wsSettings": { "headers": { "Host": "${VLESS_VHOST}", "User-Agent": "curl" }, "path": "${SRV_WG_URI_PATH}" },
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
      {"type": "field", "inboundTag": ["cli-in-udp"], "outboundTag": "vless-out-udp" },
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
cat > v2_srv_wg_wstunnel.service <<EOF
[Unit]
After=network-online.target
[Service]
Type=simple
DynamicUser=true
ExecStart=wstunnel server --restrict-to 127.0.0.1:${SRV_WG_V2RAY_PORT} ws://127.0.0.1:${SRV_WST_WG_PORT};
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat > v2_srv_wstunnel.service <<EOF
[Unit]
After=network-online.target
[Service]
Type=simple
DynamicUser=true
ExecStart=wstunnel server --restrict-to 127.0.0.1:${SRV_V2RAY_PORT} ws://127.0.0.1:${SRV_WST_PORT}
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

cat > v2_srv_ngx.http <<EOF
server {
    listen ${VLESS_PORT} ssl; # default_server reuseport;
    http2 on;
    server_name _;
    ssl_certificate        ssl/ngxsrv.pem;
    ssl_certificate_key    ssl/ngxsrv.key;
    location / { access_log off; default_type text/html; root /var/www/; }
}
server {
    listen ${VLESS_PORT} ssl;
    http2 on;
    server_name ${VLESS_VHOST};
    ssl_certificate        ssl/ngxsrv.pem;
    ssl_certificate_key    ssl/ngxsrv.key;
    ssl_client_certificate ssl/ngx_verifyclient_ca.pem;
    access_log logs/ray.log;
    # ssl_verify_client on;
    proxy_intercept_errors on;
    error_page 400 495 496 497 = @400;
    location @400 { return 500 "bad request"; }
    # # connect via wstunnel ################################
    location ${SRV_WST_URI_PATH} {
        if (\$request_method != "GET") { return 404; }
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${SRV_WST_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_buffering off;
        proxy_read_timeout 90m;
        proxy_send_timeout 90m;
    }
    location ${SRV_WST_WG_URI_PATH} {
        if (\$request_method != "GET") { return 404; }
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${SRV_WST_WG_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_buffering off;
        proxy_read_timeout 90m;
        proxy_send_timeout 90m;
    }
    # # direct connect ################################
    location ${SRV_URI_PATH} {
        if (\$request_method != "GET") { return 404; }
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${SRV_V2RAY_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_buffering off;
        proxy_read_timeout 90m;
        proxy_send_timeout 90m;
    }
    location ${SRV_WG_URI_PATH} {
        if (\$request_method != "GET") { return 404; }
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_redirect off;
        proxy_pass http://127.0.0.1:${SRV_WG_V2RAY_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_buffering off;
        proxy_read_timeout 90m;
        proxy_send_timeout 90m;
    }
}
EOF
cat > v2_srv.json <<EOF
{
  "log": {"access": "", "error": "", "loglevel": "debug"},
  "inbounds": [
    {"tag": "srv-in-all", "listen":"127.0.0.1", "port": ${SRV_V2RAY_PORT}, "protocol": "vless",
      "settings": { "decryption": "none", "clients": [ { "id": "${VLESS_UUID}", "alterId": ${VLESS_ALTERID} } ] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "${SRV_URI_PATH}" }}},
    {"tag": "srv-in-udp", "listen":"127.0.0.1", "port": ${SRV_WG_V2RAY_PORT}, "protocol": "vless",
      "settings": { "decryption": "none", "clients": [ { "id": "${VLESS_UUID}", "alterId": ${VLESS_ALTERID} } ] },
      "streamSettings": { "network": "ws", "wsSettings": { "path": "${SRV_WG_URI_PATH}" }}}
  ],
  "outbounds": [
    {"tag": "srv_out_all", "protocol": "freedom"},
    {"tag": "srv_out_udp", "protocol": "freedom", "settings": { "redirect": "127.0.0.1:${SRV_WG_PORT}" }}
  ],
  "routing": {
    "rules": [
      {"type": "field", "inboundTag": ["srv-in-all"], "outboundTag": "srv_out_all"},
      {"type": "field", "inboundTag": ["srv-in-udp"], "outboundTag": "srv_out_udp"}
    ]
  }
}
EOF
