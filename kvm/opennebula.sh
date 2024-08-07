#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("0f99172[2023-11-16T09:38:18+08:00]:opennebula.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
# https://docs.opennebula.io
# Take out serial console from kernel configuration
# (it can freeze during the boot process).
# sed -i --follow-symlinks 's/console=ttyS[^ "]*//g' /etc/default/grub /etc/grub.cfg
# Gold Image:
# Download Contextualization Packages to the VM
# wget https://github.com/OpenNebula/addon-context-linux/
# /usr/share/one/context/one-context-6.6.1-1.el6.noarch.rpm
# openEuler:  echo "ID_LIKE=centos" >> /etc/os-release # one-context > 6.6
#######################################################################################
# # 创建数据库
# mysql_secure_installation
# cat <<EOF | mysql -uroot -p<Pass>
# CREATE DATABASE opennebula;
# GRANT ALL PRIVILEGES ON opennebula.* TO 'oneadmin'@'localhost' IDENTIFIED BY 'password';
# GRANT ALL PRIVILEGES ON opennebula.* TO 'oneadmin'@'%' IDENTIFIED BY 'password';
# flush privileges;
# EOF
# systemctl stop opennebula
# onedb fsck --sqlite /var/lib/one/one.db
# onedb sqlite2mysql -d opennebula -u oneadmin -p password
# # Change /etc/one/oned.conf from
#  DB = [ backend = "sqlite" ]
# # to
# DB = [ backend = "mysql", server = "localhost", port = 3306, user = "oneadmin", passwd = "oneadmin", db_name = "opennebula" ]
# systemctl restart opennebula opennebula-sunstone
# check logs for errors (/var/log/one/oned.log /var/log/one/sched.log /var/log/one/sunstone.log)
#########################################
init_frontend() {
    local pubaddr=${1}
    local sshport=${2:-22}
    local password=${3:-password}
    local hosts=localhost
    grep -q "Host ${hosts/\*/\\*}" /var/lib/one/.ssh/config || {
        tee -a /var/lib/one/.ssh/config <<EOF
Host ${hosts}
  Port ${sshport}
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
EOF
    }
    rm -f /var/lib/one/.one/* || true
    echo "oneadmin:${password}" | sudo -u oneadmin tee /var/lib/one/.one/one_auth
    sed -i -E \
        -e 's|^\s*#*\s*:host:.*|:host: 0.0.0.0|g' \
        /etc/one/onegate-server.conf
    # DATASTORE_LOCATION
    sed -i -E \
        -e "s|^\s*#*\s*ONEGATE_ENDPOINT\s*=.*|ONEGATE_ENDPOINT = \"http://${pubaddr}:5030\"|g" \
        -e 's|^\s*#*\s*DATASTORE_LOCATION\s*=.*|DATASTORE_LOCATION = /storage|g' \
        -e 's|^\s*#*\s*DEFAULT_CDROM_DEVICE_PREFIX\s*=.*|DEFAULT_CDROM_DEVICE_PREFIX = "sd"|g' \
        /etc/one/oned.conf
    # /etc/one/vmm_exec/vmm_exec_kvm.conf, add full path firmware file in <OVMF_UEFIS>
    #       vmm_exec_kvm.conf are only used during VM creation. other actions like nic or disk
    #       attach/detach the default values must be set in /var/lib/one/remotes/etc/vmm/kvm/kvmrc
    # /usr/lib/one/mads/one_vmm_exec : generic VMM driver.
    # /var/lib/one/remotes/vmm/kvm : commands executed to perform actions.
    # /var/lib/one/remotes/etc/vmm/kvm/kvmrc
    echo "" >> /etc/one/vmm_exec/vmm_exec_kvm.conf
    sed --quiet -i -E \
        -e '/(\s*OVMF_UEFIS\s*=).*/!p' \
        -e '$aOVMF_UEFIS = "/usr/share/OVMF/OVMF_CODE.fd /usr/share/OVMF/OVMF_CODE.secboot.fd /usr/share/AAVMF/AAVMF_CODE.fd /usr/share/edk2/aarch64/QEMU_EFI-pflash.raw"' \
        /etc/one/vmm_exec/vmm_exec_kvm.conf
    echo "vnc fix"
    sed -i -E \
        -e "s|fireedge_endpoint\s*:.*|fireedge_endpoint: http://${pubaddr}:2616|g" \
        -e "s|:port\s*:.*|:port: 80|g" \
        /etc/one/sunstone-server.conf
    # [[ $port -lt 1024 ]] &&
    setcap 'cap_net_bind_service=+ep' "$(readlink -f /usr/bin/ruby)"
    systemctl stop opennebula --force || true
    rm -f /var/lib/one/one.db /var/log/one/* || true
    sudo -u oneadmin oned --init-db
    systemctl restart opennebula opennebula-sunstone opennebula-gate.service opennebula-fireedge || true
    echo "if no fireedge, nee start opennebula-novnc.service"
    for svc in opennebula opennebula-sunstone opennebula-gate.service opennebula-fireedge; do
        systemctl enable ${svc} || true
    done
    echo "disable market place, delete default datastore"
    onemarket list --no-header | awk '{print $1}' | xargs -I@ onemarket delete @ || true
    onedatastore list --no-header | awk '{print $1}' | xargs -I@ onedatastore delete @ || true
    # Verify OpenNebula Frontend installation
    sudo -u oneadmin oneuser show --json
    [ -e "/var/lib/one/.ssh/known_hosts" ] && truncate -s0 /var/lib/one/.ssh/known_hosts
    oneuser show 0 | sed '/USER TEMPLATE/,/VMS USAGE/!d;//d' >/tmp/oneadmin.tpl
    cat <<EOF >> /tmp/oneadmin.tpl
SSH_PUBLIC_KEY="$(cat /var/lib/one/.ssh/id*pub 2>/dev/null)"
EOF
    oneuser update 0 /tmp/oneadmin.tpl && rm -f /tmp/oneadmin.tpl
    # # To change oneadmin password, follow the next steps:
    # oneuser passwd 0 <PASSWORD>
    # echo 'oneadmin:PASSWORD' > /var/lib/one/.one/one_auth
    # # # # # # # # # # To recover the DB you may try:
    # rm -fr /var/lib/one/.one
    # sudo -u oneadmin mkdir -m 0700 /var/lib/one/.one
    # echo "oneadmin:${password:-password}" | sudo -u oneadmin tee /var/lib/one/.one/one_auth
    # sudo -u oneadmin onedb restore <backupfile>
    # systemctl start opennebula
    # sudo -u oneadmin oneuser passwd --sha256 serveradmin new_passwd_for_serveradmin
    # echo serveradminnew_passwd_for_serveradmin | sudo -u oneadmin tee /var/lib/one/.one/sunstone_auth
    # cat /var/lib/one/.one/sunstone_auth | sudo -u oneadmin tee /var/lib/one/.one/oneflow_auth
    # cat /var/lib/one/.one/sunstone_auth | sudo -u oneadmin tee /var/lib/one/.one/onegate_auth
    echo "http://$pubaddr:9869, Sunstone web"
    echo "http://$pubaddr:2616, FireEdge Sunstone is the new generation OpenNebula web interface,still in BETA stage"
}
#######################################################################################
# Manage
#######################################################################################
add_cluster() {
    local cluster=${1}
    sudo -u oneadmin onecluster create ${cluster}
}
add_kvmhost() {
    ipaddr=${1}
    sshport=${2}
    local cluster=${3:-}
    local hosts=${ipaddr}
    grep -q "Host ${hosts/\*/\\*}" /var/lib/one/.ssh/config || {
        tee -a /var/lib/one/.ssh/config <<EOF
