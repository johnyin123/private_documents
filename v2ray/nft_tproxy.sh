#!/usr/bin/env bash
TPROXY_PORT=50099
RULE_TABLE=100
FWMARK=0x440
cat<<EONFT
# # tproxy ipv4 tcp&udp
# # chn ipaddress
# https://github.com/misakaio/chnroutes2/raw/master/chnroutes.txt
# https://github.com/felixonmars/chnroutes-alike/blob/master/chnroutes-alike.txt
# define direct_ipv4 = { 0.0.0.0/8, 10.0.0.0/8, 127.0.0.0/8, 169.254.0.0/16, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4, chnipsxxxxxxxxxxxxx }
include "/usr/local/lib/nft-transproxy/nft/direct-ipv4.nft";
table ip ipv4_tproxy {
  set direct_address {
    type ipv4_addr
    flags interval
    auto-merge
    elements = \$direct_ipv4
  }
  chain output {
    type route hook output priority mangle
    ip daddr @direct_address accept
    meta l4proto { tcp, udp } mark set ${FWMARK} accept
  }
  chain prerouting {
    type filter hook prerouting priority filter
    meta l4proto tcp socket transparent 1 meta mark ${FWMARK} accept
    meta l4proto { tcp, udp } mark ${FWMARK} tproxy to :${TPROXY_PORT}
  }
}

# # tproxy ipv6 tcp&udp
# # chn ipaddress
# https://raw.githubusercontent.com/PaPerseller/chn-iplist/master/chnroute-ipv6.txt
# define direct_ipv6 = { ::/128, ::1/128, fc00::/7, fe80::/10, ff00::/8,  chnipv6xxxxxxxx }
include "/usr/local/lib/nft-transproxy/nft/direct-ipv6.nft";
table ip6 ipv6_tproxy {
  set direct_address6 {
    type ipv6_addr
    flags interval
    auto-merge
    elements = \$direct_ipv6
  }
  chain output {
    type route hook output priority mangle
    ip6 daddr @direct_address6 accept
    meta l4proto { tcp, udp } mark set ${FWMARK} accept
  }
  chain prerouting {
    type filter hook prerouting priority filter
    meta l4proto tcp socket transparent 1 mark ${FWMARK} accept
    meta l4proto { tcp, udp } mark ${FWMARK} tproxy to :${TPROXY_PORT}
  }
}
EONFT
cat <<EOF
[Unit]
Description=nft & ip rule for TCP/UDP TPROXY
After=network.target

[Service]
Type=oneshot
RemainAfterExit=yes
# start
ExecStart=/usr/bin/nft --file /usr/local/lib/nft-transproxy/nft/transproxy.nft
ExecStartPost=/usr/bin/ip rule add fwmark ${FWMARK} lookup ${RULE_TABLE}
ExecStartPost=/usr/bin/ip route add local 0.0.0.0/0 dev lo table ${RULE_TABLE}
ExecStartPost=/usr/bin/ip -6 rule add fwmark ${FWMARK} lookup ${RULE_TABLE}
ExecStartPost=/usr/bin/ip -6 route add local ::/0 dev lo table ${RULE_TABLE}
# reload
ExecReload=/usr/bin/nft --file /usr/local/lib/nft-transproxy/nft/transproxy.nft
# stop
ExecStop=/usr/bin/nft flush ruleset
ExecStopPost=/usr/bin/ip rule del fwmark ${FWMARK} lookup ${RULE_TABLE}
ExecStopPost=/usr/bin/ip route del local 0.0.0.0/0 dev lo table ${RULE_TABLE}
ExecStopPost=/usr/bin/ip -6 rule del fwmark ${FWMARK} lookup ${RULE_TABLE}
ExecStopPost=/usr/bin/ip -6 route del local ::/0 dev lo table ${RULE_TABLE}

[Install]
WantedBy=multi-user.target
EOF
