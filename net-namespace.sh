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

ip netns exec ${NS} /bin/bash --rcfile <(echo "PS1=\"namespace ${NS}> \"")
#ip link delete v${ETH}
ip netns delete ${NS}
ip netns pids ${NS} 2>/dev/null && echo "pid run!!!" || echo "clean up"

# ip link add link br0 name br0.147 type vlan id 147


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

#1点对点. ip link add vxlan100 type vxlan id 100 dstport 4789 remote 192.168.8.101 local 192.168.8.100 dev enp0s8 
#1多  播. ip link add vxlan100 type vxlan id 100 group 239.1.1.1 dev enp0s8
#2. ip addr add 10.20.1.2(3)/24 dev vxlan100
#3. ip link set vxlan100 up

# add bridge
# ip link add vxlan100 type vxlan id 100 dstport 4789 remote 192.168.8.101 local 192.168.8.100 dev enp0s8 
# ip link add br0 type bridge
# ip link set vxlan100 master bridge
# ip link set vxlan100 up
# ip link set br0 up
# 模拟容器（vm）
# ip netns add container1
# # 创建 veth pair，并把一端加到网桥上
# ip link add veth0 type veth peer name veth1
# ip link set dev veth0 master br0
# ip link set dev veth0 up
# # 配置容器内部的网络和 IP
# ip link set dev veth1 netns container1
# ip netns exec container1 ip link set lo up
# ip netns exec container1 ip link set veth1 name eth0
# ip netns exec container1 ip addr add 10.20.1.2/24 dev eth0
# ip netns exec container1 ip link set eth0 up