Host ${hosts}
  Port ${sshport}
  StrictHostKeyChecking no
  UserKnownHostsFile=/dev/null
EOF
    }
    sudo -u oneadmin onehost create ${cluster:+--cluster ${cluster}} --im kvm --vm kvm ${ipaddr}
}
add_bridge_net() {
    local vn_name=${1}
    local phy_bridge=${2}
    local guest_ipaddr=${3}
    local guest_ipaddr_size=${4}
    local guest_net_mask=${5:-255.255.255.0}
    local guest_gateway=${6:-}
    local guest_nameserver=${7:-}
    local cluster=${8:-}
    local tmp_file=$(sudo -u oneadmin mktemp) || return 1
    sudo -u oneadmin tee "${tmp_file}" <<EOF
NAME       = "${vn_name}"
BRIDGE     = "${phy_bridge}"
BRIDGE_TYPE= "linux"
VN_MAD     = "bridge"
${guest_nameserver:+DNS        = "${guest_nameserver}"}
${guest_gateway:+GATEWAY    = "${guest_gateway}"}
AR = [ IP = "${guest_ipaddr}", SIZE = "${guest_ipaddr_size}", NETWORK_MASK = "${guest_net_mask}", TYPE = "IP4" ]
EOF
    sleep 5
    sudo -u oneadmin onevnet create ${cluster:+--cluster ${cluster}} "${tmp_file}" && rm -f "${tmp_file}"
    # ADD Address Ranges
    # onevnet addar ${vn_name} --ip 192.168.168.50 --size 10
}
######################################gg###
# Create a System/Image Datastore
# TM_MAD:
#     shared for shared transfer mode
#       对于shared类型的System storage，必须配置一个类型为shared的image storage
#       否则无法在shared system storage上创新虚拟机，ssh image storage是无法把镜像拷贝到shared system storage
#     qcow2 for qcow2 transfer mode
#     ssh for ssh transfer mode
add_fs_store() {
    local name=${1}
    local type=${2}
    local cluster=${3:-}
    local val=""
    case "${type}" in
        sys)   val="TYPE = SYSTEM_DS";;
        img)   val="DS_MAD = fs";;
        *)     echo "fs store type [${type}] error"; return 1;;
    esac
    local tmp_file=$(sudo -u oneadmin mktemp) || return 1
    sudo -u oneadmin tee "${tmp_file}" <<EOF
