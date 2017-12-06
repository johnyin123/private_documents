#!/bin/bash
set -u -e -o pipefail

NAT_SRV=10.32.151.250
NAT_PORT=60100
DEST_SRV=10.0.2.100
DEST_PORT=60022
TYPE=tcp

iptables -t nat -A PREROUTING -p ${TYPE} -d ${NAT_SRV} --dport ${NAT_PORT} -j DNAT --to-destination ${DEST_SRV}:${DEST_PORT}
iptables -t nat -A POSTROUTING -p ${TYPE} -d ${DEST_SRV} --dport ${DEST_PORT} -j SNAT --to-source ${NAT_SRV}


NAT_SRV=10.32.151.250
NAT_PORT=60101
DEST_SRV=10.0.2.101
DEST_PORT=60022
TYPE=tcp
iptables -t nat -A PREROUTING -p ${TYPE} -d ${NAT_SRV} --dport ${NAT_PORT} -j DNAT --to-destination ${DEST_SRV}:${DEST_PORT}
iptables -t nat -A POSTROUTING -p ${TYPE} -d ${DEST_SRV} --dport ${DEST_PORT} -j SNAT --to-source ${NAT_SRV}




NAT_SRV=10.32.151.250
NAT_PORT=60102
DEST_SRV=10.0.2.102
DEST_PORT=60022
TYPE=tcp
iptables -t nat -A PREROUTING -p ${TYPE} -d ${NAT_SRV} --dport ${NAT_PORT} -j DNAT --to-destination ${DEST_SRV}:${DEST_PORT}
iptables -t nat -A POSTROUTING -p ${TYPE} -d ${DEST_SRV} --dport ${DEST_PORT} -j SNAT --to-source ${NAT_SRV}



NAT_SRV=10.32.151.250
NAT_PORT=60103
DEST_SRV=10.0.2.103
DEST_PORT=60022
TYPE=tcp
iptables -t nat -A PREROUTING -p ${TYPE} -d ${NAT_SRV} --dport ${NAT_PORT} -j DNAT --to-destination ${DEST_SRV}:${DEST_PORT}
iptables -t nat -A POSTROUTING -p ${TYPE} -d ${DEST_SRV} --dport ${DEST_PORT} -j SNAT --to-source ${NAT_SRV}


