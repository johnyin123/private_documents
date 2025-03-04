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
VERSION+=("cb04ba9[2025-02-24T16:34:36+08:00]:v2ray.ipset.transprant.sh")
################################################################################
# export FILTER_CMD=cat;;
# export FILTER_CMD=tee output.log
cat <<EOF
UUID=${UUID:-UNDEFINE}
ALTERID=${ALTERID:-UNDEFINE}
WSPATH=${WSPATH:-UNDEFINE}
SERVER=${SERVER:-tunl.wgserver.org}
EOF

V2RAY_TPROXY_PORT=50099

cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'} > v2ray.cli.tproxy.config.json
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
      "protocol": "http",
      "settings": {
        "userLevel": 0,
        "auth": "noauth",
        "udp": true,
        "ip": "127.0.0.1"
      },
      "streamSettings": {
        "sockopt": {
          "mark": 255
        }
      }
    },
    # #################测试inbound end
    {
      "tag":"transparent",
      "listen": "127.0.0.1",
      "port": ${V2RAY_TPROXY_PORT},
      "protocol": "dokodemo-door",
      "settings": {
        "network": "tcp,udp",
        "followRedirect": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": [
          "http",
          "tls"
        ]
      },
      "streamSettings": {
        "sockopt": {
          "tproxy": "tproxy",
          # 使用tproxy模式
          "mark": 255
          # 打上标志, 防止环路
        }
      }
    }
  ],
  "outbounds": [
    {
      "tag": "proxy",
      # VLESS使用了更为安全的AEAD加密方式，而VMess则使用的是更加常见的AES-CFB等对称加密方式。AEAD加密方式在保证数据安全的同时，还能够提供数据完整性的校验，防止数据被篡改。2.传输方式：VLESS采用了更加高效的QUIC协议作为传输方式，而VMess则采用的是TCP或者WebSocket。
      "protocol": "vless",
      "settings": {
        "vnext": [
          {
            "address": "${SERVER}",
            "port": 443,
            "users": [
              {
                "encryption":"none",
                "id": "${UUID}",
                "alterId": ${ALTERID}
              }
            ]
          }
        ]
      },
      "streamSettings": {
        "network": "ws",
        "security": "tls",
        "tlsSettings": {
          //"fingerprint": "firefox",
          //"serverName": "your.domain.name",
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
          "path": "${WSPATH}"
        },
        # streamSettings/sockopt打上标志, 防止环路
        "sockopt": {
          "mark": 255
          # 打上标志, 防止环路, 注意每个出口都必须打上
        }
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom",
      "streamSettings": {
        "sockopt": {
          "mark": 255
          # 直连的也需要打上标志, 防止环路, 注意每个出口都必须打上
        }
      }
    },
    {
      "tag": "block",
      # 流量黑洞, 网站屏蔽
      "protocol": "blackhole",
      "settings": {
        "response": {
          "type": "http"
        }
      }
    },
    {
      "tag": "dns-out",
      "protocol": "dns",
      "streamSettings": {
        "sockopt": {
          "mark": 255
          # dns出口的也需要打上标志
        }
      }
    }
  ],
  # 解决dns污染
  "dns": {
      {
        "tag": "ali",
        "address": "https://223.6.6.6/dns-query",
        "domains": [
          "geosite:cn",
          "ntp.org"
        ]
      },
      {
        "tag": "cloudflare",
        "address": "https://1.1.1.1/dns-query",
        "domains": [
          "geosite:geolocation-!cn"
        ]
      }
  },
  # 主要做了国内外分流, 出口负载
  "routing": {
    "domainStrategy": "IPOnDemand",
    "domainMatcher": "mph",
    "balancers": [
      {
        # 出口标签, 类似分组, 在routing中使用到, 可自定义其他的, 控制哪些源ip从哪组出口出去
        "tag": "proxy",
        # 上面 outbounds中的海外出口
        "selector": [
          "trojan",
          "vmess",
          "vless"
        ],
        "strategy": {
          "type": "random"
          # 随机负载
        }
      }
    ],
    "rules": [
      # dns 劫持
      {
        "type": "field",
        "inboundTag": [
          "transparent"
        ],
        "port": 53,
        "network": "udp",
        "outboundTag": "dns-out"
      },
      # 时间同步直连
      {
        "type": "field",
        "inboundTag": [
          "transparent"
        ],
        "port": 123,
        "network": "udp",
        "outboundTag": "direct"
      },
      # 国内DNS地址直连, 可自行添加其他的
      {
        "type": "field",
        "ip": [
          "223.5.5.5",
          "114.114.114.114"
        ],
        "outboundTag": "direct"
      },
      # 海外DNS地址直连, 可自行添加其他的
      {
        "type": "field",
        "ip": [
          "8.8.8.8",
          "1.1.1.1"
        ],
        "balancerTag": "proxy"
      },
      # BT直连
      {
        "type": "field",
        "protocol":["bittorrent"],
        "outboundTag": "direct"
      },
      # 自定义走代理
      {
        "type": "field",
        "ip": [
          "geoip:hk",
          "geoip:mo"
        ],
        "balancerTag": "proxy"
      },
      # 国内直连
      {
        "type": "field",
        "ip": [
          "geoip:private",
          "geoip:cn"
        ],
        "outboundTag": "direct"
      },
      # 海外走代理
      {
        "type": "field",
        "domain": [
          "geosite:geolocation-!cn",
          "geosite:google-scholar"
        ],
        "balancerTag": "proxy"
      },
      # 国内直连
      {
        "type": "field",
        "domain": [
          "geosite:cn",
          "geosite:category-scholar-!cn",
          "geosite:category-scholar-cn"
        ],
        "outboundTag": "direct"
      },
      # 匹配不到的全走代理
      {
        "type": "field",
        "port": "0-65535",
        "balancerTag": "proxy",
        "enabled": true
      }
    ]
  }
}
EOF

