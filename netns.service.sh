echo "/lib/systemd/system"
echo "/etc/systemd/system"
echo "systemd netns, DNS NOT WORK, ip netns is ok"

cat <<'EOF' | grep -v "^\s*#" > netns@.service
[Unit]
Description=Named network namespace %i
After=network.target
StopWhenUnneeded=yes
[Service]
Type=oneshot
PrivateNetwork=yes
RemainAfterExit=yes
# # /bin/touch: 无法 touch '/var/run/netns/aws
# ExecStart=/bin/touch /var/run/netns/%i
# ExecStart=/bin/mount --bind /proc/self/ns/net /var/run/netns/%i
ExecStart=/bin/sh -c '/sbin/ip netns attach %i $$$$'
ExecStop=/sbin/ip netns delete %i
EOF
cat <<'EOF' > bridge-netns@.service
[Unit]
Requires=netns@%i.service
After=netns@%i.service
[Service]
Type=oneshot
RemainAfterExit=yes
Environment=DNS=""
EnvironmentFile=/etc/%i.conf
ExecStart=/sbin/ip link add %i_eth0 type veth peer name %i_eth1
ExecStart=/sbin/ip link set %i_eth0 netns %i name eth0 up
ExecStart=/sbin/ip link set %i_eth1 master ${BRIDGE}
ExecStart=/sbin/ip link set dev %i_eth1 up
ExecStart=/sbin/ip netns exec %i /sbin/ip address add ${ADDRESS} dev eth0
ExecStart=/sbin/ip netns exec %i /sbin/ip route add default via ${GATEWAY} dev eth0
ExecStart=-/bin/mkdir -p /etc/netns/%i
ExecStart=-/bin/sh -c "[ -z '${DNS}' ] || echo 'nameserver ${DNS}' > /etc/netns/%i/resolv.conf"
ExecStop=-/bin/rm -fr /etc/netns/%i/
ExecStop=-/sbin/ip link set %i_eth1 promisc off
ExecStop=-/sbin/ip link set %i_eth1 down
ExecStop=-/sbin/ip link set dev %i_eth1 nomaster
ExecStop=-/sbin/ip link delete %i_eth1
[Install]
WantedBy=multi-user.target
EOF

TEST_SVC=myssh

cat <<'EOF' > ${TEST_SVC}.conf
BRIDGE=br-ext
ADDRESS=192.168.168.133/24
GATEWAY=192.168.168.250
# DNS=114.114.114.114
EOF

cat <<EOF > ${TEST_SVC}.service
[Unit]
# systemctl stop bridge-netns@${TEST_SVC}.service
Description=${TEST_SVC} in netns
Wants=network-online.target
Requires=netns@${TEST_SVC}.service bridge-netns@${TEST_SVC}.service
After=netns@${TEST_SVC}.service bridge-netns@${TEST_SVC}.service

[Service]
Type=simple
ExecStart=ip netns exec ${TEST_SVC} /usr/sbin/sshd -D
[Install]
WantedBy=multi-user.target
EOF

cat <<EOF >aws.conf
BRIDGE=br-int
ADDRESS=192.168.167.10/24
GATEWAY=192.168.167.1
DNS=8.8.8.8
EOF

cat <<EOF
##################################################################################################
# # aws.conf init start
nft add table nat
nft 'add chain nat postrouting { type nat hook postrouting priority srcnat; policy accept; }'
nft add rule nat postrouting ip saddr 192.168.167.10/32 counter masquerade
ip rule add from 192.168.167.10/32 table 10 || true
ip route replace default via 10.8.0.5 table 10 || true
systemctl enable bridge-netns@aws.service --now
# # aws.conf init end
##################################################################################################
EOF

cat <<EOF > ali.conf
BRIDGE=br-int
ADDRESS=192.168.167.20/24
GATEWAY=192.168.167.1
DNS=114.114.114.114
EOF

cat <<EOF
##################################################################################################
# # ali.conf init start
nft add table nat
nft 'add chain nat postrouting { type nat hook postrouting priority srcnat; policy accept; }'
nft add rule nat postrouting ip saddr 192.168.167.20/32 counter masquerade
ip rule add from 192.168.167.20/32 table 20 || true
ip route replace default via 192.168.168.250 table 20 || true
systemctl enable bridge-netns@ali.service --now
# # ali.conf init end
##################################################################################################
EOF
