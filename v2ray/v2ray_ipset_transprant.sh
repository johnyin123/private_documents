#!/usr/bin/env bash

LOGFILE=""
# LOGFILE="-a log.txt"
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }

cat <<EOF
ip rule delete fwmark 1 table 100
ip route delete local default dev lo table 100
nft flush ruleset
ip rule
ip route show table 100
iptables-save
# https://github.com/Loyalsoldier/v2ray-rules-dat/releases
cp geoip.dat geosite.dat /etc/v2ray/
systemctl restart v2ray
journalctl -f
# # 通过 http 的inbound来测试下隧道
curl -Is -x 127.0.0.1:10888 https://www.google.com -vvvv

# Name: v2ray.location.asset or V2RAY_LOCATION_ASSET
# Default value: Same directory where v2ray is.
# This variable specifies a directory where geoip.dat and geosite.dat files are.
V2RAY_LOCATION_ASSET=/etc/v2ray v2ray -c /etc/v2ray/config.json

使用:
局域网内的主机将默认网关修改为透明网关所在的IP就可以实现本机全局自动翻墙，我上面的配置文件将国内流量国外流量自动分流了。客户端不需要做任何特殊设置即可使用。
EOF

V2RAY_TPROXY_PORT=50099

cat <<EOF | sed "/^\s*#/d"  > tproxy.json
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
      "port": 10888,
      "listen": "127.0.0.1",
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
      "protocol": "vmess",
      .................
      // streamSettings/sockopt打上标志, 防止环路
      .................
      "streamSettings": {
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
    "servers": [
      {
        "address": "223.5.5.5",
        "port": 53,
        "domains": [
          "geosite:cn",
          "ntp.org"
        ]
      },
      {
        "address": "8.8.8.8",
        "port": 53,
        "domains": [
          "geosite:geolocation-!cn"
        ]
      },
      {
        "address": "1.1.1.1",
        "port": 53,
        "domains": [
          "geosite:geolocation-!cn"
        ]
      }
    ]
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

iptables -t mangle -A V2RAY -p tcp -j TPROXY --on-ip 127.0.0.1 --on-port ${V2RAY_TPROXY_PORT} --tproxy-mark 1
iptables -t mangle -A V2RAY -p udp -j TPROXY --on-ip 127.0.0.1 --on-port ${V2RAY_TPROXY_PORT} --tproxy-mark 1

iptables -t mangle -A PREROUTING -j V2RAY
iptables -t mangle -nvL

# # 本地进程发起的连接经过OUTPUT->POSTROUTING；而TPROXY只能在PREROUTING中使用。
# # 可以通过让将OUTPUT的包重新经过PREROUTING的办法来实现对网关本机的代理。
#
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

log "add ip rule"
# ip rule delete fwmark 1 table 100
ip rule add fwmark 1 table 100
# # 将所有(0.0.0.0/0)包重定向到lo（从而进入INPUT）
# ip route delete local default dev lo table 100
ip route add local 0.0.0.0/0 dev lo table 100
# # PREROUTING的包就会到达端口V2RAY_TPROXY_PORT
