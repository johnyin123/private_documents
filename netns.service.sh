#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit

echo "/lib/systemd/system"
echo "/etc/systemd/system"
echo "systemd netns, DNS NOT WORK, ip netns is ok"
svc_file=netns@.service
[ -e "${svc_file}" ] || cat <<'EOF' | grep -v "^\s*#" > ${svc_file}
[Unit]
Description=Named network namespace %i
After=network.target
StopWhenUnneeded=true
[Service]
Type=oneshot
PrivateNetwork=yes
RemainAfterExit=yes
# # /bin/touch: 无法 touch '/var/run/netns/aws
# ExecStart=/bin/touch /var/run/netns/%i
# ExecStart=/bin/mount --bind /proc/self/ns/net /var/run/netns/%i
ExecStart=/bin/sh -c '/sbin/ip netns attach %i $$$$'
ExecStop=/sbin/ip netns delete %i
EOF
echo "cp ${svc_file} /etc/systemd/system/"
############################################################
svc_file=bridge-netns@.service
[ -e "${svc_file}" ] || cat <<'EOF' > ${svc_file}
[Unit]
Requires=netns@%i.service
After=netns@%i.service
[Service]
Type=oneshot
RemainAfterExit=yes
Environment=DNS=""
EnvironmentFile=/etc/%i.conf
ExecStart=/sbin/ip link add %i_eth0 type veth peer name %i_eth1
ExecStart=/sbin/ip link set %i_eth0 netns %i name eth0 up
ExecStart=/sbin/ip link set %i_eth1 master ${BRIDGE}
ExecStart=/sbin/ip link set dev %i_eth1 up
ExecStart=/sbin/ip netns exec %i /sbin/ip address add ${ADDRESS} dev eth0
ExecStart=/sbin/ip netns exec %i /sbin/ip route add default via ${GATEWAY} dev eth0
ExecStart=-/bin/mkdir -p /etc/netns/%i
ExecStart=-/bin/sh -c "[ -z '${DNS}' ] || echo 'nameserver ${DNS}' > /etc/netns/%i/resolv.conf"
ExecStart=-/bin/sh -c "cat /etc/hosts > /etc/netns/%i/hosts"
ExecStop=-/bin/rm -fr /etc/netns/%i/
ExecStop=-/sbin/ip link set %i_eth1 promisc off
ExecStop=-/sbin/ip link set %i_eth1 down
ExecStop=-/sbin/ip link set dev %i_eth1 nomaster
ExecStop=-/sbin/ip link delete %i_eth1
[Install]
WantedBy=multi-user.target
EOF
echo "cp ${svc_file} /etc/systemd/system/"
############################################################

