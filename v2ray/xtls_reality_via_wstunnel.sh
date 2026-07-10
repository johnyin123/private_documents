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
randstr() {
    local size=${1:-8}
    tr </dev/urandom -dc A-Za-z0-9 | head -c ${size} || true
}
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }
cat <<EOF
NGX_IP            = ${NGX_IP:-}
NGX_PORT          = ${NGX_PORT:-}
VLESS_UUID        = ${VLESS_UUID:-}     # cat /proc/sys/kernel/random/uuid
VLESS_SHORTID     = ${VLESS_SHORTID:-}  # openssl rand -hex 8
SRV_WG_PORT       = ${SRV_WG_PORT:-}
##################################################################
EOF

PROXY_SRV=${PROXY_SRV:-}
PROXY_PORT=${PROXY_PORT:-8080}
PROXY_USER=${PROXY_USER:-UNDEF}
PROXY_PASS=${PROXY_PASS:-UNDEF}

CLI_WST_PORT=${CLI_WST_PORT:-$(random 61000 62000)}
CLI_WST_WG_PORT=${CLI_WST_WG_PORT:-$(random 62000 63000)}

NGX_IP=${NGX_IP:?$(log "NGX_IP no found")}
NGX_PORT=${NGX_PORT:?$(log "NGX_PORT no found")}
VLESS_VHOST=${VLESS_VHOST:-microsoft.com}
VLESS_UUID=${VLESS_UUID:?$(log "VLESS_UUID no found")}
VLESS_SHORTID=${VLESS_SHORTID:?$(log "VLESS_SHORTID no found")}
NGX_VHOST=${NGX_VHOST:-${VLESS_VHOST}}

SRV_WG_PORT=${SRV_WG_PORT:-?$(log "SRV_WG_PORT no found")}

SRV_V2RAY_PORT=${SRV_V2RAY_PORT:-$(random 10000 14000)}

SRV_WST_PORT=${SRV_WST_PORT:-$(random 60000 61000)}
NGX_WSPATH=${NGX_WSPATH:-/wstun/$(randstr 12)}

SRV_WG_V2RAY_PORT=${SRV_WG_V2RAY_PORT:-$((${SRV_V2RAY_PORT}+1))}


PRIV_KEY=${PRIV_KEY:-}
PUB_KEY=${PUB_KEY:-}

[ -z "${PRIV_KEY}" ] && {
    # Generate X25519 Keys via OpenSSL and convert to base64url
    openssl genpkey -algorithm X25519 -out priv.pem 2>/dev/null
    openssl pkey -in priv.pem -pubout -out pub.pem 2>/dev/null
    PRIV_KEY=$(openssl pkey -in priv.pem -outform DER 2>/dev/null | tail -c 32 | base64 | tr '+/' '-_' | tr -d '=')
    PUB_KEY=$(openssl pkey -in pub.pem -pubin -outform DER 2>/dev/null | tail -c 32 | base64 | tr '+/' '-_' | tr -d '=')
    rm -f priv.pem pub.pem
}
cat <<EOF
PRIV_KEY          = ${PRIV_KEY}
PUB_KEY           = ${PUB_KEY}
VLESS_VHOST       = ${VLESS_VHOST}
NGX_VHOST         = ${NGX_VHOST}
NGX_WSPATH        = ${NGX_WSPATH}
PROXY_SRV         = ${PROXY_SRV}
PROXY_PORT        = ${PROXY_PORT}
PROXY_USER        = ${PROXY_USER}
PROXY_PASS        = ${PROXY_PASS}
CLI_WST_PORT      = ${CLI_WST_PORT}
SRV_WST_PORT      = ${SRV_WST_PORT}
SRV_V2RAY_PORT    = ${SRV_V2RAY_PORT}
CLI_WST_WG_PORT   = ${CLI_WST_WG_PORT}
SRV_WG_V2RAY_PORT = ${SRV_WG_V2RAY_PORT}
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
# NS_NAME=

