#!/bin/bash
set -u -e -o pipefail
# # redirect multiple port
# iptables -t nat -I PREROUTING -i eth0 -d <yourIP/32> -p udp -m multiport --dports 53,80,4444  -j REDIRECT --to-ports 15351
########################################
# # only enable port 60022 & ping(out/in) & access internet
# iptables -P INPUT DROP
# iptables -P FORWARD DROP
# iptables -P OUTPUT ACCEPT
# # Accept on localhost
# iptables -A INPUT -i lo -j ACCEPT
# iptables -A OUTPUT -o lo -j ACCEPT
# # only enable port 60022 & ping(out/in)
# iptables -A INPUT -p tcp -m tcp --dport 60022 -j ACCEPT
# # enable ping
# iptables -A INPUT -p icmp  -j ACCEPT
# # Allow established sessions to receive traffic
# iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
########################################
# # only spcial ip access port 60022
# iptables -A INPUT -p tcp --dport 60022 --source 192.168.0.0/24 -j ACCEPT
# iptables -A INPUT -p tcp --dport 60022 -j DROP
# # only spcial ip access sshd 60022
# cat <<EOF>/etc/hosts.allow
# sshd : 192.168.0.0/24
# sshd : 127.0.0.1
# EOF
# # OR
# # First remove default authentication methods:
# PasswordAuthentication no
# PubkeyAuthentication no
# # Then add desired authentication methods after a Match Address
# Match Address 127.0.0.*
# PubkeyAuthentication yes
########################################
# # Redirecting network traffic to a new IP
# sysctl net.ipv4.ip_forward=1
# iptables -t nat -A PREROUTING -p tcp --dport 1111 -j DNAT --to-destination 2.2.2.2:1111
# iptables -t nat -A POSTROUTING -j MASQUERADE
# # could only redirect the traffic from a specific source/network with, for a host only:
# iptables -t nat -A PREROUTING -s 192.168.1.1 -p tcp --dport 1111 -j DNAT --to-destination 2.2.2.2:1111
# # block ipaddress
# iptables -I INPUT -s xxx.xxx.xxx.xxx -j DROP
# # mirror eth0 stream to xx.xx.xx.xx (mirror/stream copy)
# iptables -t mangle -A PREROUTING -i eth0 -j TEE --gateway xx.xx.xx.xx
# iptables -A INPUT -m string --algo bm --string "test" -j DROP
# # deny port
# iptables -A FORWARD -p tcp -m multiport --dports 158,209,218,220,465,587,993,995,1109,60177,60179 -j REJECT --reject-with tcp-reset
# iptables -A FORWARD -p udp -m multiport --dports 158,209,218,220,465,587,993,995,1109,60177,60179 -j DROP
# # allow port
# iptables -A INPUT -p tcp -m tcp --dport ${start_port}:${stop_port} -j ACCEPT
# iptables -A INPUT -p udp -m udp --dport ${start_port}:${stop_port} -j ACCEPT
# # speed limit
# iptables -I FORWARD -d 10.0.0.$i/32 -j DROP
# iptables -I FORWARD -d 10.0.0.$i/32 -m limit --limit 100/sec -j ACCEPT
# # deny keyworks
# iptables -A FORWARD -m string --string "youtube.com" --algo bm -j DROP

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


====================================================================================================
echo 1:1 NAT, also known as full clone NAT
# 
# src:192.168.10.44        SNAT      src:192.168.100.44        DNAT     src:192.168.100.44
# dst:192.168.200.211--------------->dst:192.168.200.211--------------->dst:192.168.10.211
# 
# src:192.168.200.211      DNAT      src:192.168.100.211       SNAT     src:192.168.10.211
# dst:192.168.10.44  <---------------dst:192.168.200.44 <---------------dst:192.168.100.44
# 
# gwa# ip route
# 10.0.0.0/24 dev tun0 proto kernel scope link src 10.0.0.2
# 192.168.200.0/24 via 10.0.0.1 dev tun0
# 192.168.10.0/24 dev eth0 proto kernel scope link src 192.168.10.254
# # rewrite destination address on incoming traffic
iptables -t nat -A PREROUTING -s 192.168.200.0/24 -d 192.168.100.0/24 -i tun0 -j NETMAP --to 192.168.10.0/24
# rewrite source address on outgoing traffic
iptables -t nat -A POSTROUTING -s 192.168.10.0/24 -d 192.168.200.0/24 -o tun0 -j NETMAP --to 192.168.100.0/24

# gwb# ip route
# 10.0.0.0/24 dev tun0 proto kernel scope link src 10.0.0.1
# 192.168.100.0/24 via 10.0.0.2 dev tun0
# 192.168.10.0/24 dev eth0 proto kernel scope link src 192.168.10.254
# # same things, on gwb
iptables -t nat -A PREROUTING -s 192.168.100.0/24 -d 192.168.200.0/24 -i tun0 -j NETMAP --to 192.168.10.0/24
iptables -t nat -A POSTROUTING -s 192.168.10.0/24 -d 192.168.100.0/24 -o tun0 -j NETMAP --to 192.168.200.0/24


# Full Cone: 
# A full cone NAT is one where all requests from the same internal IP address and port are mapped to the same external IP address and port.
# Furthermore, any external host can send a packet to the internal host, by sending a packet to the mapped external address.
(192.168.2.170 is my "public" address and 10.0.0.1 is my "private" address
/-"Full Cone NAT", with the following rules:/
iptables -t nat -A POSTROUTING -o eth0 -j SNAT --to-source 192.168.2.170
iptables -t nat -A PREROUTING -i eth0 -j DNAT --to-destination 10.0.0.1
/-"Port Restricted Cone NAT", with just a single rule:/
iptables -t nat -A POSTROUTING -o eth0 -j SNAT --to-source 192.168.2.170/
