# # Return the state of the route
# if [[ -z `vtysh -c "sh bgp $net_type unicast $1" | grep "Network not in table"` ]]; then
#     return 0
# else 
#     return 1
# fi
# QUAGGA_CONF="/etc/quagga/bgpd.conf"
# NETWORK_ROUTEMAP_CMD=`cat $QUAGGA_CONF | grep "$1" | head -1`
# vtysh -c "conf t" -c "router bgp $BGP_LOCAL_AS" -c "$NETWORK_ROUTEMAP_CMD"
touch /etc/quagga/ospfd.conf
chown quagga:quagga /etc/quagga/ospfd.conf
chmod 640 /etc/quagga/ospfd.conf
/sbin/ospfd

vtysh  -c "conf t" -c "interface eth0" -c "ip ospf authentication message-digest" -c "ip ospf message-digest-key 1 md5 pass4OSPF"
vtysh  -c "conf t" -c  "router ospf" -c "ospf router-id 1.1.1.1"
vtysh  -c "write"
vtysh  -c "conf t" -c  "router ospf" -c "log-adjacency-changes"
cat /etc/quagga/ospfd.conf
