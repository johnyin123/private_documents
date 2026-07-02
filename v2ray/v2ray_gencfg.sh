#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
################################################################################
# https://github.com/UmeLabs/node.umelabs.dev
# V2Ray:https://raw.githubusercontent.com/umelabs/node.umelabs.dev/master/Subscribe/v2ray.md
# geosite/geoip: https://github.com/Loyalsoldier/v2ray-rules-dat/releases
cat <<'EOF'
curl -kv -x http://srv:port http://www
EOF
random() { shuf -i ${1:-1}-${2:-65535} -n ${3:-1}; }
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }
cat <<EOF
CLI_OUT_DIRECT    = ${CLI_OUT_DIRECT:-} #direct output or via wstunnel(yes/no)
VLESS_IP          = ${VLESS_IP:-}
VLESS_PORT        = ${VLESS_PORT:-}
VLESS_UUID        = ${VLESS_UUID:-}
VLESS_ALTERID     = ${VLESS_ALTERID:-}
V2RAY_WSPATH      = ${V2RAY_WSPATH:-}
SRV_WG_PORT       = ${SRV_WG_PORT:-}
##################################################################
EOF
CLI_OUT_DIRECT=${CLI_OUT_DIRECT:?$(log "CLI_OUT_DIRECT no found,(yes/no)")} #direct output/via wstunnel
cli_out_mode_direct() { [ "${CLI_OUT_DIRECT:-x}" == "yes" ]; }

PROXY_SRV=${PROXY_SRV:-}
PROXY_PORT=${PROXY_PORT:-}
PROXY_USER=${PROXY_USER:-UNDEF}
PROXY_PASS=${PROXY_PASS:-UNDEF}

CLI_WST_PORT=${CLI_WST_PORT:-$(random 61000 62000)}
CLI_WST_WG_PORT=${CLI_WST_WG_PORT:-$(random 62000 63000)}

VLESS_VHOST=${VLESS_VHOST:-microsoft.com}
VLESS_IP=${VLESS_IP:?$(log "VLESS_IP no found")}
VLESS_PORT=${VLESS_PORT:?$(log "VLESS_PORT no found")}
VLESS_UUID=${VLESS_UUID:?$(log "VLESS_UUID no found")}
VLESS_ALTERID=${VLESS_ALTERID:?$(log "VLESS_ALTERID no found")}

SRV_WG_PORT=${SRV_WG_PORT:-?$(log "SRV_WG_PORT no found")}

SRV_V2RAY_PORT=${SRV_V2RAY_PORT:-$(random 10000 14000)}
V2RAY_WSPATH=${V2RAY_WSPATH:?$(log "V2RAY_WSPATH no found")}

SRV_WST_PORT=${SRV_WST_PORT:-$(random 60000 61000)}
NGX_WSPATH=${NGX_WSPATH:-/wst${V2RAY_WSPATH}}

SRV_WG_V2RAY_PORT=${SRV_WG_V2RAY_PORT:-$((${SRV_V2RAY_PORT}+1))}
V2RAY_WG_WSPATH=${V2RAY_WG_WSPATH:-/wg${V2RAY_WSPATH}}

SRV_WG_WST_PORT=${SRV_WG_WST_PORT:-$((${SRV_WST_PORT}+1))}
NGX_WG_WSPATH=${NGX_WG_WSPATH:-/wst/wg${V2RAY_WSPATH}}

cat <<EOF
VLESS_VHOST       = ${VLESS_VHOST}
PROXY_SRV         = ${PROXY_SRV}
PROXY_PORT        = ${PROXY_PORT}
PROXY_USER        = ${PROXY_USER}
PROXY_PASS        = ${PROXY_PASS}
CLI_WST_PORT      = ${CLI_WST_PORT}
SRV_WST_PORT      = ${SRV_WST_PORT}
SRV_V2RAY_PORT    = ${SRV_V2RAY_PORT}
CLI_WST_WG_PORT   = ${CLI_WST_WG_PORT}
SRV_WG_V2RAY_PORT = ${SRV_WG_V2RAY_PORT}
SRV_WG_WST_PORT   = ${SRV_WG_WST_PORT}
NGX_WSPATH        = ${NGX_WSPATH}
NGX_WG_WSPATH     = ${NGX_WG_WSPATH}
V2RAY_WG_WSPATH   = ${V2RAY_WG_WSPATH}
EOF
read -n 1 -p "Press any key continue ..." value