gen_svc_tpl() {
    local srv_name="${1}"
    local bridge="${2}"
    local ipaddr="${3}"
    local gateway="${4}"
    local dns="${5:-}"
    mkdir -p ${srv_name}/etc/systemd/system
    mkdir -p ${srv_name}/etc/${srv_name}
    ############################################################
    cat <<EOF > ${srv_name}/etc/${srv_name}.conf
BRIDGE="${bridge}"
ADDRESS="${ipaddr}"
GATEWAY="${gateway}"
${dns:+DNS=\"${dns}\"}
EOF
    ############################################################
    cat <<EOF > ${srv_name}/etc/systemd/system/${srv_name}.service
[Unit]
# systemctl stop bridge-netns@${srv_name}.service
Description=${srv_name} in netns
Wants=network-online.target
Requires=netns@${srv_name}.service bridge-netns@${srv_name}.service
After=netns@${srv_name}.service bridge-netns@${srv_name}.service

[Service]
Type=simple
# keep, else shutdown svc
RemainAfterExit=yes
ExecStart=ip netns exec ${srv_name} /bin/bash /etc/${srv_name}/startup.sh
ExecStop=-ip netns exec ${srv_name} /bin/bash /etc/${srv_name}/teardown.sh
[Install]
WantedBy=multi-user.target
EOF
    ############################################################
    cat <<EOF > ${srv_name}/etc/${srv_name}/teardown.sh
#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
echo "stop"
# # systemctl cmd can not run in this script, if want remove netns, manual exec:
# systemctl stop bridge-netns@${srv_name}.service
EOF
    ############################################################
    cat <<EOF > ${srv_name}/etc/${srv_name}/startup.sh
#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
cat <<EO_HOST > /etc/hosts
127.0.0.1      localhost
EO_HOST
EOF
}
############################################################
srv_name="ns-ali"
bridge="br-int"
ipaddr="192.168.167.251/24"
gateway="192.168.167.1"
dns="114.114.114.114"
gen_svc_tpl "${srv_name}" "${bridge}" "${ipaddr}" "${gateway}" "${dns}"
cat <<EOF > ${srv_name}/etc/${srv_name}/startup.sh
#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
/usr/sbin/ip route add 39.104.207.142 via 192.168.167.1 || true
/usr/sbin/ip route add 10.0.0.0/8 via 192.168.167.1 || true
/usr/sbin/ip route add 172.16.0.0/12 via 192.168.167.1 || true
/usr/sbin/ip route add 192.168.0.0/16 via 192.168.167.1 || true
cat <<EO_HOST > /etc/hosts
127.0.0.1      localhost
39.104.207.142 tunl.wgserver.org
EO_HOST
wg-quick up wgali
/usr/sbin/ip route replace default via 192.168.32.1 || true
sysctl -w net.ipv4.ip_forward=1
cat<<EO_NAT | nft -f /dev/stdin
flush ruleset
table ip nat {
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        ip saddr 192.168.167.0/24 ip daddr != 192.168.167.0/24 counter masquerade
    }
}
EO_NAT
EOF
cat <<EOF > ${srv_name}/etc/${srv_name}/teardown.sh
#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
wg-quick down wgali
EOF
echo "(cd ${srv_name} && rsync -avP * /)"
############################################################
srv_name="ns-rank"
bridge="br-int"
ipaddr="192.168.167.252/24"
gateway="192.168.167.1"
dns="8.8.8.8"
gen_svc_tpl "${srv_name}" "${bridge}" "${ipaddr}" "${gateway}" "${dns}"
cat <<EOF > ${srv_name}/etc/${srv_name}/startup.sh
#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
/usr/sbin/ip route add 192.3.164.171 via 192.168.167.1 || true
/usr/sbin/ip route add 10.0.0.0/8 via 192.168.167.1 || true
/usr/sbin/ip route add 172.16.0.0/12 via 192.168.167.1 || true
/usr/sbin/ip route add 192.168.0.0/16 via 192.168.167.1 || true
cat <<EO_HOST > /etc/hosts
127.0.0.1      localhost
192.3.164.171  tunl.wgserver.org
EO_HOST
wg-quick up wgrank
/usr/sbin/ip route replace default via 192.168.32.1 || true
sysctl -w net.ipv4.ip_forward=1
cat<<EO_NAT | nft -f /dev/stdin
flush ruleset
table ip nat {
    chain postrouting {
        type nat hook postrouting priority 100; policy accept;
        ip saddr 192.168.167.0/24 ip daddr != 192.168.167.0/24 counter masquerade
    }
}
EO_NAT
EOF
cat <<EOF > ${srv_name}/etc/${srv_name}/teardown.sh
#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
wg-quick down wgrank
EOF
echo "(cd ${srv_name} && rsync -avP * /)"
############################################################
srv_name="ns-v2ray"
bridge="br-int"
ipaddr="192.168.167.250/24"
# all to ns-ali, or on host add 'ip rule add from 192.168.167.250 table 777 && ip r a default via 192.168.167.251 table 777'
gateway="192.168.167.251"
dns="8.8.8.8"
gen_svc_tpl "${srv_name}" "${bridge}" "${ipaddr}" "${gateway}" "${dns}"
cat <<EOF > ${srv_name}/etc/${srv_name}/startup.sh
#!/usr/bin/env bash
set -o nounset -o pipefail -o errexit
/usr/sbin/ip route add 10.0.0.0/8 via 192.168.167.1 || true
/usr/sbin/ip route add 172.16.0.0/12 via 192.168.167.1 || true
/usr/sbin/ip route add 192.168.0.0/16 via 192.168.167.1 || true
cat <<EO_HOST > /etc/hosts
127.0.0.1      localhost
192.3.164.171  tunl.wgserver.org
EO_HOST
/etc/${srv_name}/v2ray.cli.tproxy.nft.sh
sysctl -w net.ipv4.ip_forward=1
/etc/${srv_name}/v2ray -config /etc/${srv_name}/config.json
EOF
echo "(cd ${srv_name} && rsync -avP * /)"
cat <<EOF
############################################################
# # /etc/${srv_name}/
config.json
geoip.dat
geosite.dat
v2ray
v2ray.cli.tproxy.nft.sh
EOF
