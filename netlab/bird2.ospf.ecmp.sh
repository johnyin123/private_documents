apt -y install bird2

ECMP_NUM=2
NODE_IP=192.168.169.150
INTERFACE=eth0
NEIGHBOR_PWD=bgppassword
POD_CIDR=10.1.0.0/24
cat <<EOF > bird.conf
log syslog all;
debug protocols all;
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
        export all;
    };
    merge paths yes limit ${ECMP_NUM};
}
# Static IPv4 routes.
protocol static {
    ipv4;
    ${POD_CIDR:+route ${POD_CIDR} via \"lbdev0\";}
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
}
protocol ospf v2 uplink0 {
    # Cost一样的时候要不要启用负载均衡. ECMP默认是开的.
    ecmp yes;
    merge external yes;
    ipv4 {
        import all;
        # import where net !~ [10.65.2.0/24, 10.65.1.0/24];
        export all;
    };
    area 0.0.0.0 {
        interface "${INTERFACE}" {
            bfd yes;
            # 默认Cost是10, Cost越低选路优先. 注意这个Cost是单向向外的.
            cost 5;
            # authentication none|simple|cryptographic;
            authentication cryptographic;
            password "${NEIGHBOR_PWD}" {
                algorithm hmac sha256;
               # algorithm keyed md5;
            };
            gt
            # 链接类型定义. 由于是基于WireGuard的, 所以可以改成PTP网络, 会稍微减少消耗加快速度, 但实际用途不大.
            # type ptp;
        };
        interface "${INTERFACE}";
    };
}
EOF
birdcl show ospf neighbors
birdcl show ospf state
birdcl show route