gen_wst_script() {
    cat > v2_cli_wstunnel.sh <<EOF
#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="\$(readlink -f "\$(dirname "\$0")")"

LOG="--log-lvl OFF --no-color 1"
# TLS="--tls-certificate /etc/wstunnel/ssl/cli.pem --tls-private-key /etc/wstunnel/ssl/cli.key"
# PROXY="--http-proxy http://USER:PASS@SRV:PORT"

# # http
PREFIX="${NGX_WSPATH}"
systemd-run --unit wst-srv \\
./wstunnel client \${LOG:-} --connection-retry-max-backoff 1s \${PROXY:-} --http-upgrade-path-prefix \${PREFIX} --local-to-remote tcp://127.0.0.1:${CLI_WST_PORT}:127.0.0.1:${SRV_V2RAY_PORT} --http-headers "Host: ${VLESS_VHOST}" \${TLS:-} wss://${VLESS_IP}:${VLESS_PORT}

# # udp
PREFIX=${NGX_WG_WSPATH}
systemd-run --unit wstwg-srv \\
./wstunnel client \${LOG:-} --connection-retry-max-backoff 1s \${PROXY:-} --http-upgrade-path-prefix \${PREFIX} --local-to-remote tcp://127.0.0.1:${CLI_WST_WG_PORT}:127.0.0.1:${SRV_WG_V2RAY_PORT} --http-headers "Host: ${VLESS_VHOST}" \${TLS:-} wss://${VLESS_IP}:${VLESS_PORT}

systemd-run --working-directory=\${DIRNAME} --unit v2ray-cli \\
./v2ray run -c v2_cli.json

cat <<EODOC
systemctl stop wst-srv.service
systemctl stop wstwg-srv.service
systemctl stop v2ray-cli.service
systemctl reset-failed
EODOC
EOF
}
# "tlsSettings":{
#   /*"certificates":[{"certificateFile":"cert.pem","keyFile":"cert.key","usage":"encipherment"}],*/
#   /*"certificates":[{"certificate":[],"key":[],"usage":"encipherment"}],*/
#   "fingerprint":"chrome","allowInsecure":true,"disableSystemRoot":true
# },
gen_outbound() {
    local local_port=${1}
    local wspath=${2}
    local local_ip="127.0.0.1"
    cli_out_mode_direct && {
        cat <<EOF
      /*"settings":{"vnext":[{"address":"${local_ip}","port":${local_port},"users":[{"encryption":"none","id":"${VLESS_UUID}","alterId":${VLESS_ALTERID}}]}]},*/
EOF
        local_ip=${VLESS_IP}
        local_port=${VLESS_PORT}
    } || {
        cat <<EOF
      /*"settings":{"vnext":[{"address":"${VLESS_IP}","port":${VLESS_PORT},"users":[{"encryption":"none","id":"${VLESS_UUID}","alterId":${VLESS_ALTERID}}]}]},*/
EOF
    }
    gen_wst_script
    cat <<EOF
      "settings":{"vnext":[{"address":"${local_ip}","port":${local_port},"users":[{"encryption":"none","id":"${VLESS_UUID}","alterId":${VLESS_ALTERID}}]}]},
      "mux": { "enabled": true },
      "streamSettings":{"network":"ws",
        "security":"tls","tlsSettings":{"fingerprint":"chrome","allowInsecure":true,"disableSystemRoot":true},
        "wsSettings":{"headers":{"Host":"${VLESS_VHOST}","User-Agent":"curl"},"path":"${wspath}"},
        "sockopt":{"tcpKeepAliveInterval":5,"tcpKeepAliveIdle":10}
      }
EOF
}

