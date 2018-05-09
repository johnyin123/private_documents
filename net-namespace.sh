NS=myns
ETH=eth0
ip netns add ${NS}
mkdir -p /etc/netns/${NS}
echo "ns3 conf" > /etc/netns/${NS}/resolv.conf
ip link add link ${ETH} dev v${ETH} type macvlan
ip link set v${ETH} netns ${NS}
#iw phy phy0 set netns name ${NS}

ip -n ${NS} addr add 10.0.2.101/24 dev v${ETH}
ip -n ${NS} link set v${ETH} up
ip -n ${NS} route add default via 10.0.2.1 dev v${ETH}

ip netns exec ${NS} bash
#ip link delete v${ETH}
ip netns delete ${NS}
ip netns pids ${NS} 2>/dev/null && echo "pid run!!!" || echo "clean up"



# echo 1 > /proc/sys/net/ipv4/conf/veth1/accept_local
# echo 1 > /proc/sys/net/ipv4/conf/veth0/accept_local
# echo 0 > /proc/sys/net/ipv4/conf/all/rp_filter
# echo 0 > /proc/sys/net/ipv4/conf/veth0/rp_filter
# echo 0 > /proc/sys/net/ipv4/conf/veth1/rp_filter



# ip link add v1 type veth peer name vp1
# ip link add v2 type veth peer name vp2
# brctl addbr br0
# brctl addif vp1 vp2
# ifconfig vp1 up
# ifconfig vp2 up
# sysctl -w net.ipv4.ip_forward=1
# ip netns add t1
# ip netns add t2
# ip link set v1 netns t1
# ip link set v2 netns t2
# ip netns exec t1 ifconfig v1 1.1.1.1/24
# ip netns exec t2 ifconfig v2 1.1.1.2/24
# ip netns exec t1 ping 1.1.1.2
# 
