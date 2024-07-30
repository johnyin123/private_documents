#!/usr/bin/env bash

SKIP_ZONE=${SKIP_ZONE:-/etc/openvpn/skip.zone}

LOGFILE=""
# LOGFILE="-a log.txt"
log() { echo "$(tput setaf 141)$*$(tput sgr0)" >&2; }

default_route=$(ip -4 route show default | awk '{ print $3 }')
log "default route is: ${default_route}"
for ip in $(cat "${SKIP_ZONE}"); do
    log "skip zone ipaddr: ${ip}"
    ip route add ${ip} via ${default_route} || true
done
ip route add 10.0.0.0/8     via ${default_route} || true
ip route add 172.16.0.0/12  via ${default_route} || true
ip route add 192.168.0.0/16 via ${default_route} || true
ip route add 172.16.0.0/21  via 192.168.168.1 || true
ip route replace default via $5 dev $1 || true

exit 0
