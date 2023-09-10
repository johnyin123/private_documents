#!/bin/bash

set -o errexit
#set -o xtrace

INTERFACE_NAME=${1:-enp5s0f1}

# Turn off irqbalance
sudo systemctl stop irqbalance.service
# Turn on irqbalance
#sudo systemctl start irqbalance.service

# Affinity CPU for hardware irq and softirq
# invoke script

# Config NIC Feature
# Jumbo Frames
sudo ip link set ${INTERFACE_NAME} mtu  9000

# enable tx/rx checksum offload
sudo ethtool -K ${INTERFACE_NAME} rx on tx on

# enable gro
sudo ethtool -K ${INTERFACE_NAME} gro on

########################  setup Queue  ########################

#Queue Number
sudo ethtool -L ${INTERFACE_NAME} combined 129
#Queue size
sudo ethtool -G ${INTERFACE_NAME} rx 4096 tx 4096

