#!/usr/bin/env bash
cat > ns-rank.conf <<EOF
BRIDGE="br-int"
ADDRESS="192.168.167.252/24"
GATEWAY="192.168.167.1"
DNS="8.8.8.8"
EOF
cat > netns@.service <<'EOF'
[Unit]
After=network.target
[Service]
Type=oneshot
RemainAfterExit=yes
EnvironmentFile=/etc/%i.conf
ExecStart=/sbin/create_netns.sh --ipaddr ${ADDRESS} --nsname %i --bridge ${BRIDGE} --gw ${GATEWAY} --dns ${DNS}
ExecStart=/sbin/ip netns exec %i /bin/bash /etc/%i/startup.sh
ExecStop=-/sbin/ip netns exec %i /bin/bash /etc/%i/teardown.sh
ExecStop=-/sbin/create_netns.sh --delete %i
[Install]
WantedBy=multi-user.target
EOF
cat >teardown.sh <<'EOF'
#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
kill -9 $(cat /etc/ns-rank/dns.pid)
wg-quick down wgrank
EOF
cat >startup.sh <<'EOF'
#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
# /usr/sbin/ip route add 192.3.164.171 via 192.168.167.1 || true # use proxy
/usr/sbin/ip route add 10.0.0.0/8 via 192.168.167.1 || true
/usr/sbin/ip route add 172.16.0.0/12 via 192.168.167.1 || true
/usr/sbin/ip route add 192.168.0.0/16 via 192.168.167.1 || true
wg-quick up wgrank
/usr/sbin/ip route replace default via 192.168.32.1 || true
/usr/sbin/ip route replace 192.168.31.111 via 192.168.32.1 || true
/usr/sbin/ip route replace 192.168.2.4 via 192.168.32.1 || true
/usr/sbin/ip route replace 192.168.169.101 via 192.168.32.1 || true
cloudflared proxy-dns &>/dev/null &
echo $! > /etc/ns-rank/dns.pid
echo 'nameserver 127.0.0.1' > /etc/resolv.conf
sysctl -w net.ipv4.ip_forward=1
sysctl -w net.ipv4.ip_default_ttl=128
sysctl -w net.ipv4.ping_group_range="0 2147483647" || true
cat<<EO_NAT | nft -f /dev/stdin
flush ruleset
table ip nat {
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        # ip saddr 192.168.167.0/24 ip daddr != 192.168.167.0/24 counter masquerade
        masquerade
    }
}
table ip filter {
    chain forward {
        type filter hook forward priority 0; policy accept;
        meta l4proto tcp tcp flags & (syn|rst) == syn counter tcp option maxseg size set rt mtu
    }
}
EO_NAT
EOF
