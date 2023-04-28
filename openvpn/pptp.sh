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