echo '#!/usr/bin/env bash' > v2ray.cli.tproxy.ipt.sh
cat <<EO_SH | ${FILTER_CMD:-sed '/^\s*#/d'} >> v2ray.cli.tproxy.ipt.sh
TPROXY_PORT=${V2RAY_TPROXY_PORT}
RULE_TABLE=100
FWMARK=0x440
LOGFILE="" #"-a log.txt"
EO_SH
cat <<'EO_SH' | ${FILTER_CMD:-sed '/^\s*#/d'} >> v2ray.cli.tproxy.ipt.sh
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }
IPSET_NAME=local_ip
# # RFC5735
iplist=(
    0.0.0.0/8
    10.0.0.0/8
    127.0.0.0/8
    169.254.0.0/16
    172.16.0.0/12
    192.168.0.0/16
    224.0.0.0/4
    240.0.0.0/4
)

ipset create ${IPSET_NAME} hash:net 2>/dev/null || {
    log "${IPSET_NAME} exists flush clear"
    ipset flush ${IPSET_NAME}
}
log "add ipset"
cat <<EOF | tee ${LOGFILE} | ipset -exist restore
create ${IPSET_NAME} hash:net
$(for ip in "${iplist[@]}"; do
    echo add ${IPSET_NAME} ${ip}
done)
EOF

log "add tproxy iptable rules, for as gateway"
iptables -t mangle -N V2RAY
# 过滤掉局域网内的请求，除非目标端口是53, 劫持 DNS 请求
iptables -t mangle -A V2RAY -p tcp -m set --match-set ${IPSET_NAME} dst -m tcp ! --dport 53 -j RETURN
iptables -t mangle -A V2RAY -p udp -m set --match-set ${IPSET_NAME} dst -m udp ! --dport 53 -j RETURN
# iptables -t mangle -A V2RAY -p udp -m owner --uid-owner nginx -j RETURN

iptables -t mangle -A V2RAY -p tcp -j TPROXY --on-ip 127.0.0.1 --on-port ${TPROXY_PORT} --tproxy-mark ${FWMARK}
iptables -t mangle -A V2RAY -p udp -j TPROXY --on-ip 127.0.0.1 --on-port ${TPROXY_PORT} --tproxy-mark ${FWMARK}

iptables -t mangle -A PREROUTING -j V2RAY

