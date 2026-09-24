# add vlan1(trunk)
ip link set eth0 nomaster
ip link add link eth0 name eth0.1 type vlan id 1
ip link set eth0.1 up
ip link set eth0.1 master br-ext 
brctl show
# restore
ip link set eth0.1 nomaster
ip link delete eth0.1 
ip link set eth0 master br-ext 
brctl show
