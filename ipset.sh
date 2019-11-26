#!/usr/bin/env bash
ipset destroy china
#创建规则
ipset -N china hash:net
#清空旧的规则文件
####ipset脚本开始#####
#清空已存在的规则
rm cn.zone
#下载中国的IP文件
wget -P . http://www.ipdeny.com/ipblocks/data/countries/cn.zone
# 把IP文件的每个IP添加到IPSET规则里
for i in $(cat ./cn.zone ); do ipset -A china $i; done
#新建一个名为 V2RAY 的链
iptables -t nat -N V2RAY
#内部流量不转发给V2RAY直通
iptables -t nat -A V2RAY -d 0.0.0.0/8 -j RETURN
iptables -t nat -A V2RAY -d 10.0.0.0/8 -j RETURN
iptables -t nat -A V2RAY -d 127.0.0.0/8 -j RETURN
iptables -t nat -A V2RAY -d 169.254.0.0/16 -j RETURN
iptables -t nat -A V2RAY -d 172.16.0.0/12 -j RETURN
iptables -t nat -A V2RAY -d 192.168.0.0/16 -j RETURN
iptables -t nat -A V2RAY -d 224.0.0.0/4 -j RETURN
iptables -t nat -A V2RAY -d 240.0.0.0/4 -j RETURN
#直连中国的IP
iptables -t nat -A V2RAY -m set --match-set china dst -j RETURN
iptables -t nat -A V2RAY -p tcp -j REDIRECT --to-ports 12345
# 其余流量转发到 12345 端口（即 V2Ray）
iptables -t nat -A PREROUTING -p tcp -j V2RAY
# 对局域网其他设备进行透明代理
#iptables -t nat -A OUTPUT -p tcp -j V2RAY
# 对本机进行透明代理
