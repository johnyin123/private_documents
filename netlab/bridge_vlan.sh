#!/usr/bin/env bash
set -euo pipefail

create_bridge() {
    local nsname="$1"
    local ifname="$2"

    echo "Creating bridge ${nsname}/${ifname}"

    ip netns add ${nsname}
    ip netns exec ${nsname} ip link set lo up
    ip netns exec ${nsname} ip link add ${ifname} type bridge
    ip netns exec ${nsname} ip link set ${ifname} up

    # Enable VLAN filtering on bridge.
    ip netns exec ${nsname} ip link set ${ifname} type bridge vlan_filtering 1
}

create_end_host() {
    local host_nsname="$1"
    local peer1_ifname="$2a"
    local peer2_ifname="$2b"
    local vlan_vid="$3"
    local bridge_nsname="$4"
    local bridge_ifname="$5"

    echo "Creating end host ${host_nsname} connected to ${bridge_nsname}/${bridge_ifname} bridge (VLAN ${vlan_vid})"

    # Create end host network namespace.
    ip netns add ${host_nsname}
    ip netns exec ${host_nsname} ip link set lo up

    # Create a veth pair connecting end host and bridge namespaces.
    ip link add ${peer1_ifname} netns ${host_nsname} type veth peer \
                ${peer2_ifname} netns ${bridge_nsname}
    ip netns exec ${host_nsname} ip link set ${peer1_ifname} up
    ip netns exec ${bridge_nsname} ip link set ${peer2_ifname} up

    # Attach peer2 interface to the bridge.
    ip netns exec ${bridge_nsname} ip link set ${peer2_ifname} master ${bridge_ifname}

    # Put host into right VLAN
    ip netns exec ${bridge_nsname} bridge vlan del dev ${peer2_ifname} vid 1
    ip netns exec ${bridge_nsname} bridge vlan add dev ${peer2_ifname} vid ${vlan_vid} pvid ${vlan_vid}
}

# ---=== Scenario 1: simple VLAN on a bridge ===---

setup__simple_vlan() {
    create_bridge netns_br0 br0

    create_end_host netns_veth10 veth10 10 netns_br0 br0
    create_end_host netns_veth11 veth11 10 netns_br0 br0
    create_end_host netns_veth12 veth12 10 netns_br0 br0

    create_end_host netns_veth20 veth20 20 netns_br0 br0
    create_end_host netns_veth21 veth21 20 netns_br0 br0
    create_end_host netns_veth22 veth22 20 netns_br0 br0
}

teardown__simple_vlan() {
    ip netns delete netns_br0

    ip netns delete netns_veth10
    ip netns delete netns_veth11
    ip netns delete netns_veth12

    ip netns delete netns_veth20
    ip netns delete netns_veth21
    ip netns delete netns_veth22
}
#################################################################################
                         +---------------+
    +---------+  <---->  |               |  <---->  +---------+
    |         |  700.50  |    bridgens   |  700.50  |         |
    | access  +----------+p0           p1+----------+   vBNG  |
    |         |          |               | untagged |         |
    +---------+          |       p2      |          +---------+
    eth0.700.50          +-------+-------+   +-->   eth1.700.50
    110.0.0.1/8                  |           |      10.0.0.1/8
                                 |           v
                                 | untagged
                                 |
                            +----+----+
                            |         |
                            +  world  +
                            |         |
                            +---------+
                            eth2
                            210.0.0.1/8
#!/bin/bash

VLAN_PROTOCOL=${VLAN_PROTOCOL:-802.1ad}

# Set DEBUG=1 to see commands at stdout
if [ $DEBUG ]; then
    set -x
fi

# Cleanup function deletes all namespaces
clean() {
    for ns in bridgens access vBNG world; do
        ip netns del $ns
    done
}

# Cleanup when exiting the script (Crtl-d in bridgens namespace)
trap clean EXIT

# Add namespaces
ip netns add bridgens
ip netns add access
ip netns add vBNG
ip netns add world

# Create vlan-aware bridge
ip netns exec bridgens ip link add bridge type bridge vlan_filtering 1 vlan_protocol $VLAN_PROTOCOL
ip netns exec bridgens ip link set bridge up

# Create veth pairs and plug bridge ports into the brigde
for i in {0..2}; do
    ip link add eth${i} type veth peer name p${i}
    ip link set p${i} netns bridgens
    ip netns exec bridgens ip link set p${i} master bridge
    ip netns exec bridgens ip link set p${i} up
done

# Move other ports into the namespaces
ip link set eth0 netns access
ip netns exec access ip link set eth0 up
ip link set eth1 netns vBNG
ip netns exec vBNG ip link set eth1 up
ip link set eth2 netns world
ip netns exec world ip link set eth2 up

# Setup QinQ interfaces
ip netns exec access ip link add link eth0 eth0.700\
        type vlan proto $VLAN_PROTOCOL id 700
ip netns exec access ip link add link eth0.700 eth0.700.50\
        type vlan proto 802.1Q id 50
ip netns exec access ip link set eth0.700 up
ip netns exec access ip link set eth0.700.50 up

ip netns exec vBNG ip link add link eth1 eth1.700\
        type vlan proto $VLAN_PROTOCOL id 700
ip netns exec vBNG ip link add link eth1.700 eth1.700.50\
        type vlan proto 802.1Q id 50
ip netns exec vBNG ip link set eth1.700 up
ip netns exec vBNG ip link set eth1.700.50 up

# Add ip addresses and routes
ip netns exec access ip address add 110.0.0.1/8 dev eth0.700.50
ip netns exec access ip route add default dev eth0.700.50

ip netns exec vBNG ip address add 10.0.0.1/8 dev eth1.700.50
ip netns exec vBNG ip route add default dev eth1
ip netns exec vBNG ip route add 110.0.0.0/8 dev eth1.700.50

ip netns exec world ip address add 210.0.0.1/8 dev eth2
ip netns exec world ip route add default dev eth2

# Setup VLAN filtering
# Drop untagged traffic from access
ip netns exec bridgens bridge vlan del vid 1 dev p0

# Allow S-Tag 700 between access and vBNG
ip netns exec bridgens bridge vlan add dev p0 vid 700
ip netns exec bridgens bridge vlan add dev p1 vid 700

# Allow untagged traffic between vBNG and world
ip netns exec bridgens bridge vlan add dev p1 vid 701 pvid 701 untagged
ip netns exec bridgens bridge vlan add dev p2 vid 701 pvid 701 untagged

# Enter netns bridgens
ip netns exec bridgens /bin/bash
