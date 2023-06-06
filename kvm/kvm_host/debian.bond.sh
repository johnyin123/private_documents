#!/usr/bin/env bash
cat <<EOF
# # bond need ifenslave
# apt -y install ifenslave
auto eth0
auto eth1
auto bond0
iface bond0 inet manual
    bond-slaves eth0 eth1
    bond-mode 802.3ad
    # bond-mode active-backup
    # bond-miimon 100
    # bond-downdelay 200
    # bond-updelay 200
    # bond-lacp-rate 1
    # bond-xmit-hash-policy layer2+3
auto br-ext
iface br-ext inet static
    bridge_ports bond0
    bridge_maxwait 0
    bridge_stp off
    # hwaddress 00:XX:XX:XX:XX:XX
    # address ip/mask
    # gateway gw
EOF
