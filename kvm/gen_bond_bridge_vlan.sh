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
BONDING_OPTS="mode=802.3ad downdelay=0 updelay=0 miimon=100 xmit_hash_policy=layer3+4"
# BONDING_OPTS="mode=802.3ad miimon=100 xmit_hash_policy=layer3+4"
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
cat <<'EOF'
IPADDR=""
PREFIX=""
GATEWAY=
# echo layer2+3 > /sys/class/net/bond0/bonding/xmit_hash_policy 
# root@sykvm16:~$ethtool bond0
	Speed: 2000Mb/s
	Duplex: Full

# socat TCP-LISTEN:6666,fork TCP:192.168.1.1:6666,sourceport=srcport
# google-chrome --explicitly-allowed-ports=6666
# juniper EX4200 802.3ad  xmit_hash_policy=layer3+4
configure
edit system services
set web-management http port 8888
commit

EX4200T-VC-01-133.10> show configuration | display set | grep ge-2/0/44
set interfaces ge-2/0/44 disable
set interfaces ge-2/0/44 ether-options 802.3ad ae5
set interfaces ge-3/0/44 disable
set interfaces ge-3/0/44 ether-options 802.3ad ae5
set interfaces ae5 aggregated-ether-options lacp active
set interfaces ae5 unit 0 family ethernet-switching port-mode trunk
set interfaces ae5 unit 0 family ethernet-switching vlan members all
#set interfaces ae0 unit 0 family inet address 172.16.16.1/30 (三层)

#ospf
set routing-options router-id 1.1.1.1
set protocols ospf area 0.0.0.0 area-range 192.168.167.0/24
set protocols ospf area 0.0.0.0 interface ae0.0
set protocols ospf area 0.0.0.0 interface ae0.0 authentication md5 1 key keypassword
lab# show protocols ospf
area 0.0.0.0 {
    area-range 192.168.167.0/24;
    interface ae0.0 {
        authentication {
            md5 1 key "$9$YUoZjmPQF/t.P5F/9B1Ndb2Zj6/t01hk."; ## SECRET-DATA
        }
    }
}

H3C:
# 创建二层聚合接口1，并配置该接口为动态聚合模式。
interface bridge-aggregation 1
link-aggregation mode dynamic
# 配置二层聚合接口1为Trunk端口，并允许VLAN 10和20的报文通过。
interface bridge-aggregation 1
port link-type trunk
port trunk permit vlan 10 20
quit
# 配置全局按照报文的源MAC地址和目的MAC地址进行聚合负载分担。
link-aggregation load-sharing mode source-mac destination-mac
display link-aggregation summary
display link-aggregation load-sharing mode
# 分别将端口GigabitEthernet1/0/1,GigabitEthernet1/0/2加入到聚合组1中。
interface gigabitethernet 1/0/1
port link-aggregation group 1
quit
interface gigabitethernet 1/0/2
port link-aggregation group 1
quit
EOF