cat > v2_cli.json <<EOF
{
  "log":{"access":"","error":"","loglevel":"debug"},
  "inbounds":[
    {"tag":"cli-in-http","listen":"127.0.0.1","port":8080,"protocol":"http"},
    {"tag":"cli-in-udp","listen":"127.0.0.1","port":${SRV_WG_PORT},"protocol":"dokodemo-door","settings":{"address":"127.0.0.1","port":${SRV_WG_PORT},"network":"udp"}}
  ],
  "outbounds":[
    {"tag":"direct-out","protocol":"freedom"},
    {"tag":"block-out","protocol":"blackhole","settings":{"response":{"type":"http"}}},
    $([ -z "${PROXY_SRV}" ] && echo -n "/*"){"tag":"via-proxy-out","protocol":"http","settings":{"servers":[{"address":"${PROXY_SRV}","port":${PROXY_PORT},"users":[{"user":"${PROXY_USER}","pass":"${PROXY_PASS}"}]}]}},$([ -z "${PROXY_SRV}" ] && echo -n "*/")
    {"tag":"vless-out","protocol":"vless",
      /* "proxySettings":{"tag":"via-proxy-out"},// not worked ws,maybe tcp work */
$(gen_outbound ${CLI_WST_PORT} ${V2RAY_WSPATH})
    },
    {"tag":"vless-out-udp","protocol":"vless",
$(gen_outbound ${CLI_WST_WG_PORT} ${V2RAY_WG_WSPATH})
    }
  ],
  "dns":{
    "hosts":{"test.com":"127.0.0.1"}
  },
  "routing":{
    "domainStrategy":"IPIfNonMatch",
    "rules":[
      /* via-proxy-out tag here work ok */
      {"type":"field","inboundTag":["cli-in-udp"],"outboundTag":"vless-out-udp"},
      {"type":"field","outboundTag":"block-out",
        "domain":["domain:taobao.com","geosite:category-ads-all"]
      },
      {"type":"field","outboundTag":"direct-out",
        "domain":["domain:baidu.com","geosite:cn"]
      },
      {"type":"field","outboundTag":"direct-out",
        "ip":["geoip:private","geoip:cn"]
      },
      {"type":"field","outboundTag":"vless-out",
        "network":"tcp,udp"
      }
    ]
  }
}
EOF
################################################################################
# ./nginx -g 'daemon off;'
# ./v2ray run -config v2_srv.json
cat > v2_srv_wstunnel.sh <<'EOF'
#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"

systemd-run --working-directory=${DIRNAME} --unit ngx-srv ${DIRNAME}/nginx -g 'daemon off;'
systemd-run --working-directory=${DIRNAME} --unit v2ray-srv ${DIRNAME}/v2ray run -c ${DIRNAME}/v2_srv.json
EOF
cat >> v2_srv_wstunnel.sh <<EOF
systemd-run --unit wst-srv \${DIRNAME}/wstunnel server --restrict-to 127.0.0.1:${SRV_V2RAY_PORT} wss://127.0.0.1:${SRV_WST_PORT}
systemd-run --unit wstwg-srv \${DIRNAME}/wstunnel server --restrict-to 127.0.0.1:${SRV_WG_V2RAY_PORT} wss://127.0.0.1:${SRV_WG_WST_PORT}
# systemctl stop wst-srv.service
# systemctl stop wstwg-srv.service
# systemctl stop v2ray-srv.service
# systemctl stop ngx-srv.service
# systemctl reset-failed
EOF

cat > v2_srv_wstunnel@.service <<EOF
# systemctl enable v2_srv_wstunnel@\$(systemd-escape --path /mydir/myray/)
[Unit]
After=network.target
[Service]
Type=oneshot
# DynamicUser=true
RemainAfterExit=yes
WorkingDirectory=/%I
ExecStart=/bin/sh -c "./nginx"
ExecStart=/bin/sh -c "./v2ray run -c v2_srv.json &"
ExecStart=/bin/sh -c "./wstunnel server --restrict-to 127.0.0.1:${SRV_V2RAY_PORT} wss://127.0.0.1:${SRV_WST_PORT} &"
ExecStart=/bin/sh -c "./wstunnel server --restrict-to 127.0.0.1:${SRV_WG_V2RAY_PORT} wss://127.0.0.1:${SRV_WG_WST_PORT} &"
[Install]
WantedBy=multi-user.target
EOF

