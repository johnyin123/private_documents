#!/usr/bin/env bash
# If you do not have access to the application's source code,
# you can use mptcpize on Linux to automatically transform the TCP socket system calls into Multipath TCP sockets.
cat <<EOF
ip addr add 192.168.56.100/24 dev eth1 2> /dev/null
ip addr add 192.168.57.100/24 dev eth2 2> /dev/null
ip addr add 192.168.58.100/24 dev eth3 2> /dev/null

# Configure MPTCP
sysctl net.mptcp.enabled=1
ip mptcp limits set subflow 8
ip mptcp limits set add_addr_accepted 8
ip mptcp endpoint add 192.168.57.100 dev eth2 subflow
ip mptcp endpoint add 192.168.58.100 dev eth3 subflow
iperf3 -s
server: (Server1): mptcpize run iperf3 -s
EOF

cat <<EOF
ip addr add 192.168.56.101/24 dev eth1 2> /dev/null
ip addr add 192.168.57.101/24 dev eth2 2> /dev/null
ip addr add 192.168.58.101/24 dev eth3 2> /dev/null

# Configure MPTCP
sysctl net.mptcp.enabled=1
ip mptcp limits set subflow 8
ip mptcp endpoint add 192.168.57.101 dev eth2 signal
ip mptcp endpoint add 192.168.58.101 dev eth3 signal
iperf3 -c 192.168.56.100 -t 3
client (Server2): mptcpize run iperf3 -c 10.0.0.2
EOF

echo "Done setting up MPTCP..."

# #  Verify the connection and IP address limit:
# ip mptcp limit show
# # Verify the newly added endpoint:
# ip mptcp endpoint show
