# # Return the state of the route
# if [[ -z `vtysh -c "sh bgp $net_type unicast $1" | grep "Network not in table"` ]]; then
#     return 0
# else 
#     return 1
# fi
# QUAGGA_CONF="/etc/quagga/bgpd.conf"
# NETWORK_ROUTEMAP_CMD=`cat $QUAGGA_CONF | grep "$1" | head -1`
# vtysh -c "conf t" -c "router bgp $BGP_LOCAL_AS" -c "$NETWORK_ROUTEMAP_CMD"

