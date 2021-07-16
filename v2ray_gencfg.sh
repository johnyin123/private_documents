#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("v2ray_gencfg.sh - d9da1a9 - 2021-07-16T10:16:09+08:00")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || true
################################################################################
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
      "1.0.0.1",
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
