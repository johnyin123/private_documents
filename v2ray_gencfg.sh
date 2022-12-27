#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("d039079[2022-12-26T08:15:54+08:00]:v2ray_gencfg.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
# https://github.com/UmeLabs/node.umelabs.dev
# V2Ray:https://raw.githubusercontent.com/umelabs/node.umelabs.dev/master/Subscribe/v2ray.md
cat > http_proxy.json <<EOF
{
  "log": {
    "access": "access.log",
    "error": "error.log",
    "loglevel": "info"
  },
  "inbounds": [
    {
      "tag": "http-in",
      "port": 8080,
      "listen": "127.0.0.1",
      "protocol": "http"
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
cat > via_proxy.json <<EOF
{
  "log": {
    "access": "access.log",
    "error": "error.log",
    "loglevel": "info"
  },
  "inbounds": [
    {
      "tag": "http-in",
      "port": 58891,
      "listen": "127.0.0.1",
      "protocol": "http"
    }
  ],
  "outbounds": [
    {
      "protocol": "vmess",
      "settings": {
        "vnext": [
          {
            "address": "172.67.116.211",
            "port": 443,
            "users": [
              {
                "id": "10a5a682-de44-456c-feed-8932d7a1aa8f",
                "alterId": 64,
                "email": "t@t.tt",
                "security": "auto"
              }
            ]
          }
        ]
      },
      "tag": "VMESS",
      "proxySettings": {
          "tag": "HTTP"
      }
    },
    {
      "protocol": "http",
      "settings": {
        "servers": [
          {
            "address": "192.168.108.1",
            "port": 3128,
            "users": [
              {
                "user": "username",
                "pass": "password"
              }
            ]
          }
        ]
      },
      "tag": "HTTP"
    }
  ]
}
EOF
cat > as_proxy.json <<EOF
{
  "log": {
      "access": "/var/log/v2ray/access.log",
      "error": "/var/log/v2ray/error.log",
      "loglevel": "info"
  },
  "inbounds": [
    {
      "port": [port number],
      "protocol": "vmess",
      "settings": {
        "clients": [
          {
            "id": "[your uuid]",
            "alterId": [your alterid]
          }
        ]
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
:<<EOF
  # 5IOeRnuWFuOaWr+W+t+WTpeWwlOaRqUFtYXpvbuaVsOaNruS4reW/gyAxOCIsDQogICJhZGQiOiAiMTMuNDkuMjQ2LjIwOCIsDQogICJwb3J0IjogIjQ0MyIsDQogICJpZCI6ICJkZjA1NWVhMi00ZDNhLTQ0NWUtOTc3ZC04ZTk1OGFiYWFkM2EiLA0KICAiYWlkIjogIjIiLA0KICAibmV0IjogIndzIiwNCiAgInR5cGUiOiAibm9uZSIsDQogICJob3N0IjogInYycmF5LXNlLTIueGFtanlzc3Zwbi54eXoiLA0KICAicGF0aCI6ICIveGFtanlzczE0My8iLA0KICAidGxzIjogInRscyIsDQogICJzbmkiOiAiIg0KfQ==
  "outbounds": [
    {
      "protocol": "vmess",
      "settings": {
        "vnext": [
          {
            "address": "13.49.246.208",
            "port": 443,
            "users": [
              {
                "email": "user@v2ray.com",
                "id": "df055ea2-4d3a-445e-977d-8e958abaad3a",
                "alterId": 2,
                "security": "auto"
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          "allowInsecure": true
        },
        "wsSettings": {
          "connectionReuse": true,
          "path": "/xamjyss143/",
          "headers": {
            "Host": "v2ray-se-2.xamjyssvpn.xyz"
          }
        }
      },
      "mux": {
        "enabled": true
      },
      "tag": "proxy"
    },
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ]
EOF
HTTP_IP=${HTTP_IP:-127.0.0.1}
HTTP_PORT=${HTTP_PORT:-8891}
:<<EOF
# /etc/systemd/system/v2ray@.service
[Unit]
Description=V2Ray Service
Documentation=https://www.v2fly.org/
After=network.target nss-lookup.target

[Service]
User=nobody
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/v2ray -config /usr/local/etc/v2ray/%i.json
Restart=on-failure
RestartPreventExitStatus=23

[Install]
WantedBy=multi-user.target
EOF
main() {
    local cfg=
    local address= port= id= alterid=
    cat <<EOF
//curl -k -x http://${HTTP_IP}:${HTTP_PORT} http://www.google.com -v
{
  "log": {
    "access": "",
    "error": "",
    "loglevel": "error"
  },
  "inbounds": [
    {
      "tag": "http-in",
      "port": ${HTTP_PORT},
      "listen": "${HTTP_IP}",
      "protocol": "http"
    }
  ],
  "outbounds": [
    {
      "protocol": "vmess",
      "settings": {
        "vnext": [
EOF
    __FIRST__=whatever
    curl -s https://hardss.top/v2/sub  | base64  -d | sed "s_vmess://__g" | while IFS= read -r line ; do
        cfg="$(echo -n $line | base64 -d)"
        address=$(json_config ".add"  <<<  "${cfg}")
        port=$(json_config ".port"  <<<  "${cfg}")
        id=$(json_config ".id"  <<<  "${cfg}")
        alterid=$(json_config ".aid"  <<<  "${cfg}")
        cat <<EOF
          {
            "address": "${address}", "port": ${port},
            "users": [ {
                "email": "user@v2ray.com",
                "id": "${id}",
                "alterId": ${alterid},
                "security": "auto"
              } ]
          }${__FIRST__:+,}
EOF
        unset __FIRST__
    done
cat <<EOF
        ]
      },
      "streamSettings": {
        "network": "tcp"
      },
      "mux": {
        "enabled": true
      },
      "tag": "proxy"
    },
    {
      "protocol": "freedom",
      "tag": "direct"
    }
  ],
  "dns": {
    "servers": [
      "8.8.8.8",
      "localhost"
    ]
  },
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
      {
        "type": "field",
        "ip": [
          "geoip:private",
          "geoip:cn"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "ip": [
          "192.168.0.0/16",
          "fe80::/10"
        ],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "outboundTag": "direct",
        "domain": [
          "domain:baidu.com",
          "domain:163.com"
        ]
      },
      {
        "type": "field",
        "domain": [
          "geosite:cn"
        ],
        "outboundTag": "direct"
      }
    ]
  }
}
EOF
}
main "$@"
