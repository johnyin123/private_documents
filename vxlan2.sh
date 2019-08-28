#!/bin/bash
NODE=${NODES:-1}

declare -A PEERS
#PEERS[1]=59.46.220.174
PEERS=([1]=59.46.220.174 [2]=119.254.158.141 [3]=59.46.22.56)
VXMAC=9e:08:90:00:00
VXIP=172.16.16


ip link add vxlan100 type vxlan id 100 dstport 50000 nolearning proxy
ip link set vxlan100 address ${VXMAC}:0${NODE}
ip addr add ${VXIP}.${NODE}/24 dev vxlan100
ip link set vxlan100 up

for peer in ${!PEERS[@]}
do
    if [[ ${peer} -eq ${NODE} ]]
    then
        continue
    fi
    printf "%-18s%-18s%s\n" ${VXIP}.${peer} ${VXMAC}:0${peer} ${PEERS[$peer]}
    bridge fdb append  ${VXMAC}:0${peer} dev vxlan100 dst ${PEERS[$peer]}
    ip neigh add ${VXIP}.${peer} lladdr ${VXMAC}:0${peer} dev vxlan100
done
# ip r a 10.4.30.0/23 via ${VXIP}.2 dev vxlan100
sysctl net.ipv4.ip_forward=1
iptables -t nat -D POSTROUTING  -j MASQUERADE || true
iptables -t nat -A POSTROUTING  -j MASQUERADE || true