# # cloudflared tunnel --no-tls-verify --url https://localhost
# # --http-headers "Host:xxxxxxxxxxxxx.trycloudflare.com" wss://xxxxxxxxxxxxx.trycloudflare.com
# # http/udp
PREFIX="${NGX_WSPATH}"
PREFIX="\${PREFIX/#\//}" # remove first /
systemd-run --unit wst-srv \${NS_NAME:+-p NetworkNamespacePath=/run/netns/\${NS_NAME}} \\
\${DIRNAME}/wstunnel client \${LOG:-} --connection-retry-max-backoff 1s \${PROXY:-} --http-upgrade-path-prefix \${PREFIX} --http-headers "Host: ${NGX_VHOST}" \${TLS:-} 
--local-to-remote tcp://127.0.0.1:${CLI_WST_PORT}:127.0.0.1:${SRV_V2RAY_PORT} \\
--local-to-remote tcp://127.0.0.1:${CLI_WST_WG_PORT}:127.0.0.1:${SRV_WG_V2RAY_PORT} \\
wss://${NGX_IP}:${NGX_PORT}

systemd-run --working-directory=\${DIRNAME} --unit v2ray-cli \${NS_NAME:+-p NetworkNamespacePath=/run/netns/\${NS_NAME}} \\
\${DIRNAME}/v2ray run -c v2_cli.json

cat <<EODOC
systemctl stop wst-srv.service
systemctl stop v2ray-cli.service
systemctl reset-failed
EODOC
EOF
}
gen_outbound() {
    local local_port=${1}
    local local_ip="127.0.0.1"
    gen_wst_script
    cat <<EOF
      "mux":{"enabled":true},
      "settings":{"vnext":[{"address":"${local_ip}","port":${local_port},"users":[{"encryption":"none","id":"${VLESS_UUID}","flow":"xtls-rprx-vision"}]}]},
      "streamSettings":{"network":"tcp","security":"reality",
        "realitySettings":{"show":false,"serverName":"://${VLESS_VHOST}","fingerprint":"chrome","publicKey":"${PUB_KEY}","shortId":"${VLESS_SHORTID}"}
      },
      "sockopt":{"tcpUserTimeout":10000,"tcpKeepAliveIdle":45,"tcpKeepAliveInterval":45,"tcpFastOpen":true}
EOF
}