NAME    = ${name}
TM_MAD  = ssh
$(echo ${val})
EOF
    sudo -u oneadmin onedatastore create ${cluster:+--cluster ${cluster}} "${tmp_file}" && rm -f "${tmp_file}"
}
#########################################
# Image template
add_dataimg_tpl() {
    local img_datastore=${1}
    local img_tpl_name=${2}
    local tmp_file=$(sudo -u oneadmin mktemp) || return 1
    sudo -u oneadmin tee "${tmp_file}" <<EOF
NAME           = "${img_tpl_name}"
DESCRIPTION    = "${img_tpl_name} data tpl image."
TYPE           = DATABLOCK
PERSISTENT     = No
FORMAT         = raw
SIZE           = 1024
DEV_PREFIX     = "vd"
EOF
    sudo -u oneadmin oneimage create -d ${img_datastore} "${tmp_file}" && rm -f "${tmp_file}"
    # sudo -u oneadmin oneimage create --prefix vd --datastore ${img_datastore} --name ${img_tpl_name} --path ${tpl_file} --description "${img_tpl_name} vm tpl image."
    # sudo -u oneadmin oneimage nonpersistent
    sudo -u oneadmin oneimage chmod ${img_tpl_name} 604
}
add_osimg_tpl() {
    local img_datastore=${1}
    local img_tpl_name=${2}
    local tpl_file=${3}
    [ -e "${tpl_file}" ] || {
        echo "${tpl_file} no found!!! create one 2GiB"
        truncate -s 2G "${tpl_file}"
    }
    local tmp_file=$(sudo -u oneadmin mktemp) || return 1
    sudo -u oneadmin tee "${tmp_file}" <<EOF
NAME           = "${img_tpl_name}"
DESCRIPTION    = "${img_tpl_name} sys tpl image."
TYPE           = OS
PERSISTENT     = No
PATH           = ${tpl_file}
DEV_PREFIX     ="vd"
EOF
    sudo -u oneadmin oneimage create -d ${img_datastore} "${tmp_file}" && rm -f "${tmp_file}"
    # sudo -u oneadmin oneimage create --prefix vd --datastore ${img_datastore} --name ${img_tpl_name} --path ${tpl_file} --description "${img_tpl_name} vm tpl image."
    # sudo -u oneadmin oneimage nonpersistent
    sudo -u oneadmin oneimage chmod ${img_tpl_name} 604
}
# *************** Frontend Setup ****************#
# # The Frontend does not need any specific Ceph setup, it will access the Ceph cluster through the storage bridges.
# # DEFINE system and image datastores
# # Both datastores will share the same configuration parameters and Ceph pool.
# # https://docs.opennebula.io/6.6/open_cluster_deployment/storage_setup/ceph_ds.html
add_ceph_store() {
    local name=${1}
    local type=${2}
    local poolname=${3}
    local secret_uuid=${4}
    local secret_name=${5}
    local mon_host=${6}
    local bridge_host=${7}
    local ceph_conf=$(basename ${8:-ceph.conf})
    local cluster=${9:-}
    local val=""
    case "${type}" in
        sys)   val="TYPE = SYSTEM_DS"; transfer_mode="TM_MAD = ceph";;
        img)   val="DS_MAD = ceph"; transfer_mode="TM_MAD = ceph";;
        *)     echo "fs store type [${type}] error"; return 1;;
    esac
    local tmp_file=$(sudo -u oneadmin mktemp) || return 1
    sudo -u oneadmin tee "${tmp_file}" <<EOF
NAME        = "${name}"
${val}
${transfer_mode}
DISK_TYPE   = RBD
RBD_FORMAT  = 2
POOL_NAME   = ${poolname}
CEPH_SECRET = "${secret_uuid}"
CEPH_USER   = ${secret_name}
CEPH_HOST   = "${mon_host}"
CEPH_CONF= /etc/ceph/${ceph_conf}
BRIDGE_LIST = "${bridge_host}"
# List of storage bridges to access the Ceph cluster
EOF
    sudo -u oneadmin onedatastore create ${cluster:+--cluster ${cluster}} "${tmp_file}" && rm -f "${tmp_file}"
}
add_vm_tpl() {
    local vmtpl_name=${1}
    local img_tpl=${2}
    local arch=${3}
    local vn_name=${4}
    local img_store_type=${5:-}
    local firmware="" machine="" raw="" tm_mad_system=""
    case "${img_store_type}" in
        # # Note that the same mode will be used for all disks of the VM.
        fs)   tm_mad_system="TM_MAD_SYSTEM=ssh" ;;
        ceph) tm_mad_system="";;
    esac
    case "${arch}" in
        aarch64)
            firmware=/usr/share/edk2/aarch64/QEMU_EFI-pflash.raw
            machine="virt-6.2"
            raw="RAW=[TYPE=\"kvm\",DATA=\"<devices><input type='keyboard' bus='virtio'/></devices>\" ]"
            ;;
        x86_64)
            firmware=""
            machine="q35"
            raw=""
            ;;
        *)  echo "arch [${arch}] error"; return 1;;
    esac
    # SCHED_REQUIREMENTS = "FREE_CPU > 60"
    # SCHED_REQUIREMENTS    = "CPUSPEED > 1000"
    # SCHED_DS_REQUIREMENTS = "NAME=GoldenCephDS"
