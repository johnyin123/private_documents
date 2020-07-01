# enp2s0 – regular network interface, carries inter-host LAN traffic
# ${BR_MGMT_INTERFACE} – carries br-mgmt bridge for LXC container communication
# ${BR_VLAN_INTERFACE} – carries br-vlan bridge for VM public network connectivity
# ${BR_VXLAN_INTERFACE} – carries br-vxlan bridge for VM private network connectivity

BR_MGMT_INTERFACE=eth0
BR_MGMT_VLANID=10
BR_VLAN_INTERFACE=eth1
BR_VXLAN_INTERFACE=eth2
BR_VXLAN_VLANID=11



yum -y install systemd-networkd
systemctl disable network
systemctl disable NetworkManager
systemctl enable systemd-networkd
systemctl enable systemd-resolved
systemctl start systemd-resolved
rm -f /etc/resolv.conf
ln -s /run/systemd/resolve/resolv.conf /etc/resolv.conf

echo "LAN interface"
cat <<EOF >/etc/systemd/network/enp2s0.network
[Match]
Name=enp2s0
[Network]
Address=192.168.250.21/24
Gateway=192.168.250.1
DNS=192.168.250.1
DNS=8.8.8.8
DNS=8.8.4.4
IPForward=yes
EOF

echo "Management bridge"
cat <<EOF >/etc/systemd/network/br-mgmt.netdev
[NetDev]
Name=br-mgmt
Kind=bridge
EOF

cat <<EOF >/etc/systemd/network/br-mgmt.network
[Match]
Name=br-mgmt

[Network]
Address=172.29.236.21/22
EOF

cat <<EOF >etc/systemd/network/vlan${BR_MGMT_VLANID}.netdev
[NetDev]
Name=vlan${BR_MGMT_VLANID}
Kind=vlan

[VLAN]
Id=${BR_MGMT_VLANID}
EOF

cat <<EOF >/etc/systemd/network/vlan${BR_MGMT_VLANID}.network
[Match]
Name=vlan${BR_MGMT_VLANID}

[Network]
Bridge=br-mgmt
EOF

cat <<EOF >/etc/systemd/network/${BR_MGMT_INTERFACE}.network
[Match]
Name=${BR_MGMT_INTERFACE}

[Network]
VLAN=vlan${BR_MGMT_VLANID}
EOF

echo "Public instance"
echo "My router offers up a few different VLANs for OpenStack instances to use for their public networks. We start by creating a br-vlan network device and its configuration:"

cat <<EOF>/etc/systemd/network/br-vlan.netdev
[NetDev]
Name=br-vlan
Kind=bridge
EOF

cat <<EOF>/etc/systemd/network/br-vlan.network
[Match]
Name=br-vlan

[Network]
DHCP=no
EOF
cat <<EOF>/etc/systemd/network/${BR_VLAN_INTERFACE}.network
[Match]
Name=${BR_VLAN_INTERFACE}

[Network]
Bridge=br-vlan
EOF

echo "VXLAN private instance connectivity"

cat <<EOF>/etc/systemd/network/br-vxlan.netdev
[NetDev]
Name=br-vxlan
Kind=bridge
EOF
cat <<EOF>/etc/systemd/network/br-vxlan.network
[Match]
Name=br-vxlan

[Network]
Address=172.29.240.21/22
EOF
echo "My VXLAN traffic runs over VLAN ${BR_VXLAN_VLANID}, so we need to define that VLAN interface:"
cat <<EOF>/etc/systemd/network/vlan${BR_VXLAN_VLANID}.netdev
[NetDev]
Name=vlan${BR_VXLAN_VLANID}
Kind=vlan

[VLAN]
Id=${BR_VXLAN_VLANID}
EOF
cat <<EOF>/etc/systemd/network/vlan${BR_VXLAN_VLANID}.network
[Match]
Name=vlan${BR_VXLAN_VLANID}

[Network]
Bridge=br-vxlan
EOF
echo "We can hook this VLAN interface into the ${BR_VXLAN_INTERFACE} interface now:"
cat <<EOF>/etc/systemd/network/${BR_VXLAN_INTERFACE}.network
[Match]
Name=${BR_VXLAN_INTERFACE}

[Network]
VLAN=vlan${BR_VXLAN_VLANID}
EOF

echo "Checking our work"
networkctl
echo "You should have configured in the SETUP column for all of the interfaces you created. Some interfaces will show as degraded because they are missing an IP address (which is intentional for most of these interfaces)."
