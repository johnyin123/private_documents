#!/usr/bin/env bash
# tcp port 1723

apt -y install pptpd

mtu=1490
mru=1490
dns=114.114.114.114
localip=192.168.166.1
remoteip="192.168.166.2-238,192.168.166.245"

sed --quiet -i -E \
    -e '/^\s*(localip\s|remoteip\s).*/!p' \
    -e "\$alocalip ${localip}" \
    -e "\$aremoteip ${remoteip}" \
    /etc/pptpd.conf

sed --quiet -i -E \
    -e '/^\s*(my-dns\s|nobsdcomp|noipx|mtu\s|mru\s).*/!p' \
    -e "\$ams-dns ${dns}" \
    -e "\$anobsdcomp" \
    -e "\$anoipx" \
    -e "\$amtu ${mtu}" \
    -e "\$amru ${mru}" \
    /etc/ppp/pptpd-options

cat <<EOF | tee -a /etc/ppp/chap-secrets
user1   *   password1   *
EOF

cat <<EOF
# pptpd-options
# The name of the local system for authentication purposes
name pptpd

# Refuse EAP, PAP, CHAP or MS-CHAP connections
# Accept ONLY MS-CHAPv2 or MPPE with 128-bit encryption
refuse-eap
refuse-pap
refuse-chap
refuse-mschap
require-mschap-v2
require-mppe
require-mppe-128

# Require authorization
auth

# Add entry to the ARP system table
proxyarp

# For the serial device to ensure exclusive access to the device
lock

# Disable BSD-Compress and Van Jacobson TCP/IP header compression
nobsdcomp
novj
novjccomp

# Disable logging
nolog
nologfd

# LCP echo-requests options
lcp-echo-interval 30
lcp-echo-failure 5

# MTU MRU options
mtu 1200
mru 1200

# DNS options for Windows clients
ms-dns 8.8.8.8
ms-dns 8.8.4.4
EOF
