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