# When different System Datastores are available the TM_MAD_SYSTEM attribute will be set after picking the Datastore.
# Same TM_MAD for both the System and Image datastore
# When creating a VM Template you can choose to deploy the disks using the default Ceph mode or the SSH one.
# Note that the same mode will be used for all disks of the VM.
# To set the deployment mode, add the following attribute to the VM template:
# TM_MAD_SYSTEM="ssh"
# When using Sunstone, the deployment mode needs to be set in the Storage tab.
    local dynamic='VCPU_MAX  = 16
MEMORY_MAX= 32768
MEMORY_RESIZE_MODE="BALLOONING"
HOT_RESIZE  = [ CPU_HOT_ADD_ENABLED="YES", MEMORY_HOT_ADD_ENABLED="YES" ]'
    # add NETWORK_UNAME avoid none admin user, create vm from tpl, network error
    # /etc/one/vmm_exec/vmm_exec_kvm.conf, add full path firmware file in <OVMF_UEFIS>
    # ONEGATE_ENDPOINT = "http://gate:5030"
    # CONTEXT = [ DEV_PREFIX = "sd", TARGET = "sda" ], nebula iso use scsi not ide
    # SCHED_DS_REQUIREMENTS = "NAME = ssd_system"
    # KVM磁盘热插拔, ACPI="yes"
    local tmp_file=$(sudo -u oneadmin mktemp) || return 1
    sudo -u oneadmin tee "${tmp_file}" <<EOF
${tm_mad_system}
LOGO          = "images/logos/linux.png"
SUNSTONE      = [ NETWORK_SELECT = "NO" ]
FEATURES      = [ ACPI="yes", APIC="yes", PAE="yes", GUEST_AGENT="yes" ]
NAME      = "${vmtpl_name}"
CPU_COST         ="4"
DISK_COST        ="0.0009765625"
MEMORY_UNIT_COST ="GB"
MEMORY_COST      ="0.00390625"
VCPU      = 0.5
CPU       = 1
MEMORY    = 512
USER_INPUTS = [
  ROOTPASS  = "M|text|root password||rootpass",
  VCPU      = "M|list||1,2,4,8,16|1",
  CPU       = "M|list||0.5,1,2,4,8,16|0.5",
  MEMORY    = "M|list||512,1024,2048,4096,8192,16384,32768|512" ]
