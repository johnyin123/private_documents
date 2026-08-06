#!/usr/bin/env bash
export NAMESRV_ADDR=localhost:9876
export ROCKETMQ_HOME=/opt/rocketmq
mqadmin getNamesrvConfig
mqadmin consumerProgress
mqadmin topicList

{ uname -a;getsebool;ip a;free -h;cat /proc/cpuinfo;uptime;vmstat 1 10;iostat 1 10;ps -efwww;netstat -s;netstat -tunlpa;for p in $(pidof java);do echo $p;cat /proc/$p/limits; done;;journalctl --since "7 days ago";cat /proc/cmdline;sysctl -a; } &> $(hostname).log

# sysctl -a | grep net.netfilter.nf_conntrack_max
cat /proc/sys/net/netfilter/nf_conntrack_count
cat /proc/sys/net/netfilter/nf_conntrack_max
cat /proc/sys/net/netfilter/nf_conntrack_tcp_timeout_established
netstat -s

crictl ps | grep <pod-name>
crictl inspect <container-id> | grep pid

kubectl get pod -A -o wide | grep <pod-name>
for pid in $(pidof java); do echo "java pid = $pid";nsenter -n -t $pid ip a | grep 11.244.82.149/32; done
lsof -p <pid>
cat /proc/<pid>/limits
nsenter -t <pid> -n tcpdump
nsenter -t <pid> -m /bin/sh
