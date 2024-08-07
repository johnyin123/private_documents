#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("af7c231[2024-01-12T09:06:39+08:00]:inst_zabbix_agent.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
change() {
    local PKG=${1}
    local type=${2:-VM}
    yum -y --disablerepo=* install /tmp/${PKG}
    rm -fr /tmp/${PKG}
    mkdir -p /etc/systemd/system/zabbix-agent.service.d
    # root execute get uuid
    cat <<'EOF' > /etc/systemd/system/zabbix-agent.service.d/tsd.conf
[Service]
ExecStartPre=+/usr/bin/tsdzabbix.sh
EOF
    cat <<'EOF' > /usr/bin/tsdzabbix.sh
#!/bin/sh
uuid=$(cat /sys/class/dmi/id/product_uuid 2>/dev/null)
[ -z "${uuid}" ] && uuid="BAD"-$(cat /proc/sys/kernel/random/uuid)
/usr/bin/sed --quiet -i -E \
    -e '/(Hostname|HostMetadata|Server|ServerActive)\s*=.*/!p' \
    -e "\$aHostname=${uuid}" \
    -e "\$aHostMetadata=$(/usr/bin/uname -m)" \
    -e '$aServer=zabbix.tsd.org' \
    -e '$aServerActive=zabbix.tsd.org' \
    /etc/zabbix/zabbix_agentd.conf
# /usr/bin/sed --quiet -i -E \
#     -e '/(Hostname|HostnameItem)\s*=.*/!p' \
#     -e '$aHostnameItem = system.run[curl -s http://zabbix.tsd.org:8181?hostname=`hostname`]' \
#     /etc/zabbix/zabbix_agentd.conf
exit 0
EOF
    chmod 755 /usb/bin/tsdzabbix.sh
    sed -i '/^ListenIP=.*/d' /etc/zabbix/zabbix_agentd.conf
    sed -i '/^HostMetadataItem=.*/d' /etc/zabbix/zabbix_agentd.conf
    # VM : 虚拟机
    # PHY : 物理机
    # X86 : X86 架构
    # ARM : arm 架构
    # sed -i 's/^#\s*HostnameItem=system.hostname/HostnameItem=system.hostname/g' /etc/zabbix/zabbix_agentd.conf
    echo "172.16.0.222 zabbix.tsd.org" >> /etc/hosts
    mkdir -p /var/log/zabbix && chown zabbix:zabbix /var/log/zabbix
    systemctl enable zabbix-agent
    systemctl restart zabbix-agent
    ps -ef |grep zabbix_agentd
}
set_sshpass "2wsx@WSX"
for i in $(cat lst); do
    arch=$(ssh root@$i "uname -m") || { echo "$i ERROR"; continue; }
    PKG=zabbix_agent-6.0.25-1.${arch}.rpm
    scp ${PKG} root@$i:/tmp
    ssh_func root@$i 60022 change ${PKG} "VM"
done