DISK      = [ IMAGE = "${img_tpl}", DEV_PREFIX = "vd", IMAGE_UNAME = oneadmin, CACHE="none", IO="native" ]
NIC_DEFAULT = [ MODEL = "virtio" ]
NIC       = [ NETWORK = "${vn_name}", NETWORK_UNAME = "oneadmin" ]
GRAPHICS  = [ TYPE = "vnc", LISTEN = "0.0.0.0", RANDOM_PASSWD="YES" ]
OS        = [ ARCH="${arch}", MACHINE="${machine}" ${firmware:+, FIRMWARE="${firmware}", FIRMWARE_SECURE=false} ]
CPU_MODEL = [ MODEL="host-passthrough" ]
${raw}
RAW       = [
  TYPE = "kvm",
  VALIDATE = "YES",
  DATA = "<devices>
            <serial type='pty'><target port='0'/></serial>
            <console type='pty'><target type='serial' port='0'/></console>
            <rng model='virtio'><backend model='random'>/dev/urandom</backend></rng>
          </devices>"
]
CONTEXT            = [
    DEV_PREFIX     = "sd",
    TARGET         = "sda",
    PASSWORD       = "\$ROOTPASS",
    GROW_ROOTFS    = "YES",
    TOKEN          = "YES",
    REPORT_READY   = "YES",
    NETWORK        = "YES",
    SET_HOSTNAME   = "\$NAME",
    SSH_PUBLIC_KEY = "\$USER[SSH_PUBLIC_KEY]",
    START_SCRIPT   = "#!/bin/bash
echo 'start' > /.start.ok"
]
EOF
    sudo -u oneadmin onetemplate create "${tmp_file}" && rm -f "${tmp_file}"
    sudo -u oneadmin onetemplate chmod "${vmtpl_name}" 604
}
teardown() {
    onevm list --no-header | awk '{print $1}' | xargs -I@ onevm recover --delete @ || true
    for cmd in onetemplate oneimage onevnet onedatastore onehost onemarket; do
        echo "${cmd} delete"
        ${cmd} list --no-header | awk '{print $1}' | xargs -I@ ${cmd} delete @ || true
        ${cmd} list || true
    done
    systemctl stop opennebula opennebula-sunstone opennebula-gate.service opennebula-fireedge opennebula-novnc || true
    systemctl disable opennebula opennebula-sunstone opennebula-gate.service opennebula-fireedge opennebula-novnc || true
}
#######################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        env:
            SUDO=   default undefine
        -F|--frontend   *  <addr>   Frontend address
        --teardown         <addr>   teardown
        -N|--kvmnode    *  <addr>   kvm node address, multi input, NOT execute on kvmnodes!!!!, only frontend, need init manual
        --adminpass        <str>    http://<frontend_address>:9869, oneadmin pass,default 'password'
        --vnet             <str>    vnet name, use <bridge>
        --bridge        *  <str>    vnet used phy bridge name on kvm node
        --guest_ipstart    <ipaddr> vnet guest start ip, if vnet set, must set it
        --guest_ipsize     <int>    vnet guest ip size, if vnet set, must set it
        --guest_netmask    <mask>   vnet guset netmask, like 255.255.255.0
        --guest_gateway    <ipaddr> vnet guest gateway, can NULL
        --guest_dns        <ipaddr> vnet guest dns, can NULL
        --ceph_pool        <str>    ceph datastore pool name
        --ceph_user        <str>    ceph datastore user name
        --ceph_conf        <file>   ceph config filename
        --ceph_keyring     <file>   ceph user keyring filename
                                    ceph --conf <ceph_conf> auth get client.<ceph_user> -o <cluster>.client.<ceph_user>.keyring
        --secret_uuid      <uuid>   libvirt ceph rbd secret uuid, if not set auto gen
                                    kvmnodes define use <secret_uuid
        --fs_store         <str>    fs datastore name
        --arm_tplimg       <file>   aarch64 vm gold image
        --x86_tplimg       <file>   x86_64 vm gold image
        --cluster          <str>    create opennebula cluster
        -U|--user          <user>   ssh user, default root
        -P|--port          <int>    ssh port, default 60022
        --password         <str>    ssh password(default use sshkey)
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
    exam ceph:
        ./opennebula.sh --frontend 192.168.168.150 --kvmnode 192.168.168.151 \\
           --bridge br-ext --vnet pub-net \\
           --guest_ipstart 172.16.4.0 --guest_ipsize 255 --guest_netmask 255.255.248.0 \\
           --guest_gateway 172.16.0.1 --guest_dns 192.168.1.11 \\
           --arm_tplimg openeuler_22.03sp1_aarch64.img --x86_tplimg debian_bulleye_amd64.img \\
           --fs_store ssdstore \\
           --ceph_pool libvirt-pool --secret_uuid 81a6a177-1328-4711-addb-632b1f446ff7 \\
           --ceph_user admin --ceph_conf ceph/armsite.conf --ceph_keyring ceph/armsite.client.admin.keyring
# apt update && apt -y install wget gnupg2 apt-transport-https
curl -fsSL https://downloads.opennebula.io/repo/repo2.key|gpg --dearmor -o /etc/apt/trusted.gpg.d/opennebula.gpg
wget -q -O- 'https://repo.dovecot.org/DOVECOT-REPO-GPG' | gpg --dearmor > /etc/apt/trusted.gpg.d/dovecot-archive-keyring.gpg
### Debian 12 / Debian 11 ###
echo 'Acquire { https::Verify-Peer false }' > /etc/apt/apt.conf.d/99verify-peer.conf
echo "deb [trusted=yes] https://downloads.opennebula.io/repo/6.6/Debian/11 stable opennebula" | tee /etc/apt/sources.list.d/opennebula.list
### Debian 10 ###
echo "deb https://downloads.opennebula.io/repo/6.6/Debian/10 stable opennebula" | tee /etc/apt/sources.list.d/opennebula.list

make private repo for install, see k8s/gen_k8s_pkg.sh
# mkdir -p package packs
# mv *.deb package/ || true
# dpkg-scanpackages --multiversion package /dev/null | gzip > packs/Packages.gz
# deb [trusted=yes] http://192.168.168.1/debian packs/
# KvmNode:
  apt update && apt -y install opennebula-node-kvm
  echo 'Binary::apt::APT::Keep-Downloaded-Packages "true";' > /etc/apt/apt.conf.d/01keep-debs
  apt update && apt -o APT::Keep-Downloaded-Packages="true" -y install ceph-common
# Frontend
  apt update && apt -y install vim opennebula opennebula-sunstone opennebula-gate opennebula-flow opennebula-fireedge # opennebula-provision
