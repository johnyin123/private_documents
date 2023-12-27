#!/usr/bin/env bash
#/etc/openvpn/upaws.sh tun0 1500 0 10.8.0.6 10.8.0.5 init
ip route delete 192.168.169.0/24 table 200 || true
ip route delete default table 200 || true
ip rule delete from 192.168.169.0/24 || true

ip rule add from 192.168.169.0/24 table 200 || true
ip route add default via $5 dev $1 table 200 || true
ip route add 192.168.169.0/24 dev br-ext scope link table 200 || true
# iptables -t nat -A POSTROUTING -s 192.168.169.0/24 -j MASQUERADE || true
exit 0
