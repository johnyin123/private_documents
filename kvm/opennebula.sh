#!/usr/bin/env bash
readonly DIRNAME="$(readlink -f "$(dirname "$0")")"
readonly SCRIPTNAME=${0##*/}
if [[ ${DEBUG-} =~ ^1|yes|true$ ]]; then
    exec 5> "${DIRNAME}/$(date '+%Y%m%d%H%M%S').${SCRIPTNAME}.debug.log"
    BASH_XTRACEFD="5"
    export PS4='[\D{%FT%TZ}] ${BASH_SOURCE}:${LINENO}: ${FUNCNAME[0]:+${FUNCNAME[0]}(): }'
    set -o xtrace
fi
VERSION+=("264e346[2023-10-17T09:50:32+08:00]:opennebula.sh")
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
# mysql -u root -p
# mysql> GRANT ALL PRIVILEGES ON opennebula.* TO 'oneadmin' IDENTIFIED BY '密码';
# mysql> flush privilege
#  onedb sqlite2mysql ...
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
    cat <<EOF >> /var/lib/one/.ssh/config
Host localhost
  Port ${sshport}
EOF
    echo "oneadmin:${password}" > /var/lib/one/.one/one_auth
    sed -i -E \
        -e 's|^\s*#*\s*:host:.*|:host: 0.0.0.0|g' \
        /etc/one/onegate-server.conf
    # DATASTORE_LOCATION
    sed -i -E \
        -e "s|^\s*#*\s*ONEGATE_ENDPOINT\s*=.*|ONEGATE_ENDPOINT = \"http://${pubaddr}:5030\"|g" \
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
        -e "s|fireedge_endpoint\s*:.*|fireedge_endpoint: http://${pubaddr}:2616|g" /etc/one/sunstone-server.conf
    systemctl restart opennebula opennebula-sunstone opennebula-gate.service opennebula-fireedge || true
    systemctl enable opennebula opennebula-sunstone opennebula-gate.service opennebula-fireedge || true
    echo "disable market place"
    onemarket list --no-header | awk '{print $1}' | xargs -I@ onemarket delete @
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
    local guest_ipaddr=${3}
    local guest_ipaddr_size=${4}
    local guest_net_mask=${5:-255.255.255.0}
    local guest_gateway=${6:-}
    local guest_nameserver=${7:-}
    local c_name=${8:-}
    cat << EOF | sudo -u oneadmin tee /tmp/def.net
NAME       = "${vn_name}"
BRIDGE     = "${phy_bridge}"
BRIDGE_TYPE= "linux"
VN_MAD     = "bridge"
${guest_nameserver:+DNS        = "${guest_nameserver}"}
${guest_gateway:+GATEWAY    = "${guest_gateway}"}
AR = [ IP = "${guest_ipaddr}", SIZE = "${guest_ipaddr_size}", NETWORK_MASK = "${guest_net_mask}", TYPE = "IP4" ]
EOF
    sleep 5
    sudo -u oneadmin onevnet create ${c_name:+--cluster ${c_name}} /tmp/def.net && rm -f /tmp/def.net
    sudo -u oneadmin onevnet show --json ${vn_name}
    # ADD Address Ranges
    # onevnet addar ${vn_name} --ip 192.168.168.50 --size 10
}
######################################gg###
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
    local mon_host=${6}
    local bridge_host=${7}
    local ceph_conf=$(basename ${8:-ceph.conf})
    local c_name=${9:-}
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
CEPH_HOST   = "${mon_host}"
CEPH_CONF=/etc/ceph/${ceph_conf}
BRIDGE_LIST = "${bridge_host}"
# List of storage bridges to access the Ceph cluster
EOT
    sudo -u oneadmin onedatastore create ${c_name:+--cluster ${c_name}} /tmp/store.def && rm -f /tmp/store.def
    sudo -u oneadmin onedatastore show --json ${name}
}
add_vm_tpl() {
    local vmtpl_name=${1}
    local img_tpl=${2}
    local arch=${3}
    local vn_name=${4}
    local firmware="" machine="" raw=""
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

    local dynamic='VCPU_MAX  = 16
MEMORY_MAX= 32768
MEMORY_RESIZE_MODE="BALLOONING"
HOT_RESIZE  = [ CPU_HOT_ADD_ENABLED="YES", MEMORY_HOT_ADD_ENABLED="YES" ]'
    # add NETWORK_UNAME avoid none admin user, create vm from tpl, network error
    # /etc/one/vmm_exec/vmm_exec_kvm.conf, add full path firmware file in <OVMF_UEFIS>
    # ONEGATE_ENDPOINT = "http://gate:5030"
    # CONTEXT = [ DEV_PREFIX = "sd", TARGET = "sda" ], nebula iso use scsi not ide
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
OS        = [ ARCH="${arch}", MACHINE="${machine}" ${firmware:+, FIRMWARE="${firmware}", FIRMWARE_SECURE=false} ]
CPU_MODEL = [ MODEL="host-passthrough" ]
${raw}
RAW       = [
  TYPE = "kvm",
  VALIDATE = "YES",
  DATA = "<devices><serial type='pty'><target port='0'/></serial><console type='pty'><target type='serial' port='0'/></console></devices>"
]
CONTEXT            = [
    DEV_PREFIX     = "sd",
    TARGET         = "sda",
    TOKEN          = "YES",
    REPORT_READY   = "YES",
    NETWORK        = "YES",
    SET_HOSTNAME   = "\$NAME",
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
    onevm list --no-header | awk '{print $1}' | xargs -I@ onevm recover --delete @
    for cmd in onetemplate oneimage onevnet onedatastore onehost onemarket; do
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
        env:
            SUDO=   default undefine
        -F|--frontend   *  <addr>   Frontend address
        --teardown         <addr>   teardown
        -N|--kvmnode    *  <addr>   kvm node address, multi input, NOT execute on kvmnodes!!!!, only frontend, need init manual
        --adminpass        <str>    http://<frontend_address>:9869, oneadmin pass,default 'password'
        --vnet             <str>    vnet name, use <bridge>
        --bridge           <str>    vnet used phy bridge name on kvm node
        --guest_ipstart    <ipaddr> vnet guest start ip, if vnet set, must set it
        --guest_ipsize     <int>    vnet guest ip size, if vnet set, must set it
        --guest_netmask    <mask>   vnet guset netmask, like 255.255.255.0
        --guest_gateway    <ipaddr> vnet guest gateway, can NULL
        --guest_dns        <ipaddr> vnet guest dns, can NULL
        --ceph_pool        <str>    ceph datastore pool name
        --ceph_user        <str>    ceph datastore user name
        --ceph_conf        <file>   ceph config filename
        --ceph_keyring     <file>   ceph user keyring filename
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
           --ceph_pool libvirt-pool --ceph_user admin --ceph_conf ceph/ceph.conf --ceph_keyring ceph/ceph.client.admin.keyring
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
  apt update && apt -y install vim opennebula opennebula-sunstone opennebula-gate opennebula-flow opennebula-provision opennebula-fireedge
# rbd rm libvirt-pool/one-3-5-0
# rbd snap unprotect libvirt-pool/one-3@snap
# rbd snap purge libvirt-pool/one-3
# rbd rm libvirt-pool/one-3
#
# euler 2203
# # yum group install "Virtualization Host"
yum install libvirt lvm2 bridge-utils ebtables iptables ipset qemu-block-rbd qemu-block-ssh
yum install ceph-common
yum install xmlrpc-c rubygems rubygem-rexml rubygem-sqlite3

useradd oneadmin --no-create-home --home-dir /var/lib/one --shell /bin/bash
mkdir -m0755 /var/lib/one/remotes && chown -R oneadmin.oneadmin /var/lib/one
usermod -a -G libvirt oneadmin
usermod -a -G kvm oneadmin
echo '%oneadmin ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/oneadmin
su - oneadmin -c "ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa"
ln -s /usr/libexec/qemu-kvm /usr/bin/qemu-kvm-one
./install.sh -u oneadmin -g oneadmin -6
# # install below files
# /usr/lib/one/onegate-proxy/onegate-proxy.rb 0644
# /usr/bin/onegate-proxy                      0755
# /var/lib/one/remotes/etc                    0644
# cat << EOF >> /etc/libvirt/qemu.conf
# user = "oneadmin"
# group = "oneadmin"
# dynamic_ownership = 0
# EOF
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
    2. Shared datastores must be mounted on all the nodes.
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
    [ "$(array_size kvmnode)" -gt "0" ] || usage "kvmnode ?"
    [ -z "${ceph_conf}" ] || file_exists "${ceph_conf}" || exit_msg "${ceph_conf} no found\n"
    [ -z "${ceph_keyring}" ] || file_exists "${ceph_keyring}" || exit_msg "${ceph_keyring} no found\n"
    download "${frontend}" "${port}" "${user}" "/var/lib/one/.ssh/id_rsa.pub" "authorized_keys"
    ssh_func "${user}@${frontend}" "${port}" init_frontend "${frontend}" "${port}" "${adminpass}"
    [ -z "${cluster}" ] || ssh_func "${user}@${frontend}" "${port}" add_cluster "${cluster}"
    [ -z "${vnet}" ] || [ -z "${bridge}" ] || ssh_func "${user}@${frontend}" "${port}" add_bridge_net "${vnet}" "${bridge}" "${guest_ipstart}" "${guest_ipsize}" "${guest_netmask}" "${guest_gateway}" "${guest_dns}" "${cluster}"
    local x86fn=$(basename ${x86_tplimg})
    local armfn=$(basename ${arm_tplimg})
    file_exists "${x86_tplimg}" && upload "${x86_tplimg}" "${frontend}" "${port}" "${user}" "/var/tmp/${x86fn}";
    file_exists "${arm_tplimg}" && upload "${arm_tplimg}" "${frontend}" "${port}" "${user}" "/var/tmp/${armfn}";
    [ -z "${ceph_pool}" ] || [ -z "${ceph_user}" ] || [ -z "${ceph_conf}" ] || [ -z "${ceph_keyring}" ] || {
        info_msg  "###############################################################################\n"
        info_msg  "Libvirt ceph secret_uuid = ${secret_uuid}\n"
        info_msg  "###############################################################################\n"
        local mon_host=$(awk -F= '/\s*mon_host/{print $2}' ${ceph_conf} | tr , ' ')
        local bridge_host="${kvmnode[@]}"
        info_msg "mon_host=${mon_host}\n"
        info_msg "bridge_host=${bridge_host}\n"
        ssh_func "${user}@${frontend}" "${port}" add_ceph_store "sys_${ceph_pool}" "sys" "${ceph_pool}" "${secret_uuid}" "${ceph_user}" "${mon_host}" "${bridge_host}" "${ceph_conf}" "${cluster}"
        ssh_func "${user}@${frontend}" "${port}" add_ceph_store "img_${ceph_pool}" "img" "${ceph_pool}" "${secret_uuid}" "${ceph_user}" "${mon_host}" "${bridge_host}" "${ceph_conf}" "${cluster}"
        ssh_func "${user}@${frontend}" "${port}" add_osimg_tpl "img_${ceph_pool}" "${x86fn}_ceph" "/var/tmp/${x86fn}"
        ssh_func "${user}@${frontend}" "${port}" add_vm_tpl "${x86fn}_vmtpl_ceph" "${x86fn}_ceph" "x86_64" "${vnet}"
        ssh_func "${user}@${frontend}" "${port}" add_osimg_tpl "img_${ceph_pool}" "${armfn}_ceph" "/var/tmp/${armfn}"
        ssh_func "${user}@${frontend}" "${port}" add_vm_tpl "${armfn}_vmtpl_ceph" "${armfn}_ceph" "aarch64" "${vnet}"
    }
    [ -z "${fs_store}" ] || {
        ssh_func "${user}@${frontend}" "${port}" add_fs_store "sys_${fs_store}" "sys" "${cluster}"
        ssh_func "${user}@${frontend}" "${port}" add_fs_store "img_${fs_store}" "img" "${cluster}"
        ssh_func "${user}@${frontend}" "${port}" add_osimg_tpl "img_${fs_store}" "${x86fn}_onfs" "/var/tmp/${x86fn}"
        ssh_func "${user}@${frontend}" "${port}" add_vm_tpl "${x86fn}_vmtpl_onfs" "${x86fn}_onfs" "x86_64" "${vnet}"
        ssh_func "${user}@${frontend}" "${port}" add_osimg_tpl "img_${fs_store}" "${armfn}_onfs" "/var/tmp/${armfn}"
        ssh_func "${user}@${frontend}" "${port}" add_vm_tpl "${armfn}_vmtpl_onfs" "${armfn}_onfs" "aarch64" "${vnet}"
    }
    local ipaddr=""
    for ipaddr in $(array_print kvmnode); do
        ssh_func "${user}@${frontend}" "${port}" add_kvmhost "${ipaddr}" "${port}" "${cluster}"
    done
    info_msg "Frontend init OK\n"
    cat <<EOF
# #  init kvm nodes
echo $(cat authorized_keys) > /var/lib/one/.ssh/authorized_keys
chown oneadmin.oneadmin /var/lib/one/.ssh/authorized_keys
chmod 0600 /var/lib/one/.ssh/authorized_keys
[ -e /var/lib/one/.ssh/id_rsa ] || su - oneadmin -c "ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa"
cat <<EOBR  > /etc/sysconfig/network-scripts/ifcfg-${bridge}
DEVICE="${bridge}"
ONBOOT="yes"
TYPE="Bridge"
BOOTPROTO="none"
STP="off"
EOBR
echo "copy ${ceph_conf} ${ceph_keyring} ==> /etc/ceph/"

# # COPY ceph.client.admin.keyring ceph.conf to nodes
# # https://docs.opennebula.io/6.6/open_cluster_deployment/storage_setup/ceph_ds.html
cat <<EPOOL | virsh secret-define /dev/stdin
<secret ephemeral='no' private='no'>
  <uuid>${secret_uuid}</uuid>
  <usage type='ceph'>
    <name>${ceph_user} secret</name>
  </usage>
</secret>
EPOOL
# ceph auth get-key client.${ceph_user})
# cat /etc/ceph/ceph.client.${ceph_user}.keyring  | awk '/key = /{print \$3}'
# virsh secret-set-value --secret ${secret_uuid} --base64 ${secret_key} 2>/dev/null
# virsh secret-list
EOF
    info_msg "for live mirgation, modify all kvmnode /var/lib/one/.ssh/config, authorized_keys\n"
    info_msg "ALL DONE\n"
    return 0
}
main "$@"