# rbd rm libvirt-pool/one-3-5-0
# rbd snap unprotect libvirt-pool/one-3@snap
# rbd snap purge libvirt-pool/one-3
# rbd rm libvirt-pool/one-3
#
# euler 2203
# # yum group install "Virtualization Host"
yum -y install libvirt lvm2 bridge-utils ebtables iptables ipset qemu-block-rbd qemu-block-ssh
yum -y install ceph-common
yum -y install xmlrpc-c rubygems rubygem-rexml rubygem-sqlite3
cat <<EO_NB >/etc/sysctl.d/bridge-nf-call.conf
net.bridge.bridge-nf-call-arptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
EO_NB
useradd oneadmin --no-create-home --home-dir /var/lib/one --shell /bin/bash
mkdir -p -m0755 /var/lib/one/remotes && chown -R oneadmin.oneadmin /var/lib/one
su - oneadmin -c "mkdir -p -m0644 /var/lib/one/remotes/etc"
chown oneadmin:oneadmin /storage/ -R
usermod -a -G libvirt oneadmin
usermod -a -G kvm oneadmin
echo '%oneadmin ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/oneadmin
su - oneadmin -c "ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa"
ln -s /usr/libexec/qemu-kvm /usr/bin/qemu-kvm-one
# NOT NEED add blow on euler
./install.sh -u oneadmin -g oneadmin -6
# # install below files
# /usr/lib/one/onegate-proxy/onegate-proxy.rb 0644
# /usr/bin/onegate-proxy                      0755
# /var/lib/one/remotes/etc                    0644
# cat << EO_NB >> /etc/libvirt/qemu.conf
# user = "oneadmin"
# group = "oneadmin"
# dynamic_ownership = 0
# EO_NB
# cat <<EO_NB >> /etc/libvirt/libvirtd.conf
# auth_unix_ro = "none"
# auth_unix_rw = "none"
# unix_sock_group = "oneadmin"
# unix_sock_ro_perms = "0770"
# unix_sock_rw_perms = "0770"
# EO_NB
# cat <<EO_NB >> /etc/polkit-1/localauthority/50-local.d/50-org.libvirt.unix.manage-opennebula.pkla
# [Allow oneadmin user to manage virtual machines]
# Identity=unix-user:oneadmin
# Action=org.libvirt.unix.manage
# #Action=org.libvirt.unix.monitor
# ResultAny=yes
# ResultInactive=yes
# ResultActive=yes
# EO_NB
onedb backup filename
oneuser create user1 password
onevm deploy 1 2
onevm list --search MAC=02:00:0c:00:4c:dd
oneuser quota
onegroup quota
oneuser batchquota userA,userB,35
onegroup batchquota
Or in Sunstone through the user/group tab
modify /etc/one/oned.conf <DEFAULT_CDROM_DEVICE_PREFIX>, can set CDROM default to ide/scsi/virtio
OR:
    You can set the TARGET & DEV_PREFIX in the context section
    CONTEXT = [ DEV_PREFIX = "sd", TARGET="sd" .... ]

Every HA cluster requires:
    1. Odd number of servers (3 is recommended).
    2. Recommended identical servers capacity.
    3. Same software configuration of the servers (the sole difference would be the SERVER_ID field in /etc/one/oned.conf).
    4. Working database connection of the same type, MySQL is recommended.
    5. All the servers must share the credentials.
    6. Floating IP which will be assigned to the leader.
    7. Shared filesystem.
The servers should be configured in the following way:
    1. Sunstone (with or without Apache/Passenger) running on all the nodes.
https://docs.opennebula.io/5.8/advanced_components/ha/frontend_ha_setup.html
sudo -i -u oneadmin
BAK_DIR=~/one_backup
mkdir -p \$BAK_DIR
cp -rp --parents /etc/one \$BAK_DIR
cp -rp --parents /var/lib/one/remotes \$BAK_DIR
cp -rp --parents /var/lib/one/.one \$BAK_DIR
onedb backup -S <database_host> -u <user> -p <password> -d <database_name> -P <port>
cp -rp <onedb_backup> \$BAK_DIR
EOF
    exit 1
}

