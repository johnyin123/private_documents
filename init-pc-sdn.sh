#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("6936a75[2024-08-31T08:37:40+08:00]:init-pc-sdn.sh")
################################################################################
DIR=$(pwd)
AWS=10
ALI=20
LOCAL=100
LOCAL_FWMARK=0x440
cfg_file=${DIR}/etc/network/interfaces.d/tunl0
mkdir -p $(dirname "${cfg_file}") && cat <<'EOF' > "${cfg_file}"
auto tunl0
iface tunl0 inet static
    address 192.168.166.0/32
    mtu 1476
    pre-up (/usr/sbin/modprobe ipip || true)
    # # ipip peers
    post-up (/usr/sbin/ip route add 192.168.166.1/32 via 10.9.22.222 dev tunl0 onlink || true)
    post-up (/usr/sbin/ip route add 192.168.166.27/32 via 10.170.24.27 dev tunl0 onlink || true)
    # # route to aws/ali
    post-up (/usr/sbin/ip r a 95.169.24.101 via 10.9.22.222 dev tunl0 onlink || true)
    post-up (/usr/sbin/ip r a 39.104.207.142 via 10.9.22.222 dev tunl0 onlink || true)
    # # inner routes"
    post-up (/usr/sbin/ip r a 172.16.0.0/21 via 10.170.24.27 dev tunl0 onlink || true)
    # post-up (/usr/sbin/ip r a 192.168.1.0/24 via 10.170.24.27 dev tunl0 onlink || true)
    post-down (/usr/sbin/ip link del $IFACE || true)
EOF

cfg_file=${DIR}/etc/network/interfaces.d/br-int
mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
auto br-int
iface br-int inet static
    bridge_ports none
    bridge_maxwait 0
    address 192.168.167.1/24
    # # aws route rule
    post-up (/usr/sbin/ip rule add from 192.168.167.10/32 table ${AWS} || true)
    post-up (/usr/sbin/ip route replace default via 10.8.0.5 table ${AWS} || true)
    post-down (/usr/sbin/ip rule del from 192.168.167.10/32 table ${AWS} || true)
    post-down (/usr/sbin/ip route flush table ${AWS} || true)
    # # ali route rule
    post-up (/usr/sbin/ip rule add from 192.168.167.20/32 table ${ALI} || true)
    post-up (/usr/sbin/ip route replace default via 192.168.168.250 table ${ALI} || true)
    post-down (/usr/sbin/ip rule del from 192.168.167.20/32 table ${ALI} || true)
    post-down (/usr/sbin/ip route flush table ${ALI} || true)
EOF

cat<<EOHOST>>${DIR}/etc/hosts
# # start site address
111.124.200.227   pop3.163.com
101.71.33.11      mirrors.163.com
20.205.243.166    github.com
# # end site address
EOHOST

