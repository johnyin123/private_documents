#!/usr/bin/env bash
# tayga: NAT64 network

# 2002::/16，
# 而6to4地址的形成如下：
# 2002：IPv4地址：子网ID：：接口ID, (2002::, can not setup in windows)
# 2001:
# ipv6calc --ipv4_to_6to4addr
#
echo "net.ipv4.ip_forward=1"
echo "net.ipv6.conf.all.forwarding=1"

vmaddr=192.168.168.198
natprefix=10.170.29

echo "router add nexthop"
echo "ip r a ${natprefix}.0/24 via ${vmaddr}"

IFS='.' read -r a1 a2 a3 a4 <<< "${natprefix}.1"

echo "vm eth0 config:"
cat <<EOF
auto eth0
allow-hotplug eth0
iface eth0 inet static
    address ${vmaddr}/24
    gateway <you gateway here>

iface eth0 inet6 static
    address 2001::$(printf "%x%02x:%x%02x" ${a1} ${a2} ${a3} ${a4})/96
EOF

echo "/etc/default/tayga"
cat <<EOF
# Defaults for tayga initscript
# sourced by /etc/init.d/tayga
# installed at /etc/default/tayga by the maintainer scripts

# Configure interface and set the routes up
CONFIGURE_IFACE="yes"

# Configure NAT44 for the private IPv4 range
CONFIGURE_NAT44="yes"

# Additional options that are passed to the Daemon.
DAEMON_OPTS=""

# IPv4 address to assign to the NAT64 tunnel device
IPV4_TUN_ADDR="${natprefix}.1"

# IPv6 address to assign to the NAT64 tunnel device
IPV6_TUN_ADDR="2002::$(printf "%x%02x:%x%02x" ${a1} ${a2} ${a3} ${a4})"
EOF

# /usr/share/doc/tayga/tayga.conf.example
# tun-device: the name of the network device that tayga owns.  No need to change this.
# ipv4-addr: an IPv4 address that exists within the dynamic-pool subnet.  No need to change this unless you change dynamic-pool.
# ipv6-addr: an IPv6 address that exists within the real subnet that your Pi was allocated.  For example, if your Pi’s address is 2001:db81/64, then you could set this to 2001:db82/64.
# prefix: the NAT64 prefix that tayga will use; we must use this one as it is the one used by Google’s DNS64.
# dynamic-pool: a private IPv4 subnet that tayga can allocate addresses in.  No need to change this unless it happens to collide with your actual IPv4 subnet.
echo "/etc/tayga.conf"
cat <<EOF
tun-device nat64
ipv4-addr ${natprefix}.1
prefix 2001:ffff::/96
dynamic-pool ${natprefix}.0/24
data-dir /var/spool/tayga
EOF
echo "in ipv6 env ping output: ping 2001:ffff::192.168.168.1"

echo "systemctl stop tayga.service"
echo "/var/spool/tayga/dynamic.map"
echo "add static map ipv4->ipv6"
for i in $(seq 2 254); do printf "map ${natprefix}.%d    2001::%x%02x:%x%02x\n" $i ${a1} ${a2} ${a3} $i; done >> /etc/tayga.conf
