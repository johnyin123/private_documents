#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"

NS_NAME=ns-rank

cat > ${NS_NAME}.conf <<EOF
BRIDGE="br-int"
# ADDRESS="192.168.167.252/24"
# GATEWAY="192.168.167.1"
# DNS="127.0.0.1"
EOF
cat > netns@.service <<'EOF'
[Unit]
After=network.target
[Service]
Type=oneshot
RemainAfterExit=yes
Environment=ADDRESS=""
Environment=GATEWAY=""
Environment=DNS=""
EnvironmentFile=/etc/%i.conf
ExecStart=/sbin/create_netns.sh --nsname %i --bridge ${BRIDGE} --ipaddr "${ADDRESS}" --gw "${GATEWAY}" --dns "${DNS}"
ExecStart=/sbin/ip netns exec %i /bin/bash /etc/%i/startup.sh
ExecStop=-/sbin/ip netns exec %i /bin/bash /etc/%i/teardown.sh
ExecStop=-/sbin/create_netns.sh --delete %i
[Install]
WantedBy=multi-user.target
EOF
cat >teardown.sh <<'EOF'
#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="\$(readlink -f "\$(dirname "\$0")")"

systemctl stop cfdns || true
systemctl reset-failed
wg-quick down wgrank
EOF
# IFS='.' read -r a1 a2 a3 a4 <<< "${ipaddr}"
# for i in $(seq 2 254); do printf "map ${natprefix}.%d    2001::%x%02x:%x%02x\n" $i ${a1} ${a2} ${a3} $i; done
cat >startup.sh <<EOF
#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
readonly DIRNAME="\$(readlink -f "\$(dirname "\$0")")"

## ipv6 support start
[ -z "\${ADDRESS:-}" ] || {
    ipaddr=\${ADDRESS%/*}
    prefix=\${ADDRESS##*/}
    echo "\${ADDRESS} \${GATEWAY}"
    IFS='.' read -r a1 a2 a3 a4 <<< "\${ipaddr}"
    ipv6=\$(printf "2001::%x%02x:%x%02x\n" \${a1} \${a2} \${a3} \${a4})
    ip -6 addr add \${ipv6}/96 dev eth0 || true
    [ -z "\${GATEWAY}" ] || {
        IFS='.' read -r a1 a2 a3 a4 <<< "\${GATEWAY}"
        ipv6_gw=\$(printf "2001::%x%02x:%x%02x\n" \${a1} \${a2} \${a3} \${a4})
        ip -6 route add default via \${ipv6_gw} dev eth0 || true
    }
    sysctl -w net.ipv6.conf.all.forwarding=1
}
## ipv6 support end

# /usr/sbin/ip route add 192.3.164.171 via 192.168.167.1 || true # use proxy
/usr/sbin/ip route add 10.0.0.0/8 via 192.168.167.1 || true
/usr/sbin/ip route add 172.16.0.0/12 via 192.168.167.1 || true
/usr/sbin/ip route add 192.168.0.0/16 via 192.168.167.1 || true
wg-quick up wgrank
/usr/sbin/ip route replace default via 192.168.32.1 || true
systemd-run --working-directory=\${DIRNAME} --unit cfdns \${NS_NAME:+-p NetworkNamespacePath=/run/netns/\${NS_NAME}} cloudflared proxy-dns
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
table inet filter {
    chain forward {
        type filter hook forward priority 0; policy accept;
        tcp flags & (syn|rst) == syn tcp option maxseg size set rt mtu
    }
}
EO_NAT
EOF