# # Only for local mode, not as router
# iptables -t mangle -A OUTPUT -m set --match-set ${IPSET_NAME} dst -j RETURN
# iptables -t mangle -A OUTPUT -p tcp -j MARK --set-mark 1
# iptables -t mangle -A OUTPUT -p udp -j MARK --set-mark 1
# # 本地进程发起的连接经过OUTPUT->POSTROUTING；而TPROXY只能在PREROUTING中使用。
# # 可以通过让将OUTPUT的包重新经过PREROUTING的办法来实现对网关本机的代理。
# log "add tproxy iptable rules, for local machine"
# iptables -t mangle -N V2RAY_LOCAL
# iptables -t mangle -A V2RAY_LOCAL -p tcp -m set --match-set ${IPSET_NAME} dst -m tcp ! --dport 53 -j RETURN
# iptables -t mangle -A V2RAY_LOCAL -p udp -m set --match-set ${IPSET_NAME} dst -m udp ! --dport 53 -j RETURN
# # 过滤掉代理程序发出的包
# iptables -t nat -A V2RAY -d <V2Ray server> -j RETURN ## or can add <V2Ray server> to local ipset
# iptables -t mangle -A V2RAY_LOCAL -m cgroup --path system.slice/v2ray.service -j RETURN
# # 打fwmark标记；根据已经配置的路由规则，标记的包会重回lo，从而经过PREROUTING
# iptables -t mangle -A V2RAY_LOCAL -p tcp -j MARK --set-mark 1
# iptables -t mangle -A V2RAY_LOCAL -p udp -j MARK --set-mark 1
# # 将chain附加到mangle table的OUTPUT chain
# iptables -t mangle -A OUTPUT -j V2RAY_LOCAL
iptables -t mangle -nvL

log "add ip rule"
ip rule delete fwmark ${FWMARK} table ${RULE_TABLE} 2>/dev/null || true
ip rule add fwmark ${FWMARK} table ${RULE_TABLE}
# # 将所有(0.0.0.0/0)包重定向到lo（从而进入INPUT）
# ip route delete local default dev lo table ${RULE_TABLE}
ip route replace local 0.0.0.0/0 dev lo table ${RULE_TABLE}
# # PREROUTING的包就会到达端口TPROXY_PORT
EO_SH

echo '#!/usr/bin/env bash' > v2ray.cli.tproxy.nft.sh
cat <<EOF | ${FILTER_CMD:-sed '/^\s*#/d'} >> v2ray.cli.tproxy.nft.sh
TPROXY_PORT=${V2RAY_TPROXY_PORT}
RULE_TABLE=100
FWMARK=0x440
LOGFILE="" #"-a log.txt"
EOF
cat <<'EOF' | ${FILTER_CMD:-sed '/^\s*#/d'} >> v2ray.cli.tproxy.nft.sh
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }
log "add tproxy nft ruleset"
cat<<EONFT | nft -f /dev/stdin
flush ruleset
define V2RAY_TPROXY_PORT=${TPROXY_PORT};
define FWMARK_PROXY = ${FWMARK};
# # chn ipaddress, can add to BYPASS4
# # include "/etc/direct-ipv4.nft";
# https://github.com/misakaio/chnroutes2/raw/master/chnroutes.txt
# https://github.com/felixonmars/chnroutes-alike/blob/master/chnroutes-alike.txt
define BYPASS4 = { 0.0.0.0/8, 10.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4 }
table ip v2ray {
    set bypassv4 {
        typeof ip daddr
        flags interval
        elements = { \$BYPASS4 }
    }
    chain prerouting {
        type filter hook prerouting priority filter; policy accept;
        ip daddr @bypassv4 tcp dport != 53 counter return
        ip daddr @bypassv4 udp dport != 53 counter return
        meta mark 0x000000ff counter return
        meta l4proto { tcp, udp } meta mark set \$FWMARK_PROXY tproxy to 127.0.0.1:\$V2RAY_TPROXY_PORT accept
    }
    chain output {
        type route hook output priority filter; policy accept;
        ip daddr @bypassv4 tcp dport != 53 counter return
        ip daddr @bypassv4 udp dport != 53 counter return
        meta mark 0x000000ff counter return
        meta l4proto { tcp, udp } meta mark set \$FWMARK_PROXY accept
    }
    chain divert {
        type filter hook prerouting priority mangle; policy accept;
        meta l4proto tcp socket transparent 1 meta mark set \$FWMARK_PROXY accept
    }
}
EONFT

log "add ip rule"
ip rule delete fwmark ${FWMARK} table ${RULE_TABLE} 2>/dev/null || true
ip rule add fwmark ${FWMARK} table ${RULE_TABLE}
ip route replace local 0.0.0.0/0 dev lo table ${RULE_TABLE}
EOF
