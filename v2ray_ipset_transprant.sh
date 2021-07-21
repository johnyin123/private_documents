#!/usr/bin/env bash
:<<"EOF"
Preparation
Someone who's capable to solve problems in their own situations;
A VPS that has installed V2Ray, the IP of which we assume to be 110.231.43.65;
A device with iptables, root permission, and Linux system, the IP of which we assume to be 192.168.1.22, with V2Ray running as a client. This device can be a router, a development board, a personal computer, a virtual machine, or an Android device, referred to a gateway here. We do not recommend using the MT7620 system to deploy as a transparent proxy, due to its limited performance, and the fact that many of their firmware does not have access to FPU. If you are not willing to purchase a new device specifically for transparent proxy, you can, however, create a virtual machine on your PC (e.g. VirtualBox, Hyper-V, and KVM). Note that on the hypervisor, you should set virtual machines' network in bridge mode.
#Procedures
The setup steps are as follows, assuming you are logged in with root.

Enable IP forwarding on the gateway device: Add new line net.ipv4.ip_forward=1 to the /etc/sysctl.conf file and execute :
sysctl -p
The gateway device sets to a static IP, which is in the same network segment as the LAN port of the router. The default gateway should be the IP address of the router. Enter the router management page and go to the DHCP setting, set the default gateway address at the IP address of the gateway device, as 192.168.1.22 in this example. Or you can set your computer, phone and other devices their default gateway individually (to 192.168.1.22), and reconnect your devices to the router to see if they can connect to the Internet. (It's normal that the device can not yet bypass the GFW at this time). If the devices have no access to the internet at all, you'll have to solve this issue first before going any further. Otherwise, you'll only waste your time following the next steps. The gateway device is set to a static IP so that to its IP does not change after a reboot. The default gateway on the router is set to the gateway IP address so that the router routes all data sent from the LAN devices connected to it to the gateway device, who then forwards the traffic using V2Ray.

Install the latest version of V2Ray on the server (your VPS) and the gateway. (If you don't how then you need to follow the previous tutorials. Note that GFW likes to intercept the GitHub releases traffic, and it can cause failure to install V2Ray using the installation script. It is hence advised to download the V2Ray package manually, and then use the installation script with the "-local" parameter.) Configure your config file accordingly. When you are sure that the V2Ray is working properly, at the gateway, execute curl -x socks5://127.0.0.1:1080 google.com to test whether your setup can bypass GFW. (Here socks5 refers to the inbound protocol and 1080 is the inbound port ) . If the output is something like the following, you are good. Otherwise, there's something wrong with your setup and you need to recheck what you have missed.

<HTML><HEAD><meta http-equiv="content-type" content="text/html;charset=utf-8">
<TITLE>301 Moved</TITLE></HEAD><BODY>
<H1>301 Moved</H1>
The document has moved
<A HREF="http://www.google.com/">here</A>.
</BODY></HTML>
In the configuration file of the gateway, add the inbound configuration of the dokodemo-door protocol, enable sniffing, and add also SO_MARK to all outbound streamSettings. The configuration should be as follows (the ... represents configuration in a standard client):
 {
  "routing": {...},
  "inbounds": [
    {
      ...
    },
    {
      "port": 12345, // The open port
      "protocol": "dokodemo-door",
      "settings": {
        "network": "tcp,udp",
        "followRedirect": true // Need to be set as true to accept traffic from iptables
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
  ],
  "outbounds": [
    {
      ...
      "streamSettings": {
        ...
        "sockopt": {
          "mark": 255  // Here is SO_MARK，used for iptables to recognise. Each outbound needs to configure; you can use other value other than 255 but it needs to be consistant as in iptables rules; if there are multiple outbounds, it is recommended that you set all SO_MARK value the same for all outbounds.
        }
      }
    }
    ...
  ]
}
Set iptable rules for TCP for the transparent proxy device: (after # are comments):
iptables -t nat -N V2RAY # Create a new chain called V2RAY
iptables -t nat -A V2RAY -d 192.168.0.0/16 -j RETURN # Direct connection 192.168.0.0/16
iptables -t nat -A V2RAY -p tcp -j RETURN -m mark --mark 0xff # Directly connect SO_MARK to 0xff traffic (0xff is a hexadecimal number, numerically equivalent to 255), the purpose of this rule is to avoid proxy loopback with local (gateway) traffic
iptables -t nat -A V2RAY -p tcp -j REDIRECT --to-ports 12345 # The rest of the traffic is forwarded to port 12345 (ie V2Ray)
iptables -t nat -A PREROUTING -p tcp -j V2RAY # Transparent proxy for other LAN devices
iptables -t nat -A OUTPUT -p tcp -j V2RAY # Transparent proxy for this machine
Then set the iptables rule of UDP traffic for the transparent proxy device:

ip rule add fwmark 1 table 100
ip route add local 0.0.0.0/0 dev lo table 100
iptables -t mangle -N V2RAY_MASK
iptables -t mangle -A V2RAY_MASK -d 192.168.0.0/16 -j RETURN
iptables -t mangle -A V2RAY_MASK -p udp -j TPROXY --on-port 12345 --tproxy-mark 1
iptables -t mangle -A PREROUTING -p udp -j V2RAY_MASK
Try visiting a blocked website directly using your computer/phone that are connected under the same LAN with your configured transparent proxy device. You should not be blocked by now.

You might need a script or anything (such as iptables-persistent) that can automatically load the above iptable rules after the transparent proxy device reboots. Otherwise, the iptables will be lost after it reboots.

#Notes
WIth the above setup, when you visit a normally blocked site, the gateway will still use the system DNS for the query, except that the returned result is polluted. But the sniffing provided by V2Ray can learn the domain name (of the polluted website) from the traffic and send it for your VPS to resolve, returning the correct result. This is to say that every time you visit a blocked website by the GFW, despite the fact that you can bypass the censorship with V2Ray, your system DNS provider (who pollutes your DNS) knows that you have tried to visit the blocked website. Hence you need to be aware of the possibility that they could actively collect such data.
V2Ray sniffing currently only extracts domain names from TLS and HTTP traffic. If there is traffic that is neither type of the two, be cautious of using sniffing to solve DNS pollution.
There might be some problems with the transparent proxy rule for UDP traffic. It will be thankful if you would like to give us any feedback regarding those rules. If your online activities involve simply web surfing or watching videos, TCP rules only might be sufficient without the need of configuring UDP rules.
Due to the limit of VMESS protocol, V2Ray transparent proxy would not offer satisfactory online gaming performance.
Only TCP/UDP traffic can be proxied via V2Ray, so it does not work with ICMP packets. Therefore, the transparent proxy does not support ping/mtr which is based on ICMP. However, tcping or hping3 works as they use TCP instead of ICMP.
There are some transparent proxy tutorials on the internet that set iptables rules for private addresses like RETURN 127.0.0.0/8, but we suggest they should be placed in the V2Ray routing rules for performance reason.

EOF
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
