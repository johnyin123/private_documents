apt -y install bird2
cat <<EOF > /etc/modules-load.d/dummy.conf
# Load dummy.ko at boot
dummy
EOF
cat <<EOF > /etc/modprobe.d/dummy.conf
install dummy /sbin/modprobe --ignore-install dummy; ip link add name lbdev0 type dummy
EOF
cat <<EOF > /etc/network/interfaces.d/lbdev0
allow-hotplug lbdev0
iface lbdev0 inet static
    address 10.1.0.1/24
# nmcli connection add type dummy ifname lbdev0 con-name lbdev0 ip4 10.1.0.1/24

EOF
ip link add name lbdev0 type dummy 
ifup lbdev0


NODE_IP=192.168.169.150
NODE_ASN=65000
INTERFACE=eth0
ECMP_NUM=2
NEIGHBOR_0_IP=192.168.169.151
NEIGHBOR_0_ASN=65001
NEIGHBOR_1_IP=192.168.169.152
NEIGHBOR_1_ASN=65002
NEIGHBOR_PWD=bgppassword

cat <<EOF > bird.conf
log syslog all;
router id ${NODE_IP};
protocol device {
    scan time 10;        # Scan interfaces every 10 seconds
}
# Disable automatically generating direct routes to all network interfaces.
protocol direct {
    disabled;         # Disable by default
}
# Forbid synchronizing BIRD routing tables with the OS kernel.
protocol kernel {
    ipv4 {                # Connect protocol to IPv4 table by channel
        import none;      # Import to table, default is import all
        export none;      # Export to protocol. default is export none
    };
    # Configure ECMP
    merge paths yes limit ${ECMP_NUM} ;
}
# Static IPv4 routes.
protocol static {
    ipv4;
}
# # Bidirectional Forwarding Detection (BFD) is a detection protocol designed to accelerate path failure detection.
protocol bfd {
    interface "${INTERFACE}" {
        min rx interval 100 ms;
        min tx interval 100 ms;
        idle tx interval 300 ms;
        multiplier 10;
        password "${NEIGHBOR_PWD}";
    };
    neighbor ${NEIGHBOR_0_IP};
    neighbor ${NEIGHBOR_1_IP};
}

# BGP peers
protocol bgp uplink0 {
    description "BGP uplink 0";
    local ${NODE_IP} as ${NODE_ASN};
    neighbor ${NEIGHBOR_0_IP} as ${NEIGHBOR_0_ASN};
    password "${NEIGHBOR_PWD}";
    bfd on;
    ipv4 {
        import all;
        export all;
        # import filter {reject;};
        # export filter {accept;};
    };
}

protocol bgp uplink1 {
    description "BGP uplink 1";
    local ${NODE_IP} as ${NODE_ASN};
    neighbor ${NEIGHBOR_1_IP} as ${NEIGHBOR_1_ASN};
    password "${NEIGHBOR_PWD}";
    bfd on;
    ipv4 {
        import all;
        export all;
        # import filter {reject;};
        # export filter {accept;};
    };
}
EOF


POD_CIDR=10.1.0.0/24
NODE_IP=192.168.169.152
NODE_ASN=65002
INTERFACE=eth0
ECMP_NUM=2
NEIGHBOR_0_IP=192.168.169.150
NEIGHBOR_0_ASN=65000
NEIGHBOR_PWD=bgppassword

cat <<EOF > bird.conf
log syslog all;
router id ${NODE_IP};
protocol device {
    scan time 10;        # Scan interfaces every 10 seconds
}
# Disable automatically generating direct routes to all network interfaces.
protocol direct {
    disabled;         # Disable by default
}
# Forbid synchronizing BIRD routing tables with the OS kernel.
protocol kernel {
    ipv4 {                # Connect protocol to IPv4 table by channel
        import none;      # Import to table, default is import all
        export none;      # Export to protocol. default is export none
    };
    # Configure ECMP
    merge paths yes limit ${ECMP_NUM} ;
}
# Static IPv4 routes.
protocol static {
    ipv4;
    route ${POD_CIDR} via "lbdev0";
}
# # Bidirectional Forwarding Detection (BFD) is a detection protocol designed to accelerate path failure detection.
protocol bfd {
    interface "${INTERFACE}" {
        min rx interval 100 ms;
        min tx interval 100 ms;
        idle tx interval 300 ms;
        multiplier 10;
        password "${NEIGHBOR_PWD}";
    };
    neighbor ${NEIGHBOR_0_IP};
}

# BGP peers
protocol bgp uplink0 {
    description "BGP uplink 0";
    local ${NODE_IP} as ${NODE_ASN};
    neighbor ${NEIGHBOR_0_IP} as ${NEIGHBOR_0_ASN};
    # multihop; # ... which is connected indirectly
    password "${NEIGHBOR_PWD}";
    bfd on;
    ipv4 {
        import filter {reject;};
        export filter {accept;};
    };
}
EOF
birdc show route
birdc show bfd sessions
birdc show protocols all uplink0