cat > v2_cli.json <<EOF
{
  "log":{"access":"","error":"","loglevel":"debug"},
  "inbounds":[
    {"tag":"cli-in-http","listen":"127.0.0.1","port":8080,"protocol":"http","sniffing":{"enabled":true,"destOverride":["http","tls","quic"]}},
    {"tag":"cli-in-udp","listen":"127.0.0.1","port":${SRV_WG_PORT},"protocol":"dokodemo-door","settings":{"address":"127.0.0.1","port":${SRV_WG_PORT},"network":"udp"}}
  ],
  "outbounds":[
    {"tag":"direct-out","protocol":"freedom","mux":{"enabled":true}},
    {"tag":"block-out","protocol":"blackhole","settings":{"response":{"type":"http"}}},
    $([ -z "${PROXY_SRV}" ] && echo -n "/*"){"tag":"via-proxy-out","protocol":"http","settings":{"servers":[{"address":"${PROXY_SRV}","port":${PROXY_PORT},"users":[{"user":"${PROXY_USER}","pass":"${PROXY_PASS}"}]}]}},$([ -z "${PROXY_SRV}" ] && echo -n "*/")
    {"tag":"vless-out","protocol":"vless",
      /* "proxySettings":{"tag":"via-proxy-out"},// not worked ws,maybe tcp work */
$(gen_outbound ${CLI_WST_PORT})
    },
    {"tag":"vless-out-udp","protocol":"vless",
$(gen_outbound ${CLI_WST_WG_PORT})
    }
  ],
  "dns":{
    "hosts":{"test.com":"127.0.0.1"},
    "queryStrategy": "UseIPv4",
    "servers":[
      {"address":"223.5.5.5","domains":["geosite:cn"]},
      {"address":"https://1.1.1.1/dns-query","domains":["geosite:geolocation-!cn"]},
      "localhost"
    ]
  },
  "routing":{
    "domainStrategy":"IPIfNonMatch",
    "rules":[
      /* via-proxy-out tag here work ok */
      {"type":"field","inboundTag":["cli-in-udp"],"outboundTag":"vless-out-udp"},
      {"type":"field","outboundTag":"block-out",
        "domain":["domain:aria2e.com","geosite:category-ads-all"]
      },
      {"type":"field","outboundTag":"direct-out",
        "ip":["geoip:private","geoip:cn"]
      },
      {"type":"field","outboundTag":"direct-out",
        "domain":["domain:baidu.com","geosite:cn"]
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
cat > v2_srv_wstunnel.sh <<EOF
#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="\$(readlink -f "\$(dirname "\$0")")"

systemd-run --working-directory=\${DIRNAME} --unit ngx-srv \${DIRNAME}/nginx -g 'daemon off;'
systemd-run --working-directory=\${DIRNAME} --unit ray-srv \${DIRNAME}/v2ray run -c \${DIRNAME}/v2_srv.json
systemd-run --unit wst-srv \${DIRNAME}/wstunnel server \\
    --restrict-to 127.0.0.1:${SRV_V2RAY_PORT} \\
    --restrict-to 127.0.0.1:${SRV_WG_V2RAY_PORT} \\
    wss://127.0.0.1:${SRV_WST_PORT}
cat <<EODOC
systemctl stop ngx-srv.service
systemctl stop wst-srv.service
systemctl stop ray-srv.service
systemctl reset-failed
EODOC
EOF

cat > v2_srv_wstunnel@.service <<EOF
# systemctl enable v2_srv_wstunnel@\$(systemd-escape --path /mydir/myray/)
[Unit]
After=network.target
[Service]
LimitNOFILE=65536
Type=oneshot
# DynamicUser=true
RemainAfterExit=yes
WorkingDirectory=/%I
ExecStart=/bin/sh -c "./nginx"
ExecStart=/bin/sh -c "./v2ray run -c v2_srv.json &"
ExecStart=/bin/sh -c "./wstunnel server --restrict-to 127.0.0.1:${SRV_V2RAY_PORT} --restrict-to 127.0.0.1:${SRV_WG_V2RAY_PORT} wss://127.0.0.1:${SRV_WST_PORT} &"
[Install]
WantedBy=multi-user.target
EOF

cat > v2_srv_ngx.http <<EOF
server {
    listen 443 ssl default_server reuseport;
    listen ${NGX_PORT} ssl default_server reuseport;
    http2 on;
    server_name _;
    ssl_certificate        ssl/ngxsrv.pem;
    ssl_certificate_key    ssl/ngxsrv.key;
    location / { keepalive_timeout 0; access_log off; return 301 https://${NGX_VHOST}; }
}
upstream api_srvs {
    server 127.0.0.1:${SRV_WST_PORT};
    keepalive 32;
}
server {
    listen 443 ssl;
    listen ${NGX_PORT} ssl;
    http2 on;
    server_name *.trycloudflare.com ${NGX_VHOST};
    ssl_certificate        ssl/ngxsrv.pem;
    ssl_certificate_key    ssl/ngxsrv.key;
    # ssl_client_certificate ssl/ngx_verifyclient_ca.pem;
    # ssl_verify_client on;
    access_log logs/ray.log;
    proxy_intercept_errors on;
    location / { keepalive_timeout 0; return 444; }
    # # connect via wstunnel ################################
    location ${NGX_WSPATH} {
        if (\$request_method != "GET") { return 404; }
        if (\$http_upgrade != "websocket") { return 404; }
        proxy_redirect off;
        proxy_pass https://api_srvs;
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
  "log":{"access":"","error":"","loglevel":"debug"},
  "inbounds":[
    {"tag":"srv-in-all","listen":"127.0.0.1","port":${SRV_V2RAY_PORT},"protocol":"vless",
      "settings":{"decryption":"none","clients":[{"id":"${VLESS_UUID}","flow":"xtls-rprx-vision"}]},
      "streamSettings":{"network":"tcp","security":"reality",
        "realitySettings":{"show":false,"dest":"://${VLESS_VHOST}","xver":0,"privateKey":"${PRIV_KEY}","shortIds":["${VLESS_SHORTID}"]}
      } 
    },
    {"tag":"srv-in-udp","listen":"127.0.0.1","port":${SRV_WG_V2RAY_PORT},"protocol":"vless",
      "settings":{"decryption":"none","clients":[{"id":"${VLESS_UUID}","flow":"xtls-rprx-vision"}]},
      "streamSettings":{"network":"tcp","security":"reality",
        "realitySettings":{"show":false,"dest":"://${VLESS_VHOST}","xver":0,"privateKey":"${PRIV_KEY}","shortIds":["${VLESS_SHORTID}"]}
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
