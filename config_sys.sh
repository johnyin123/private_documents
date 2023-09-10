#!/bin/bash

set -o errexit
#set -o xtrace

# Config Linux Network device subsystem
# total available budge of each NAPI
sudo sysctl -w net.core.netdev_budget=6000
sudo sysctl -w net.core.netdev_budget_usecs=6000


#Adjusting backlog for PRS or netif_rx
sudo sysctl -w net.core.netdev_max_backlog=3000
sudo sysctl -w net.core.dev_weight=600

# Protocol layer
sudo sysctl -w  net.ipv4.ip_early_demux=0

# TCP buffer
# receive buffer {"min default max"}
sudo sysctl -w net.ipv4.tcp_rmem='4096 87380 67108864'
# send buffer
sudo sysctl -w net.ipv4.tcp_rmem='4096 65536 67108864'

# UDP buffer
sudo sysctl -w net.ipv4.udp_rmem_min=16384
sudo sysctl -w net.ipv4.udp_wmem_min=16384









