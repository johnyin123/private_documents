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
