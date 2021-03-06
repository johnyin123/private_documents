#!/bin/bash
set -u -e -o pipefail

NAT_SRV=10.32.151.250
NAT_PORT=80
DEST_SRV=10.0.2.100
DEST_PORT=80
TYPE=tcp

iptables -t nat -A PREROUTING -p ${TYPE} --dst ${NAT_SRV} --dport ${NAT_PORT} -j DNAT --to-destination ${DEST_SRV}:${DEST_PORT}
iptables -t nat -A POSTROUTING -p ${TYPE} --dst ${DEST_SRV} --dport ${DEST_PORT} -j SNAT --to-source ${NAT_SRV}

#vnc port
NAT_SRV=10.32.151.250
NAT_PORT=6080
DEST_SRV=10.0.2.100
DEST_PORT=6080
TYPE=tcp

iptables -t nat -A PREROUTING -p ${TYPE} --dst ${NAT_SRV} --dport ${NAT_PORT} -j DNAT --to-destination ${DEST_SRV}:${DEST_PORT}
iptables -t nat -A POSTROUTING -p ${TYPE} --dst ${DEST_SRV} --dport ${DEST_PORT} -j SNAT --to-source ${NAT_SRV}


