GRE 技术本身还是存在一些不足之处：
（1）Tunnel 的数量问题
    GRE 是一种点对点（point to point）标准。Neutron 中，所有计算和网络节点之间都会建立 GRE Tunnel。当节点不多的时候，这种组网方法没什么问题。但是，当你在你的很大的数据中心中有 40000 个节点的时候，又会是怎样一种情形呢？使用标准 GRE的话，将会有 780 millions 个 tunnels。
（2）扩大的广播域
   GRE 不支持组播，因此一个网络（同一个 GRE Tunnel ID）中的一个虚机发出一个广播帧后，GRE 会将其广播到所有与该节点有隧道连接的节点。
（3）GRE 封装的IP包的过滤和负载均衡问题
    目前还是有很多的防火墙和三层网络设备无法解析 GRE Header，因此它们无法对 GRE 封装包做合适的过滤和负载均衡。 

#办公网路由器（linux服务器实现）：局域网IP 192.168.1.254，公网 IP 180.1.1.1 配置
#!/bin/bash
modprobe ip_gre
ip tunnel add office mode gre remote 110.2.2.2 local 180.1.1.1 ttl 255 #使用公网 IP 建立 tunnel 名字叫 ”office“ 的 device，使用gre mode。指定远端的ip是110.2.2.2，本地ip是180.1.1.1。这里为了提升安全性，你可以配置iptables，公网ip只接收来自110.2.2.2的包，其他的都drop掉。
ip link set office up #启动device office
ip link set office up mtu 1500 #设置 mtu 为1500
ip addr add 192.192.192.2/24 dev office #为 office 添加ip 192.192.192.2
echo 1 > /proc/sys/net/ipv4/ip_forward #让服务器支持转发
ip route add 10.1.1.0/24 dev office #添加路由，含义是：到10.1.1.0/24的包，由office设备负责转发
iptables -t nat -A POSTROUTING -d 10.1.1.0/24 -j SNAT --to 192.192.192.2#否则 192.168.1.x 等机器访问 10.1.1.x网段不通

#IDC路由器（linux服务器实现）：局域网 ip：10.1.1.1，公网ip 110.2.2.2配置
#!/bin/bash
modprobe ip_gre
ip tunnel add office mode gre remote 180.1.1.1 local 110.2.2.2 ttl 255
ip link set office up
ip link set office up mtu 1500
ip addr add 192.192.192.1/24 dev office #为office添加 ip 192.192.192.1
echo 1 > /proc/sys/net/ipv4/ip_forward
ip route add 192.168.1.0/24 dev office
iptables -t nat -A POSTROUTING -s 192.192.192.2 -d 10.1.0.0/16 -j SNAT --to 10.1.1.1 #否则192.168.1.X等机器访问10.1.1.x网段不通
iptables -A FORWARD -s 192.192.192.2 -m state --state NEW -m tcp -p tcp --dport 3306 -j DROP #禁止直接访问线上的3306，防止内网被破

