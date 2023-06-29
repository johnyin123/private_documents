ip link add name bond0 type bond mode active-backup/802.3ad
ip link set eth0 down
ip link set master bond0 dev eth0
ip link set up dev bond0
ip link add name bond0.3024 link bond0 type vlan id 3024

