#!/usr/bin/env bash
cat <<EOF
table inet myblackhole {
	set blacklist {
		type ipv4_addr
		flags dynamic,timeout
		timeout 5m
	}

	chain input {
		type filter hook input priority filter; policy accept;
		ct state established,related accept
		ip saddr @blacklist counter packets 0 bytes 0 reject with icmp port-unreachable
	}
}
EOF
TBL="inet myblackhole"
PRI=-1
nft add chain ${TBL} trace_chain { type filter hook prerouting priority ${PRI}\; }
nft add rule ${TBL} trace_chain meta nftrace set 1

nft monitor trace

nft delete chain ${TBL} trace_chain
