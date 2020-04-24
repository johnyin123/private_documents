#!/usr/bin/env bash

echo "gen.sh PDEV BOND BRIDGE VLAN"
DEV=${1:-eno1}
BOND=${2:-bond0}
BRIDGE=${3:-br-data}
VLAN=${4:-147}

cat <<EOF > ifcfg-${DEV}
NM_CONTROLLED=no
DEVICE=${DEV}
ONBOOT=yes
IPV6INIT=no
MASTER=${BOND}
SLAVE=yes
EOF
cat <<EOF > ifcfg-${BOND}
NM_CONTROLLED=no
TYPE=Bond
NAME=${BOND}
DEVICE=${BOND}
BONDING_MASTER=yes
ONBOOT=yes
BOOTPROTO=none
TYPE=Ethernet
BONDING_OPTS="mode=802.3ad miimon=100 xmit_hash_policy=layer3+4"
# BONDING_OPTS="mode=802.3ad miimon=100 lacp_rate=fast xmit_hash_policy=layer2+3"
# BONDING_OPTS='mode=6 miimon=100'
# cat /proc/net/bonding/bond0
EOF
cat <<EOF > ifcfg-${BOND}.${VLAN}
NM_CONTROLLED=no
DEVICE="${BOND}.${VLAN}"
ONBOOT="yes"
BRIDGE="${BRIDGE}.${VLAN}"
VLAN=yes
EOF
cat <<EOF > ifcfg-${BRIDGE}.${VLAN}
NM_CONTROLLED=no
DEVICE="${BRIDGE}.${VLAN}"
ONBOOT="yes"
TYPE="Bridge"
BOOTPROTO="none"
#STP="on"
EOF
cat <<EOF
IPADDR=""
PREFIX=""
GATEWAY=
# echo layer2+3 > /sys/class/net/bond0/bonding/xmit_hash_policy

ip link add name lag1 type bond
ip link set down dev eth0
ip link set down dev eth1
ethtool -s eth0 speed 10000 duplex full
ethtool -s eth1 speed 10000 duplex full
>/sys/class/net/lag1/bonding/mode      echo active-backup
>/sys/class/net/lag1/bonding/miimon    echo 100
>/sys/class/net/lag1/bonding/min_links echo 1
>/sys/class/net/lag1/bonding/slaves    echo +eth1
>/sys/class/net/lag1/bonding/slaves    echo +eth0
ip link set up dev lag1
ip link set up dev eth0
ip link set up dev eth1

====================

# Executed on each VM
ip link set down dev eth0
ip link set down dev eth1
ethtool -s eth0 speed 1000 duplex full
ethtool -s eth1 speed 1000 duplex full
modprobe bonding
[ -d /sys/class/net/bond0 ] || \
    ip link add name bond0 type bond
ip link set down dev bond0
echo active-backup > /sys/class/net/bond0/bonding/mode
echo 100 > /sys/class/net/bond0/bonding/miimon
echo 1 > /sys/class/net/bond0/bonding/fail_over_mac
echo 0 > /sys/class/net/bond0/bonding/primary_reselect
echo +eth0 > /sys/class/net/bond0/bonding/slaves
echo +eth1 > /sys/class/net/bond0/bonding/slaves
echo eth0 > /sys/class/net/bond0/bonding/primary
echo 5 > /sys/class/net/bond0/bonding/num_grat_arp
echo 500 > /sys/class/net/bond0/bonding/peer_notif_delay
ip link set up dev bond0
case \$uts in
    H1)

        ip addr add 203.0.113.10/24 dev bond0
        ;;
    H2)
        ip addr add 203.0.113.11/24 dev bond0
        ;;
esac
EOF