main() {
    local secret_uuid=$(cat /proc/sys/kernel/random/uuid)
    local user=root port=60022 teardown_host=""
    local frontend="" kvmnode=() adminpass="password" ceph_pool="" ceph_user="" ceph_conf="" ceph_keyring="" bridge="" cluster="" fs_store=""
    local vnet="" guest_ipstart="" guest_ipsize="" guest_netmask="" guest_gateway="" guest_dns="" arm_tplimg="aarch64.raw" x86_tplimg="x86_64.raw"
    local opt_short="U:P:F:N:"
    local opt_long="user:,port:password:,frontend:,kvmnode:,adminpass:,ceph_pool:,ceph_user:,ceph_conf:,ceph_keyring:,secret_uuid:,bridge:,"
    opt_long+="cluster:,vnet:,guest_ipstart:,guest_ipsize:,guest_netmask:,guest_gateway:,guest_dns:,fs_store:,arm_tplimg:,x86_tplimg:,teardown:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -F | --frontend)   shift; frontend=${1}; shift;;
            --teardown)        shift; teardown_host=${1}; shift;;
            --adminpass)       shift; adminpass=${1}; shift;;
            --cluster)         shift; cluster=${1}; shift;;
            --vnet)            shift; vnet=${1}; shift;;
            --guest_ipstart)   shift; guest_ipstart=${1}; shift;;
            --guest_ipsize)    shift; guest_ipsize=${1}; shift;;
            --guest_netmask)   shift; guest_netmask=${1}; shift;;
            --guest_gateway)   shift; guest_gateway=${1}; shift;;
            --guest_dns)       shift; guest_dns=${1}; shift;;
            -N | --kvmnode)    shift; kvmnode+=(${1}); shift;;
            --bridge)          shift; bridge=${1}; shift;;
            --ceph_pool)       shift; ceph_pool=${1}; shift;;
            --ceph_user)       shift; ceph_user=${1}; shift;;
            --ceph_conf)       shift; ceph_conf=${1}; shift;;
            --ceph_keyring)    shift; ceph_keyring=${1}; shift;;
            --secret_uuid)     shift; secret_uuid=${1}; shift;;
            --fs_store)        shift; fs_store=${1}; shift;;
            --arm_tplimg)      shift; arm_tplimg=${1}; shift;;
            --x86_tplimg)      shift; x86_tplimg=${1}; shift;;
            -U | --user)       shift; user=${1}; shift;;
            -P | --port)       shift; port=${1}; shift;;
            --password)        shift; set_sshpass "${1}"; shift;;
            ########################################
            -q | --quiet)   shift; QUIET=1;;
            -l | --log)     shift; set_loglevel ${1}; shift;;
            -d | --dryrun)  shift; DRYRUN=1;;
            -V | --version) shift; for _v in "${VERSION[@]}"; do echo "$_v"; done; exit 0;;
            -h | --help)    shift; usage;;
            --)             shift; break;;
            *)              usage "Unexpected option: $1";;
        esac
    done
    [ -z "${teardown_host}" ] || {
        ssh_func "${user}@${teardown_host}" "${port}" teardown
        info_msg "${teardown_host} TEARDOWN OK\n"
        return 0
    }
    [ -z "${frontend}" ] && usage "frontend ?"
    [ -z "${bridge}" ] && usage "bridge network ?"
    [ "$(array_size kvmnode)" -gt "0" ] || usage "kvmnode ?"
    [ -z "${ceph_conf}" ] || file_exists "${ceph_conf}" || exit_msg "${ceph_conf} no found\n"
    [ -z "${ceph_keyring}" ] || file_exists "${ceph_keyring}" || exit_msg "${ceph_keyring} no found\n"
    download "${frontend}" "${port}" "${user}" "/var/lib/one/.ssh/id_rsa.pub" "authorized_keys"
    info_msg "kvmnodes init script start ..............\n"
    info_msg "===================================================================\n"
    cat <<EOF
# # # init kvm nodes
# Make sure all the Hosts, including the Front-end, can SSH to any other host (including themselves), otherwise migrations will not work.
[ -e /var/lib/one/.ssh/id_rsa ] || su - oneadmin -c "ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa"
sudo -u oneadmin tee -a /var/lib/one/.ssh/authorized_keys <<EOK
$(cat authorized_keys)
EOK
chmod 0600 /var/lib/one/.ssh/authorized_keys
# tee /etc/sysconfig/network-scripts/ifcfg-${bridge} <<EOBR
# DEVICE="${bridge}"
# ONBOOT="yes"
# TYPE="Bridge"
# BOOTPROTO="none"
# STP="off"
# EOBR
EOF
[ -z "${ceph_pool}" ] || [ -z "${ceph_user}" ] || [ -z "${ceph_conf}" ] || [ -z "${ceph_keyring}" ] || cat <<EOF
# # COPY ceph.client.admin.keyring ceph.conf to nodes
tee /etc/ceph/$(basename ${ceph_conf}) <<EOK
$(cat "${ceph_conf}")
EOK
tee /etc/ceph/$(basename ${ceph_keyring}) <<EOK
$(cat "${ceph_keyring}")
EOK
systemctl restart libvirtd
cat <<EPOOL | virsh secret-define /dev/stdin
<secret ephemeral='no' private='no'>
  <uuid>${secret_uuid}</uuid>
  <usage type='ceph'>
    <name>${ceph_user} secret</name>
  </usage>
