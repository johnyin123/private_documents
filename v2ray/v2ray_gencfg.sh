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
PROXY_SRV=${PROXY_SRV:-UNDEF}
PROXY_PORT=${PROXY_PORT:-UNDEF}
PROXY_USER=${PROXY_USER:-UNDEF}
PROXY_PASS=${PROXY_PASS:-UNDEF}
VLESS_IP=${VLESS_IP:-UNDEF}
VLESS_PORT=${VLESS_PORT:-UNDEF}
VLESS_UUID=${VLESS_UUID:-UNDEF}
VLESS_ALTERID=${VLESS_ALTERID:-UNDEF}
URI_PATH=${URI_PATH:-UNDEF}
cat > proxy.json <<EOF
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
      /* "proxySettings": { "tag": "via-proxy-out" }, */
      "settings": { "vnext": [ { "address": "${VLESS_IP}", "port": ${VLESS_PORT}, "users": [ { "encryption": "none", "id": "${VLESS_UUID}", "alterId": ${VLESS_ALTERID} } ] } ] },
      "streamSettings": { "network": "ws", "security": "tls",
        "tlsSettings": {
          /* "certificates": [ { "certificate": [ ], "key": [ ], "usage": "encipherment" } ], */
          "allowInsecure": true, "disableSystemRoot": true
        },
        "wsSettings": { /*"headers": { "Host": "dom.com", "User-Agent": "curl" }, */"path": "${URI_PATH}" },
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
