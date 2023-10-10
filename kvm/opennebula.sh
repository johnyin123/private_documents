#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("6b8045e[2023-10-09T17:14:06+08:00]:opennebula.sh")
[ -e ${DIRNAME}/functions.sh ] && . ${DIRNAME}/functions.sh || { echo '**ERROR: functions.sh nofound!'; exit 1; }
################################################################################
# https://docs.opennebula.io
# Take out serial console from kernel configuration
# (it can freeze during the boot process).
# sed -i --follow-symlinks 's/console=ttyS[^ "]*//g' /etc/default/grub /etc/grub.cfg
# Gold Image:
# Download Contextualization Packages to the VM
# wget https://github.com/OpenNebula/addon-context-linux/
#######################################################################################
# # sqlite3 convert to mysql Downloading script:
#  wget http://www.redmine.org/attachments/download/6239/sqlite3-to-mysql.py
# # Converting:
#  sqlite3 /var/lib/one/one.db .dump | ./sqlite3-to-mysql.py > mysql.sql
#  mysql -u oneadmin -p opennebula < mysql.sql
# # Change /etc/one/oned.conf from
#  DB = [ backend = "sqlite" ]
# # to
#  DB = [ backend = "mysql",
#       server  = "localhost",
#       port    = 0,
#       user    = "oneadmin",
#       passwd  = "PASS",
#       db_name = "opennebula" ]
# systemctl restart opennebula opennebula-sunstone
# check logs for errors (/var/log/one/oned.log /var/log/one/sched.log /var/log/one/sunstone.log)
#########################################
init_kvmnode() {
    local phy_bridge=${1:-}
    systemctl enable libvirtd --now
    cat << EOF | tee /etc/network/interfaces
source /etc/network/interfaces.d/*
# The loopback network interface
auto lo
iface lo inet loopback
EOF
    cat << EOF | tee /etc/network/interfaces.d/br-ext
# allow-hotplug eth0
# iface eth0 inet manual

auto ${phy_bridge}
iface ${phy_bridge} inet static
#    bridge_ports eth0
    bridge_maxwait 0
#    address 192.168.168.151/24
#    gateway 192.168.168.1
EOF
}
init_frontend() {
    local pubaddr=${1}
    local sshport=${2:-22}
    local password=${3:-password}
    cat <<EOF >> /var/lib/one/.ssh/config
Host localhost
  Port ${sshport}
EOF
    echo "oneadmin:${password}" > /var/lib/one/.one/one_auth
    sed -i -E \
        -e 's|^\s*#*\s*ONEGATE_ENDPOINT\s*=.*|ONEGATE_ENDPOINT = "http://127.0.0.1:5030"|g' /etc/one/oned.conf
    systemctl enable opennebula --now
    systemctl enable opennebula-sunstone --now
    systemctl enable opennebula-gate.service --now
    echo "vnc fix"
    sed -i -E \
        -e "s|fireedge_endpoint\s*:.*|fireedge_endpoint: http://${pubaddr}:2616|g" /etc/one/sunstone-server.conf
    systemctl enable opennebula-fireedge --now
    # Verify OpenNebula Frontend installation
    sudo -u oneadmin oneuser show --json
    # # To change oneadmin password, follow the next steps:
    # oneuser passwd 0 <PASSWORD>
    # echo 'oneadmin:PASSWORD' > /var/lib/one/.one/one_auth
    echo "http://$pubaddr}:9869, Sunstone web"
    echo "http://$pubaddr}:2616, FireEdge Sunstone is the new generation OpenNebula web interface,still in BETA stage"
}
#######################################################################################
# Manage
#######################################################################################
add_cluster() {
    local c_name=${1}
    sudo -u oneadmin onecluster create ${c_name}
    sudo -u oneadmin onecluster list
}
add_kvmhost() {
    ipaddr=${1}
    sshport=${2}
    local c_name=${3:-}
    cat <<EOF >> /var/lib/one/.ssh/config
Host ${ipaddr}
  Port ${sshport}
EOF
    sudo -u oneadmin onehost create ${c_name:+--cluster ${c_name}} --im kvm --vm kvm ${ipaddr}
    sudo -u oneadmin onehost show ${ipaddr}
}
add_bridge_net() {
    local vn_name=${1}
    local phy_bridge=${2}
    local guest_ipaddr=${3:-}
    local guest_ipaddr_size=${4:-}
    local guest_gateway=${5:-}
    local guest_nameserver=${6:-}
    local c_name=${7:-}
    cat << EOF | sudo -u oneadmin tee /tmp/def.net
NAME       = "${vn_name}"
BRIDGE     = "${phy_bridge}"
BRIDGE_TYPE= "linux"
VN_MAD     = "bridge"
${guest_nameserver:+DNS        = "${guest_nameserver}"}
${guest_gateway:+GATEWAY    = "${guest_gateway}"}
AR         = [
    IP     = "${guest_ipaddr}",
    SIZE   = "${guest_ipaddr_size}",
    TYPE   = "IP4" ]
EOF
    sudo -u oneadmin onevnet create ${c_name:+--cluster ${c_name}} /tmp/def.net && rm -f /tmp/def.net
    sudo -u oneadmin onevnet show --json ${vn_name}
    # ADD Address Ranges
    # onevnet addar ${vn_name} --ip 192.168.168.50 --size 10
}
#########################################
# # Datastore
: <<'EOF'
# The Image Datastore, stores the Image repository.
# The System Datastore holds disk for running virtual machines, usually cloned from the Image Datastore.
# The Files & Kernels Datastore to store plain files used in contextualization, or VM kernels used by some hypervisors.
Datastore Layout
    Images are saved into the corresponding datastore directory (/var/lib/one/datastores/<DATASTORE ID>).
    Also, for each running virtual machine there is a directory (named after the VM ID) in the
    corresponding System Datastore. These directories contain the VM disks and additional files,
    e.g. checkpoint or snapshots.
  For example, a system with an Image Datastore (1) with three images and 3 Virtual Machines
  (VM 0 and 2 running, and VM 7 stopped) running from System Datastore 0 would present the following layout:
/var/lib/one/datastores
|-- 0/
|   |-- 0/
|   |   |-- disk.0
|   |   `-- disk.1
|   |-- 2/
|   |   `-- disk.0
|   `-- 7/
|       |-- checkpoint
|       `-- disk.0
`-- 1
    |-- 05a38ae85311b9dbb4eb15a2010f11ce
    |-- 2bbec245b382fd833be35b0b0683ed09
    `-- d0e0df1fb8cfa88311ea54dfbcfc4b0c
The canonical path for /var/lib/one/datastores can be changed in oned.conf with the DATASTORE_LOCATION configuration attribute
EOF
#########################################
# Create a System/Image Datastore
# TM_MAD:
#     shared for shared transfer mode
#     qcow2 for qcow2 transfer mode
#     ssh for ssh transfer mode
add_fs_store() {
    local name=${1}
    local type=${2}
    local c_name=${3:-}
    local val=""
    case "${type}" in
        sys)   val="TYPE = SYSTEM_DS";;
        img)   val="DS_MAD = fs";;
        *)     echo "fs store type [${type}] error"; return 1;;
    esac
    cat << EOF | sudo -u oneadmin tee /tmp/store.def
NAME    = ${name}
TM_MAD  = ssh
$(echo ${val})
EOF
    sudo -u oneadmin onedatastore create ${c_name:+--cluster ${c_name}} /tmp/store.def && rm -f /tmp/store.def
    sudo -u oneadmin onedatastore show --json ${name}
}
#########################################
# Image template
add_osimg_tpl() {
    local img_datastore=${1}
    local img_tpl_name=${2}
    local tpl_file=${3}
    [ -e "${tpl_file}" ] || {
        echo "${tpl_file} no found!!! create one 2GiB"
        truncate -s 2G "${tpl_file}"
    }
    cat << EOT | sudo -u oneadmin tee /tmp/img.tpl
NAME           = ${img_tpl_name}
TYPE           = OS
PERSISTENT     = No
PATH           = ${tpl_file}
DESCRIPTION    ="${img_tpl_name} vm tpl image."
DEV_PREFIX     ="vd"
EOT
    sudo -u oneadmin oneimage create -d ${img_datastore} /tmp/img.tpl
    # sudo -u oneadmin oneimage create --prefix vd --datastore ${img_datastore} --name ${img_tpl_name} --path ${tpl_file} --description "${img_tpl_name} vm tpl image."
    # sudo -u oneadmin oneimage nonpersistent
    sudo -u oneadmin oneimage chmod ${img_tpl_name} 604
    sudo -u oneadmin oneimage show --json ${img_tpl_name}
}
# *************** Node Setup ****************#
# # https://docs.opennebula.io/5.0/deployment/open_cloud_storage_setup/ceph_ds.html#frontend-setup
init_kvmnode_ceph() {
    local secret_uuid=${1}
    local poolname=${2}
    local secret_name=${3}
    local cluster=${4:-}
    # # COPY ceph.client.admin.keyring ceph.conf to nodes
    # rbd ${cluster:+--cluster ${cluster}} ls ${poolname} --id ${secret_name}
    # # ceph add user <secret_name> or use admin
    cat <<EPOOL | virsh secret-define /dev/stdin
<secret ephemeral='no' private='no'>
  <uuid>${secret_uuid}</uuid>
  <usage type='ceph'>
    <name>${secret_name} secret</name>
  </usage>
</secret>
EPOOL
    secret_key=$(ceph ${cluster:+--cluster ${cluster}} auth get-key client.${secret_name})
    echo ${secret_key}
    virsh secret-set-value --secret ${secret_uuid} --base64 ${secret_key}
}
# *************** Frontend Setup ****************#
# # The Frontend does not need any specific Ceph setup, it will access the Ceph cluster through the storage bridges.
# # DEFINE system and image datastores
# # Both datastores will share the same configuration parameters and Ceph pool.
add_ceph_store() {
    local name=${1}
    local type=${2}
    local poolname=${3}
    local secret_uuid=${4}
    local secret_name=${5}
    local c_name=${6:-}
    local val=""
    case "${type}" in
        sys)   val="TYPE = SYSTEM_DS";;
        img)   val="DS_MAD = ceph";;
        *)     echo "fs store type [${type}] error"; return 1;;
    esac
    cat << EOT | sudo -u oneadmin tee /tmp/store.def
NAME        = ${name}
$(echo ${val})
TM_MAD      = ceph
DISK_TYPE   = RBD
POOL_NAME   = ${poolname}
CEPH_SECRET = "${secret_uuid}"
CEPH_USER   = ${secret_name}
CEPH_HOST   = "172.16.16.2:6789 172.16.16.3:6789 172.16.16.4:6789 172.16.16.7:6789 172.16.16.8:6789"
BRIDGE_LIST = "192.168.168.151"
# List of storage bridges to access the Ceph cluster
# CEPH_CONF=/etc/ceph/armsite.conf
EOT
    sudo -u oneadmin onedatastore create ${c_name:+--cluster ${c_name}} /tmp/store.def && rm -f /tmp/store.def
    sudo -u oneadmin onedatastore show --json ${name}
}
add_vm_tpl() {
    local vmtpl_name=${1}
    local img_tpl=${2}
    local vn_name=${3}
    local dynamic='VCPU_MAX  = 16
MEMORY_MAX= 32768
MEMORY_RESIZE_MODE="BALLOONING"
HOT_RESIZE  = [
  CPU_HOT_ADD_ENABLED="YES",
  MEMORY_HOT_ADD_ENABLED="YES" ]'
    # add NETWORK_UNAME avoid none admin user, create vm from tpl, network error
    cat <<EOF | sudo -u oneadmin tee /tmp/vm512.tpl
NAME      = ${vmtpl_name}
VCPU      = 1
CPU       = 1
MEMORY    = 512
USER_INPUTS = [
  VCPU      = "M|list||1,2,4,8,16|1",
  CPU       = "M|list||0.5,1,2,4,8,16|1",
  MEMORY    = "M|list||512,1024,2048,4096,8192,16384,32768|512" ]
DISK      = [ IMAGE = "${img_tpl}", IMAGE_UNAME = oneadmin, CACHE="none", IO="native" ]
NIC_DEFAULT = [ MODEL = "virtio" ]
NIC       = [ NETWORK = "${vn_name}", NETWORK_UNAME = "oneadmin" ]
GRAPHICS  = [ TYPE = "vnc", LISTEN = "0.0.0.0"]
OS        = [ ARCH="x86_64" ]
RAW       = [
  TYPE = "kvm",
  VALIDATE = "YES",
  DATA = "<devices><serial type='pty'><target port='0'/></serial><console type='pty'><target type='serial' port='0'/></console></devices>"
]
CONTEXT            = [
    TOKEN          = "YES",
    REPORT_READY   = "YES",
    NETWORK        = "YES",
    SSH_PUBLIC_KEY = "\$USER[SSH_PUBLIC_KEY]",
    START_SCRIPT   = "#!/bin/bash
echo 'start' > /start.ok"
]
EOF
    sudo -u oneadmin onetemplate create /tmp/vm512.tpl && rm -f /tmp/vm512.tpl
    echo "for other user access this template"
    sudo -u oneadmin onetemplate chmod "${vmtpl_name}" 604
    sudo -u oneadmin onetemplate show --json "${vmtpl_name}"
}
teardown() {
    for cmd in onetemplate oneimage onevnet onedatastore onehost; do
        echo "${cmd} delete"
        ${cmd} list --no-header | awk '{print $1}' | xargs -I@ ${cmd} delete @
        ${cmd} list
    done
}
#######################################################################################
usage() {
    [ "$#" != 0 ] && echo "$*"
    cat <<EOF
${SCRIPTNAME}
        -F|--frontend   *  <addr>  Frontend address
        -N|--kvmnode       <addr>  kvm node address, multi input
        --bridge           <str>   kvm node bridge name
        --vnet             <str>   create virtual network, use <bridge>
        --adminpass        <str>   http://<frontend_address>:9869, oneadmin pass,default 'password'
        --guest_ipstart    <ipaddr> vnet guest start ip, if vnet set, must set it
        --guest_ipsize     <int>    vnet guest ip size, if vnet set, must set it
        --guest_gateway    <ipaddr> vnet guest gateway, can NULL
        --guest_dns        <ipaddr> vnet guest dns, can NULL
        --ceph_pool        <str>   ceph datastore pool name
        --ceph_user        <str>   ceph datastore user name
        --fs_store         <str>   fs datastore name
        --cluster          <str>   create opennebula cluster
        -U|--user          <user>  ssh user, default root
        -P|--port          <int>   ssh port, default 60022
        --password         <str>   ssh password(default use sshkey)
        -q|--quiet
        -l|--log <int> log level
        -V|--version
        -d|--dryrun dryrun
        -h|--help help
    exam ceph:
        ./opennebula.sh --frontend 192.168.168.150 --kvmnode 192.168.168.151 \\
           --bridge br-ext --vnet pub-net \\
           --guest_ipstart 192.168.168.3 --guest_ipsize 5 \\
           --guest_gateway 192.168.168.1 --guest_dns 192.168.1.11 \\
           --ceph_pool libvirt-pool --ceph_user admin
# apt update && apt -y install wget gnupg2 apt-transport-https
curl -fsSL https://downloads.opennebula.io/repo/repo2.key|gpg --dearmor -o /etc/apt/trusted.gpg.d/opennebula.gpg
wget -q -O- 'https://repo.dovecot.org/DOVECOT-REPO-GPG' | gpg --dearmor > /etc/apt/trusted.gpg.d/dovecot-archive-keyring.gpg
### Debian 12 / Debian 11 ###
echo "deb https://downloads.opennebula.io/repo/6.6/Debian/11 stable opennebula" | tee /etc/apt/sources.list.d/opennebula.list
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
  apt update && apt -y install vim opennebula opennebula-sunstone opennebula-gate opennebula-flow opennebula-provision opennebula-fireedge
# rbd rm libvirt-pool/one-3-5-0
# rbd snap unprotect libvirt-pool/one-3@snap
# rbd snap purge libvirt-pool/one-3
# rbd rm libvirt-pool/one-3
EOF
    exit 1
}

main() {
    local secret_uuid=$(cat /proc/sys/kernel/random/uuid)
    local user=root port=60022
    local frontend="" kvmnode=() adminpass="password" ceph_pool="" ceph_user="" bridge="" cluster="" fs_store=""
    local vnet="" guest_ipstart="" guest_ipsize="" guest_gateway="" guest_dns=""
    local opt_short="U:P:F:N:"
    local opt_long="user:,port:password:,frontend:,kvmnode:,adminpass:,ceph_pool:,ceph_user:,bridge:,cluster:,vnet:,guest_ipstart:,guest_ipsize:,guest_gateway:,guest_dns:,fs_store:,"
    opt_short+="ql:dVh"
    opt_long+="quiet,log:,dryrun,version,help"
    __ARGS=$(getopt -n "${SCRIPTNAME}" -o ${opt_short} -l ${opt_long} -- "$@") || usage
    eval set -- "${__ARGS}"
    while true; do
        case "$1" in
            -F | --frontend)   shift; frontend=${1}; shift;;
            --adminpass)       shift; adminpass=${1}; shift;;
            --cluster)         shift; cluster=${1}; shift;;
            --vnet)            shift; vnet=${1}; shift;;
            --guest_ipstart)   shift; guest_ipstart=${1}; shift;;
            --guest_ipsize)    shift; guest_ipsize=${1}; shift;;
            --guest_gateway)   shift; guest_gateway=${1}; shift;;
            --guest_dns)       shift; guest_dns=${1}; shift;;
            -N | --kvmnode)    shift; kvmnode+=(${1}); shift;;
            --bridge)          shift; bridge=${1}; shift;;
            --ceph_pool)       shift; ceph_pool=${1}; shift;;
            --ceph_user)       shift; ceph_user=${1}; shift;;
            --fs_store)        shift; fs_store=${1}; shift;;
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
    [ -z "${frontend}" ] && usage "frontend ?"
    download "${frontend}" "${port}" "${user}" "/var/lib/one/.ssh/id_rsa.pub" "authorized_keys"
    ssh_func "${user}@${frontend}" "${port}" init_frontend "${frontend}" "${port}" "${adminpass}"
    [ -z "${cluster}" ] || ssh_func "${user}@${frontend}" "${port}" add_cluster "${cluster}"
    local ipaddr=""
    for ipaddr in $(array_print kvmnode); do
        upload "authorized_keys" "${ipaddr}" "${port}" "${user}" "/var/lib/one/.ssh/authorized_keys"
        ssh_func "${user}@${ipaddr}" "${port}" "chown oneadmin.oneadmin /var/lib/one/.ssh/authorized_keys;chmod 0600 /var/lib/one/.ssh/authorized_keys"
        [ -z "${bridge}" ] || ssh_func "${user}@${ipaddr}" "${port}" init_kvmnode "${bridge}"
        [ -z "${ceph_pool}" ] || [ -z "${ceph_user}" ] || {
            ssh_func "${user}@${ipaddr}" "${port}" init_kvmnode_ceph "${secret_uuid}" "${ceph_pool}" "${ceph_user}" #"${cluster}"
        }
        ssh_func "${user}@${frontend}" "${port}" add_kvmhost "${ipaddr}" "${port}" "${cluster}"
    done
    [ -z "${vnet}" ] || [ -z "${bridge}" ] || ssh_func "${user}@${frontend}" "${port}" add_bridge_net "${vnet}" "${bridge}" "${guest_ipstart}" "${guest_ipsize}" "${guest_gateway}" "${guest_dns}" "${cluster}"
    file_exists "nebula.tpl.img" && upload nebula.tpl.img "${frontend}" "${port}" "${user}" "/var/tmp/debian.raw"
    [ -z "${ceph_pool}" ] || [ -z "${ceph_user}" ] || {
        ssh_func "${user}@${frontend}" "${port}" add_ceph_store "sys_${ceph_pool}" "sys" "${ceph_pool}" "${secret_uuid}" "${ceph_user}" "${cluster}"
        ssh_func "${user}@${frontend}" "${port}" add_ceph_store "img_${ceph_pool}" "img" "${ceph_pool}" "${secret_uuid}" "${ceph_user}" "${cluster}"
        ssh_func "${user}@${frontend}" "${port}" add_osimg_tpl "img_${ceph_pool}" "debian_onceph" "/var/tmp/debian.raw"
        ssh_func "${user}@${frontend}" "${port}" add_vm_tpl "debain_vmtpl_onceph" "debian_onceph" "${vnet}"
    }
    [ -z "${fs_store}" ] || {
        ssh_func "${user}@${frontend}" "${port}" add_fs_store "sys_${fs_store}" "sys" "${cluster}"
        ssh_func "${user}@${frontend}" "${port}" add_fs_store "img_${fs_store}" "img" "${cluster}"
        ssh_func "${user}@${frontend}" "${port}" add_osimg_tpl "img_${fs_store}" "debian_onfs" "/var/tmp/debian.raw"
        ssh_func "${user}@${frontend}" "${port}" add_vm_tpl "debain_vmtpl_onfs" "debian_onfs" "${vnet}"
    }
    cat<<EOF
onedb backup filename
oneuser create user1 password
onevm deploy 1 2
onevm list --search MAC=02:00:0c:00:4c:dd
oneuser quota
onegroup quota
oneuser batchquota userA,userB,35
onegroup batchquota
Or in Sunstone through the user/group tab
EOF
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