list_site_addr() {
    local file=${DIR}/etc/hosts
    sed -n '/^\s*#\s*#\s*start site address/,/^\s*#\s*#\s*end site address/p' ${file} | while IFS= read -r line; do
        [[ ${line} =~ ^\s*#.*$ ]] && continue #skip comment line
        [[ ${line} =~ ^\s*$ ]] && continue #skip blank
        read -r tip tname <<< "${line}"
        echo -n "$tip/32, "
    done
}
cat <<EOF
# # host white list website
cat <<EONFT | nft -f /dev/stdin
# flush table ip xxx
# delete table ip xxx
define CAN_ACCESS_IPS = { $(list_site_addr) }
table inet mangle {
    set canouts4 {
        typeof ip daddr
        flags interval
        elements = { \$CAN_ACCESS_IPS }
    }
    # # for as a router mode
    # chain prerouting {
    #     type filter hook prerouting priority mangle; policy accept;
    #     ip daddr @canouts4 meta l4proto { tcp, udp } meta mark set 0x440
    # }
    # # Only for local mode
    chain output {
        type route hook output priority mangle; policy accept;
        ip daddr @canouts4 meta l4proto { tcp, udp } meta mark set 0x440
    }
}
EONFT

cat <<EOIPT
# # iptable mode
ipset create myset hash:net
ipset add myset 111.124.200.227
ipset add myset 101.71.33.11/32
ipset add myset 20.205.243.166/32
iptables -t mangle -A OUTPUT -m set --match-set myset dst -j MARK --set-mark 0x440
iptables -t nat -A POSTROUTING -m set --match-set myset dst -j SNAT --to-source 192.168.168.1
iptables -t mangle -nvL
EOIPT

# #  add in rc.local
ip rule add fwmark ${LOCAL_FWMARK} table ${LOCAL} || true
ip route flush table ${LOCAL} || true
ip route replace default via 192.168.168.250 table ${LOCAL} || true

#for connect each other! br-int/br-ext
# ip r | grep kernel | while read line; do  echo ip route add \$line table ${AWS}; done
# ip r | grep kernel | while read line; do  echo ip route add \$line table ${ALI}; done
ip route add 10.170.6.0/24    dev br-ext proto kernel scope link src 10.170.6.105  table ${AWS}
ip route add 192.168.167.0/24 dev br-int proto kernel scope link src 192.168.167.1 table ${AWS}
ip route add 192.168.168.0/24 dev br-ext proto kernel scope link src 192.168.168.1 table ${AWS}
ip route add 192.168.169.0/24 dev br-ext proto kernel scope link src 192.168.169.1 table ${AWS}
ip route add 10.170.6.0/24    dev br-ext proto kernel scope link src 10.170.6.105  table ${ALI}
ip route add 192.168.167.0/24 dev br-int proto kernel scope link src 192.168.167.1 table ${ALI}
ip route add 192.168.168.0/24 dev br-ext proto kernel scope link src 192.168.168.1 table ${ALI}
ip route add 192.168.169.0/24 dev br-ext proto kernel scope link src 192.168.169.1 table ${ALI}
exit 0

EOF

cfg_file=${DIR}/etc/aws.conf 
mkdir -p $(dirname "${cfg_file}") && cat <<'EOF' > "${cfg_file}"
BRIDGE=br-int
IPADDR=192.168.167.10/24
GATEWAY=192.168.167.1
NAMESERVER=8.8.8.8
EOF

cfg_file=${DIR}/etc/ali.conf 
mkdir -p $(dirname "${cfg_file}") && cat <<'EOF' > "${cfg_file}"
BRIDGE=br-int
IPADDR=192.168.167.20/24
GATEWAY=192.168.167.1
NAMESERVER=114.114.114.114
EOF

cfg_file=${DIR}/etc/systemd/system/netns@.service
mkdir -p $(dirname "${cfg_file}") && cat <<'EOF' | grep -v "^\s*#" > "${cfg_file}"
[Unit]
Description=Named network namespace %i
After=network.target
StopWhenUnneeded=true
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

cfg_file=${DIR}/etc/systemd/system/bridge-netns@.service
mkdir -p $(dirname "${cfg_file}") && cat <<'EOF' > "${cfg_file}"
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
[Install]
WantedBy=multi-user.target
EOF

cat <<EOF

# # systemd service netns route table & nat
nft add table nat
nft 'add chain nat postrouting { type nat hook postrouting priority srcnat; policy accept; }'
nft add rule nat postrouting ip saddr 192.168.167.10/32 counter masquerade
nft add rule nat postrouting ip saddr 192.168.167.20/32 counter masquerade

# # route rule need setup, so br-int post-up do it
# ip rule add from 192.168.167.10/32 table ${AWS} || true
# ip route replace default via 10.8.0.5 table ${AWS} || true
# ip rule add from 192.168.167.20/32 table ${ALI} || true
# ip route replace default via 192.168.168.250 table ${ALI} || true

systemctl enable bridge-netns@aws.service
systemctl enable bridge-netns@ali.service
EOF