</secret>
EPOOL
# ceph auth get-key client.${ceph_user}
# cat /etc/ceph/ceph.client.${ceph_user}.keyring | awk '/key = /{print \$3}'
virsh secret-set-value --secret ${secret_uuid} --base64 \$(awk '/key = /{print \$3}' /etc/ceph/$(basename ${ceph_keyring})) 2>/dev/null
virsh secret-list
EOF
    info_msg "===================================================================\n"
    info_msg "kvmnodes init script end ..............\n"
    confirm "First Init kvmnode!!, then continue." 60
    ssh_func "${user}@${frontend}" "${port}" init_frontend "${frontend}" "${port}" "${adminpass}"
    [ -z "${cluster}" ] || ssh_func "${user}@${frontend}" "${port}" add_cluster "${cluster}"
    [ -z "${vnet}" ] || [ -z "${bridge}" ] || ssh_func "${user}@${frontend}" "${port}" add_bridge_net "${vnet}" "${bridge}" "${guest_ipstart}" "${guest_ipsize}" "${guest_netmask}" "${guest_gateway}" "${guest_dns}" "${cluster}"
    [ -z "${fs_store}" ] || { ssh_func "${user}@${frontend}" "${port}" add_fs_store "${fs_store}" "sys" "${cluster}"; }
    local img_store_type=fs
    local mon_host="" bridge_host=""
    [ -z "${ceph_pool}" ] || [ -z "${ceph_user}" ] || [ -z "${ceph_conf}" ] || [ -z "${ceph_keyring}" ] || {
        info_msg "###############################################################################\n"
        info_msg "Libvirt ceph secret_uuid = ${secret_uuid}\n"
        info_msg "###############################################################################\n"
        # mon_host=$(awk -F= '/\s*mon_host/{print $2}' ${ceph_conf} | tr , ' ')
        mon_host=$(sed -n 's/\s*mon_host\s*=\s*\(.*\)\s*/\1/p' ${ceph_conf} | tr , ' ')
        bridge_host="${kvmnode[@]}"
        info_msg "mon_host=${mon_host}\n"
        info_msg "bridge_host=${bridge_host}\n"
        ssh_func "${user}@${frontend}" "${port}" add_ceph_store "${ceph_pool}" "sys" "${ceph_pool}" "${secret_uuid}" "${ceph_user}" "${mon_host}" "${bridge_host}" "${ceph_conf}" "${cluster}"
        img_store_type=ceph
    }
    local ipaddr=""
    for ipaddr in $(array_print kvmnode); do
        ssh_func "${user}@${frontend}" "${port}" add_kvmhost "${ipaddr}" "${port}" "${cluster}"
    done

    local store_name=img_store
    case "${img_store_type}" in
        fs)
            ssh_func "${user}@${frontend}" "${port}" add_fs_store "${store_name}" "img" "${cluster}"
            ;;
        ceph)
            ssh_func "${user}@${frontend}" "${port}" add_ceph_store "${store_name}" "img" "${ceph_pool}" "${secret_uuid}" "${ceph_user}" "${mon_host}" "${bridge_host}" "${ceph_conf}" "${cluster}"
            ;;
    esac
    info_msg "upload gold image\n"
    local x86fn=$(basename ${x86_tplimg})
    file_exists "${x86_tplimg}" && {
        upload "${x86_tplimg}" "${frontend}" "${port}" "${user}" "/var/tmp/${x86fn}";
        ssh_func "${user}@${frontend}" "${port}" add_osimg_tpl "${store_name}" "${x86fn}" "/var/tmp/${x86fn}"
        ssh_func "${user}@${frontend}" "${port}" add_vm_tpl "${x86fn}" "${x86fn}" "x86_64" "${vnet}" "${img_store_type}"
        str_equal "${img_store_type}" "ceph" && ssh_func "${user}@${frontend}" "${port}" add_vm_tpl "${x86fn}_fs" "${x86fn}" "x86_64" "${vnet}" "fs"
    }
    local armfn=$(basename ${arm_tplimg})
    file_exists "${arm_tplimg}" && {
        upload "${arm_tplimg}" "${frontend}" "${port}" "${user}" "/var/tmp/${armfn}";
        ssh_func "${user}@${frontend}" "${port}" add_osimg_tpl "${store_name}" "${armfn}" "/var/tmp/${armfn}"
        ssh_func "${user}@${frontend}" "${port}" add_vm_tpl "${armfn}" "${armfn}" "aarch64" "${vnet}" "${img_store_type}"
        str_equal "${img_store_type}" "ceph" && ssh_func "${user}@${frontend}" "${port}" add_vm_tpl "${armfn}_fs" "${armfn}" "aarch64" "${vnet}" "fs"
    }
    info_msg "add datadisk tpl image\n"
    ssh_func "${user}@${frontend}" "${port}" add_dataimg_tpl "${store_name}" "data_disk"
    info_msg "Frontend init OK\n"
    info_msg "for live mirgation, modify all kvmnode /var/lib/one/.ssh/config, authorized_keys\n"
    info_msg "ALL DONE\n"
    info_msg "fix kvm startup UEFI, and VARS, /var/lib/one/remotes/etc/vmm/kvm/kvmrc && onehost sync <IP> --force\n"
    info_msg "guestos install: cloud-init cloud-initramfs-growroot/cloud-utils-growpart\n"
    cat <<'EOF'
# m h  dom mon dow   command
0 4 * * *  /usr/bin/onedb backup /root/dbbackup.$(date '+\%Y\%m\%d\%H\%M\%S')
EOF
    return 0
}
main "$@"
