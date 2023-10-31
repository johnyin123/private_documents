#!/usr/bin/env bash
del_forwarding_rules() {
    host_port=$1
    dest_ip=$2
    dest_port=$3
    iptables -D PREROUTING  -t nat -p tcp --dport $host_port -j DNAT --to $dest_ip:$dest_port
    iptables -D FORWARD  -p tcp -d $dest_ip --dport $dest_port -j ACCEPT
}

set_forwarding_rules() {
    host_port=$1
    dest_ip=$2
    dest_port=$3
    iptables -I PREROUTING 1 -t nat -p tcp --dport $host_port -j DNAT --to $dest_ip:$dest_port
    iptables -I FORWARD 1 -p tcp -d $dest_ip --dport $dest_port -j ACCEPT
}

if [[ -n "$1" ]]; then
    IFS=":" read host_port dest_ip dest_port <<< $1
    echo "host_port=$host_port dest_ip=$dest_ip dest_port=$dest_port"
    del_forwarding_rules $host_port $dest_ip $dest_port
    set_forwarding_rules $host_port $dest_ip $dest_port
    exit 0
else
    echo "Usage $0: host_port:dest_ip:dest_port"
    echo "E.g. $0 9000:192.168.122.50:80 will setup forwarding from host's port 9000 to port 80 on internal ip 192.168.122.50"
fi
