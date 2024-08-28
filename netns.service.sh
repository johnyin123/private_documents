cat <<'EOF' > netns@.service
[Unit]
Description=Named network namespace %i
StopWhenUnneeded=true
[Service]
Type=oneshot
PrivateNetwork=yes
RemainAfterExit=yes
ExecStart=/bin/touch /var/run/netns/%i
ExecStart=/bin/mount --bind /proc/self/ns/net /var/run/netns/%i
ExecStop=/sbin/ip netns delete %i
EOF
cat << 'EOF' > bridge-netns@.service
[Unit]
Requires=netns@%i.service
After=netns@%i.service
[Service]
Type=oneshot
RemainAfterExit=yes
Environment=NAMESERVER=""
EnvironmentFile=/etc/%i.conf
ExecStart=/sbin/ip link add %i_eth0 type veth peer name %i_eth1
ExecStart=/sbin/ip link set %i_eth0 netns %i name eth0 up
ExecStart=/sbin/ip link set %i_eth1 master ${BRIDGE}
ExecStart=/sbin/ip link set dev %i_eth1 up
ExecStart=/sbin/ip netns exec %i /sbin/ip address add ${IPADDR} dev eth0
ExecStart=/sbin/ip netns exec %i /sbin/ip route add default via ${GATEWAY} dev eth0
ExecStart=-/bin/mkdir -p /etc/netns/%i
ExecStart=-/bin/sh -c "[ -z '${NAMESERVER}' ] || echo 'nameserver ${NAMESERVER}' > /etc/netns/%i/resolv.conf"
ExecStop=-/bin/rm -fr /etc/netns/%i/
ExecStop=-/sbin/ip link set %i_eth1 promisc off
ExecStop=-/sbin/ip link set %i_eth1 down
ExecStop=-/sbin/ip link set dev %i_eth1 nomaster
ExecStop=-/sbin/ip link delete %i_eth1
EOF

TEST_SVC=webserver

cat <<'EOF' > ${TEST_SVC}.conf
BRIDGE=br-ext
IPADDR=192.168.168.133/24
GATEWAY=192.168.168.250
# NAMESERVER=114.114.114.114
EOF
systemctl enable bridge-netns@xxxx --now

cat <<EOF > ${TEST_SVC}.service
[Unit]
Description=${TEST_SVC} in netns
Requires=netns@${TEST_SVC}.service bridge-netns@${TEST_SVC}.service
After=netns@${TEST_SVC}.service bridge-netns@${TEST_SVC}.service
JoinsNamespaceOf=netns@${TEST_SVC}.service

[Service]
Type=simple
PrivateNetwork=true
ExecStart=/usr/sbin/sshd -D
[Install]
WantedBy=multi-user.target
EOF