cat > v2_srv_ngx.http <<EOF
server {
    listen 443 ssl default_server reuseport;
    listen ${VLESS_PORT} ssl default_server reuseport;
    http2 on;
    server_name _;
    ssl_certificate        ssl/ngxsrv.pem;
    ssl_certificate_key    ssl/ngxsrv.key;
    location / { access_log off; return 301 https://${VLESS_VHOST}; }
}
server {
    listen 443 ssl;
    listen ${VLESS_PORT} ssl;
    http2 on;
    server_name ${VLESS_VHOST};
    ssl_certificate        ssl/ngxsrv.pem;
    ssl_certificate_key    ssl/ngxsrv.key;
    access_log logs/ray.log;
    # ssl_client_certificate ssl/ngx_verifyclient_ca.pem;
    # ssl_verify_client on;
    proxy_intercept_errors on;
    error_page 400 495 496 497 = @400;
    location @400 { return 500 "bad request"; }
    location / { keepalive_timeout 0; return 444; }
    # # connect via wstunnel ################################
    location ${NGX_WSPATH} {
        if (\$request_method != "GET") { return 404; }
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_redirect off;
        proxy_pass https://127.0.0.1:${SRV_WST_PORT};
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
    location ${NGX_WG_WSPATH} {
        if (\$request_method != "GET") { return 404; }
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_redirect off;
        proxy_pass https://127.0.0.1:${SRV_WG_WST_PORT};
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
    location ${V2RAY_WSPATH} {
        if (\$request_method != "GET") { return 404; }
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_redirect off;
        proxy_pass https://127.0.0.1:${SRV_V2RAY_PORT};
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
    location ${V2RAY_WG_WSPATH} {
        if (\$request_method != "GET") { return 404; }
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_redirect off;
        proxy_pass https://127.0.0.1:${SRV_WG_V2RAY_PORT};
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
get_tls() {
    local fn=${1}
    local prefix=${2}
    jq -nR '[inputs]' "${fn}" | sed "2,$ s/^/${prefix}/"
}
openssl genpkey -algorithm ed25519 -out v2_srv.key
# openssl genrsa -out v2_srv.key 2048
openssl req -new -x509 -days 1460 -key v2_srv.key -out v2_srv.pem -utf8 -subj "/C=US/L=LN/O=jyca/CN=updater"
cat > v2_srv.json <<EOF
{
  "log":{"access":"","error":"","loglevel":"debug"},
  "inbounds":[
    {"tag":"srv-in-all","listen":"127.0.0.1","port":${SRV_V2RAY_PORT},"protocol":"vless",
      "settings":{"decryption":"none","clients":[{"id":"${VLESS_UUID}","alterId":${VLESS_ALTERID}}]},
      "streamSettings":{"network":"ws","wsSettings":{"path":"${V2RAY_WSPATH}"},
        "security":"tls","tlsSettings":{
          "disableSystemRoot":true,
          "certificates":[{
            "key":$(get_tls "v2_srv.key" "            "),
            "certificate":$(get_tls "v2_srv.pem" "            "),
            "usage":"encipherment"
          }]
        }
      }
    },
    {"tag":"srv-in-udp","listen":"127.0.0.1","port":${SRV_WG_V2RAY_PORT},"protocol":"vless",
      "settings":{"decryption":"none","clients":[{"id":"${VLESS_UUID}","alterId":${VLESS_ALTERID}}]},
      "streamSettings":{"network":"ws","wsSettings":{"path":"${V2RAY_WG_WSPATH}"},
        "security":"tls","tlsSettings":{
          "disableSystemRoot":true,
          "certificates":[{
            "key":$(get_tls "v2_srv.key" "            "),
            "certificate":$(get_tls "v2_srv.pem" "            "),
            "usage":"encipherment"
          }]
        }
      }
    }
  ],
  "outbounds":[
    {"tag":"srv_out_all","protocol":"freedom"},
    {"tag":"srv_out_udp","protocol":"freedom","settings":{"redirect":"127.0.0.1:${SRV_WG_PORT}"}}
  ],
  "routing":{
    "rules":[
      {"type":"field","inboundTag":["srv-in-all"],"outboundTag":"srv_out_all"},
      {"type":"field","inboundTag":["srv-in-udp"],"outboundTag":"srv_out_udp"}
    ]
  }
}
EOF
