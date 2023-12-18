# yum -y install python3-devel python3-libselinux libffi-devel git gcc openssl-devel dbus-devel glib2-devel docker
# use kolla, no need install libvirtd
# source ${KOLLA_DIR}/venv3/bin/activate && mkdir -p ~/offline && pip freeze > requirements.txt && pip download -r requirements.txt
# docker images | grep kolla | grep -v local | awk '{print $1,$2}' | while read -r image tag; do
#   newimg=`echo ${image} | cut -d / -f2-`
#   docker tag ${image}:${tag} localhost:4000/${newimg}:${tag}
#   docker push localhost:4000/${newimg}:${tag}
# done
insec_registry=10.170.6.105:5000
########################################
CTRL_X86=(172.16.1.210 172.16.1.211)
COMPUTE_X86=(172.16.1.212)
COMPUTE_ARM=(172.16.1.214)
INT_VIP_ADDR=172.16.1.213
########################################
KVM=qemu
# https://releases.openstack.org/
OPENSTACK_VER=master
KOLLA_DIR=/kolla
ADMIN_PASS=Admin@2023
HAPROXY=yes
WEBUI_SKYLINE=no
WEBUI_HORIZON=yes
USE_LVM=no
# VG_NAME=cindervg
# # # # # # # all (compute/controller) node start
# Kolla puts nearly all of persistent data in Docker volumes. defaults to /var/lib/docker directory.
cfg_file=/etc/docker/daemon.json
mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
{
  "registry-mirrors": [ "https://docker.mirrors.ustc.edu.cn", "http://hub-mirror.c.163.com" ],
  "insecure-registries": [ "quay.io"${insec_registry:+, \"${insec_registry}\"} ],
  "exec-opts": ["native.cgroupdriver=systemd", "native.umask=normal" ],
  "storage-driver": "overlay2",
  "data-root": "/var/lib/docker",
  "bridge": "none",
  "ip-forward": false,
  "iptables": false
}
EOF
cfg_file=/etc/systemd/system/docker.service.d/kolla.conf
mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
[Service]
MountFlags=shared
EOF
systemctl daemon-reload
systemctl restart docker
systemctl enable docker
# # store node
# use lvm backend store
command -v "pvcreate" &> /dev/null || yum -y install lvm2
pvcreate /dev/vdb
vgcreate ${VG_NAME:-cinder-volumes} /dev/vdb
mkdir -p ${KOLLA_DIR} && python3 -m venv ${KOLLA_DIR}/venv3 && source ${KOLLA_DIR}/venv3/bin/activate
# # # # # # # all (compute/controller) node end
[ -f "${HOME:-~}/.ssh/id_rsa" ] || ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa
echo "echo '$(cat ~/.ssh/id_rsa.pub)' >> ~/.ssh/authorized_keys"
# ssh -p60022 localhost "true" || echo "ssh-copy-id"
# cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
sed --quiet -i -E \
    -e '/(127.0.0.1\s*).*/!p' \
    -e '$a127.0.0.1 localhost' \
    /etc/hosts
# # # # # # # # # # # # # # # # # # # # # offline start
cat <<EOF
pip install --no-index --find-links ${KOLLA_DIR}/pyenv/ --upgrade pip
pip install --no-index --find-links ${KOLLA_DIR}/pyenv/ -r ${KOLLA_DIR}/pyenv/requirements.txt
# # # # all compute nodes ends here
# cd ${KOLLA_DIR} && pip install --no-index --find-links ${KOLLA_DIR}/pyenv/ ./kolla
# cd ${KOLLA_DIR} && pip install --no-index --find-links ${KOLLA_DIR}/pyenv/ ./kolla-ansible
EOF
# # # # # # # # # # # # # # # # # # # # # offline end
# # # # # # # # # # # # # # # # # # # # # online start
cfg_file=~/.pip/pip.conf
mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
[global]
trusted-host = mirrors.aliyun.com
index-url = https://mirrors.aliyun.com/pypi/simple
# index-url = https://pypi.tuna.tsinghua.edu.cn/simple
EOF
pip install --upgrade pip
pip install pip-search
pip install 'ansible>=6,<8' dbus-python selinux docker python-openstackclient
# # pip install -i https://mirrors.aliyun.com/pypi/simple/ --ignore-installed PyYAML kolla-ansible
cd ${KOLLA_DIR} && git clone --depth=1 https://github.com/openstack/kolla
cd ${KOLLA_DIR} && git clone --depth=1 https://github.com/openstack/kolla-ansible
cd ${KOLLA_DIR} && pip install ./kolla
cd ${KOLLA_DIR} && pip install ./kolla-ansible
# pip install --no-index --find-links ${KOLLA_DIR}/pyenv/ "kolla==17.0.0"
# kolla-build --base ubuntu --base-arch aarch64 --list-images
# kolla-build --base ubuntu --base-arch aarch64 --tag master-ubuntu-jammy-aarch64 ..
# kolla-build --base ubuntu --base-arch x86_64  --tag master-ubuntu-jammy
# # # # # # # # # # # # # # # # # # # # # online end
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# start init opnstack
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
cfg_file=/etc/ansible/ansible.cfg
mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
[defaults]
host_key_checking=False
pipelining=True
forks=100
EOF
cp -r ${KOLLA_DIR}/kolla-ansible/etc/kolla /etc/ 2>/dev/null || \
    cp -r ${KOLLA_DIR}/venv3/share/kolla-ansible/etc_examples/kolla /etc/
cp ${KOLLA_DIR}/kolla-ansible/ansible/inventory/* ${KOLLA_DIR} 2>/dev/null || \
    cp ${KOLLA_DIR}/venv3/share/kolla-ansible/ansible/inventory/* ${KOLLA_DIR}
command -v "crudini" &> /dev/null || pip install crudini
# # Host with a host variable.
# [control]
# control01 api_interface=eth3
# # Group with a group variable.
# [control:vars]
# api_interface=eth4
crudini --del ${KOLLA_DIR}/multinode control
crudini --del ${KOLLA_DIR}/multinode network
crudini --del ${KOLLA_DIR}/multinode compute
crudini --del ${KOLLA_DIR}/multinode monitoring
crudini --del ${KOLLA_DIR}/multinode storage
crudini --del ${KOLLA_DIR}/multinode deployment
crudini --del ${KOLLA_DIR}/multinode all:vars
crudini --del ${KOLLA_DIR}/multinode all
# 192.168.122.24 ansible_ssh_user=<ssh-username> ansible_become=True ansible_private_key_file=<path/to/private-key-file>
crudini --set ${KOLLA_DIR}/multinode storage     # no storage
crudini --set ${KOLLA_DIR}/multinode monitoring  # no monitoring
crudini --set ${KOLLA_DIR}/multinode deployment  "localhost ansible_connection=local"
for node in ${CTRL_X86[@]}; do
    crudini --set ${KOLLA_DIR}/multinode control "${node} host_arch= uselvm=${USE_LVM}"
    crudini --set ${KOLLA_DIR}/multinode all "${node} host_arch= uselvm=${USE_LVM}"
done
for node in ${COMPUTE_ARM[@]}; do
    crudini --set ${KOLLA_DIR}/multinode network "${node} host_arch=-aarch64 uselvm=${USE_LVM}"
    crudini --set ${KOLLA_DIR}/multinode compute "${node} host_arch=-aarch64 uselvm=${USE_LVM}"
    crudini --set ${KOLLA_DIR}/multinode all "${node} host_arch=-aarch64 uselvm=${USE_LVM}"
done
for node in ${COMPUTE_X86[@]}; do
    crudini --set ${KOLLA_DIR}/multinode network "${node} host_arch= uselvm=${USE_LVM}"
    crudini --set ${KOLLA_DIR}/multinode compute "${node} host_arch= uselvm=${USE_LVM}"
    crudini --set ${KOLLA_DIR}/multinode all "${node} host_arch= uselvm=${USE_LVM}"
done
crudini --set ${KOLLA_DIR}/multinode all:vars "ansible_port=60022"
crudini --set ${KOLLA_DIR}/multinode all:vars "ansible_python_interpreter=${KOLLA_DIR}/venv3/bin/python3"
crudini --set ${KOLLA_DIR}/multinode all:vars "openstack_version=${OPENSTACK_VER:-master}"
crudini --set ${KOLLA_DIR}/multinode all:vars "virt_type=${KVM:-kvm}"
crudini --set ${KOLLA_DIR}/multinode all:vars "net_if=eth0"
crudini --set ${KOLLA_DIR}/multinode all:vars "external_interface=eth1"
crudini --set ${KOLLA_DIR}/multinode all:vars "vip_addr=${INT_VIP_ADDR:-192.168.1.100}"
crudini --set ${KOLLA_DIR}/multinode all:vars "use_haproxy=${HAPROXY:-yes}"
crudini --set ${KOLLA_DIR}/multinode all:vars "uselvm=${USE_LVM}"
crudini --set ${KOLLA_DIR}/multinode all:vars "useceph=no"
crudini --set ${KOLLA_DIR}/multinode all:vars "web_skyline=${WEBUI_SKYLINE:-no}"
crudini --set ${KOLLA_DIR}/multinode all:vars "web_horizon=${WEBUI_HORIZON:-yes}"
# # Deploy All-In-One/multinode
sed --quiet -i -E \
    -e '/(openstack_tag_suffix|enable_mariabackup)\s*:.*/!p' \
    -e '$aopenstack_tag_suffix: "{{ host_arch }}"' \
    -e '$aenable_mariabackup: "yes"' \
    /etc/kolla/globals.yml
# glance_backend_file: "yes"
# glance_file_datadir_volume: "/path/to/shared/storage/" ## shared storage
sed --quiet -i -E \
    -e '/(config_strategy|kolla_base_distro|network_interface|nova_compute_virt_type|openstack_release)\s*:.*/!p' \
    -e "\$aconfig_strategy: \"COPY_ALWAYS\""   \
    -e "\$akolla_base_distro: \"ubuntu\""    \
    -e "\$anetwork_interface: \"{{ net_if }}\""      \
    -e "\$anova_compute_virt_type: \"{{ virt_type }}\""       \
    -e "\$aopenstack_release: \"{{ openstack_version }}\""       \
    /etc/kolla/globals.yml
sed --quiet -i -E \
    -e '/(enable_skyline|enable_horizon)\s*:.*/!p' \
    -e "\$aenable_skyline: \"{{ web_skyline }}\""  \
    -e "\$aenable_horizon: \"{{ web_horizon }}\""  \
    /etc/kolla/globals.yml

# linuxbridge is *EXPERIMENTAL* in Neutron since Zed
sed --quiet -i -E \
    -e '/(enable_neutron_provider_networks|neutron_external_interface|neutron_plugin_agent|enable_neutron_agent_ha)\s*:.*/!p' \
    -e '$aenable_neutron_provider_networks: "yes"' \
    -e '$aneutron_plugin_agent: "openvswitch"'   \
    -e "\$aneutron_external_interface: \"{{ external_interface }}\"" \
    -e '$aenable_neutron_agent_ha: "yes"'        \
    /etc/kolla/globals.yml

sed --quiet -i -E \
    -e '/(docker_registry|docker_registry_insecure|docker_namespace)\s*:.*/!p' \
    -e "\$adocker_registry: \"${insec_registry:-docker.io}\""  \
    -e "\$adocker_registry_insecure: \"yes\"" \
    -e "\$adocker_namespace: \"kolla\"" \
    /etc/kolla/globals.yml

# # Deploy HA Cluster
# simply change three more settings to deploy a HA cluster.
# a free static IP for the external cluster VIP on your local subnet. Make sure to adjust it to match your local subnet.
sed --quiet -i -E \
    -e '/(enable_haproxy|kolla_internal_vip_address|kolla_external_vip_address)\s*:.*/!p' \
    -e "\$aenable_haproxy: \"{{ use_haproxy }}\""  \
    -e "\$akolla_internal_vip_address: \"{{ vip_addr }}\""  \
    -e "\$akolla_external_vip_address: \"{{ vip_addr }}\""  \
    /etc/kolla/globals.yml
# Block Storage service, use LVM cinder
sed --quiet -i -E \
    -e '/(enable_cinder|enable_cinder_backup|enable_cinder_backend_lvm|cinder_volume_group)\s*:.*/!p' \
    -e "\$aenable_cinder: \"{{ uselvm | bool or useceph | bool }}\""  \
    -e "\$aenable_cinder_backup: \"yes\""  \
    -e "\$aenable_cinder_backend_lvm: \"{{ uselvm }}\""  \
    -e "\$acinder_volume_group: \"${VG_NAME:-cinder-volumes}\""  \
    /etc/kolla/globals.yml
grep -v '^\s*$\|^\s*\#' /etc/kolla/globals.yml
# 配置nova文件, virth_type kvm/qemu, 加入超卖
# /etc/kolla/config/nova.conf
# /etc/kolla/config/nova/${node}/nova.conf
# /etc/kolla/config/nova/nova-scheduler.conf
for node in ${COMPUTE_X86[@]}; do
    cfg_file=/etc/kolla/config/nova/${node}/nova.conf
    mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
[DEFAULT]
ram_allocation_ratio=2.0
cpu_allocation_ratio=10.0
# disk_allocation_ratio=2.0
[libvirt]
virt_type = ${KVM:-kvm}
# # x86_64 qemu mode. use cpu_mode=none
$([ "${KVM:-kvm}" == "qemu" ]  && { echo "cpu_mode=none"; })
EOF
done
for node in ${COMPUTE_ARM[@]}; do
    cfg_file=/etc/kolla/config/nova/${node}/nova.conf
    mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
[DEFAULT]
ram_allocation_ratio=2.0
cpu_allocation_ratio=10.0
# disk_allocation_ratio=2.0
[libvirt]
virt_type = ${KVM:-kvm}
# # aarch64 openeuler qemu mode, use "max" cpu model!!
$([ "${KVM:-kvm}" == "qemu" ]  && { echo "cpu_mode=custom" ; echo "cpu_models=max"; })
EOF
done

# cpu_mode :host-model, host-passthrough, custom, none
# https://docs.openstack.org/nova/latest/admin/cpu-models.html
# # aarch64 openeuler qemu mode, use "max" cpu model!!
# crudini --set /etc/kolla/nova-compute/nova.conf  "libvirt" "cpu_mode" "custom"
# crudini --set /etc/kolla/nova-compute/nova.conf  "libvirt" "cpu_models" "max"
# # docker restart nova_compute
# If you set the virt_type to qemu then nova will report all the supported archs as compute capability
# Currently, in many places, Nova's libvirt driver makes decisions on how
# to configure guest XML based on *host* CPU architecture
# ("caps.host.cpu.arch"). That is not optimal in all cases. So all of
# the said code needs to be reworked to make those decisions based on
# *guest* CPU architecture (i.e. "guest.arch", which should be set based
# on the image metadata property, `hw_architecture`). A related piece of
# work is to distinguish between hosts that can do AArch64 (or PPC64, etc)
# via KVM (which is hardware-accelerated) vs. those that can only do it
# via plain emulation ("TCG") — this is to ensure that guests are not
# arbitrarily scheduled on hosts that are incapable of hardware
# acceleration, thus losing out on performance-related benefits
cfg_file=/etc/kolla/config/nova.conf
mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
[scheduler]
image_metadata_prefilter = True
[filter_scheduler]
# 镜像属性过滤器时要使用的默认架构, hw_architecture未指定，默认为x86_64
image_properties_default_architecture = x86_64
EOF
cfg_file=/etc/kolla/config/nova/nova-compute.conf
mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
[DEFAULT]
ram_allocation_ratio=2.0
cpu_allocation_ratio=10.0
# disk_allocation_ratio=2.0

[libvirt]
virt_type = ${KVM:-kvm}
EOF
# 关闭创建新卷
cfg_file=/etc/kolla/config/horizon/custom_local_settings
mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
LAUNCH_INSTANCE_DEFAULTS = {'create_volume': False}
EOF
# linuxbridge must open experimental
cfg_file=/etc/kolla/config/neutron.conf
mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
# [experimental]
# linuxbridge = true
EOF
cfg_file=/etc/kolla/config/neutron/ml2_conf.ini
mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
# [ml2]
# [ml2_type_vlan]
# network_vlan_ranges = physnet1:100:200
# [ml2_type_vxlan]
# [ml2_type_flat]
EOF
# force_config_drive = True, It is also possible to force the config drive by specifying the img_config_drive=mandatory property in the image.
# ########################ceph start
for node in ${COMPUTE_X86[@]} ${COMPUTE_ARM[@]}; do
#. When using external Ceph, there may be no nodes defined in the storage
#  group.  This will cause Cinder and related services relying on this group to
#  fail.  In this case, operator should add some nodes to the storage group,
#  all the nodes where ``cinder-volume`` and ``cinder-backup`` will run:
#      [storage]
#      control01
    crudini --set ${KOLLA_DIR}/multinode storage ${node}
done
mkdir -p /etc/kolla/config/glance/ \
         /etc/kolla/config/cinder/cinder-volume/ \
         /etc/kolla/config/cinder/cinder-backup/ \
         /etc/kolla/config/nova/ \
         /etc/kolla/config/zun/zun-compute/
# extern ceph
sed --quiet -i -E \
    -e '/(enable_ceph|zun_configure_for_cinder_ceph)\s*:.*/!p' \
    -e '$aenable_ceph: "no"'         \
    -e '$azun_configure_for_cinder_ceph: "yes"' \
    /etc/kolla/globals.yml

sed --quiet -i -E \
    -e '/(enable_cinder|enable_cinder_backup|glance_backend_ceph|cinder_backend_ceph|nova_backend_ceph)\s*:.*/!p' \
    -e '$aenable_cinder: "yes"'  \
    -e '$aenable_cinder_backup: "yes"'  \
    -e '$aglance_backend_ceph: "yes"'  \
    -e '$acinder_backend_ceph: "yes"'  \
    -e '$anova_backend_ceph: "yes"'  \
    /etc/kolla/globals.yml
#    -e "s/^\s*#*gnocchi_backend_storage\s*:.*/gnocchi_backend_storage: \"ceph\"/g"  \
#    -e "s/^\s*#*enable_manila_backend_cephfs_native\s*:.*/enable_manila_backend_cephfs_native: \"yes\"/g"  \
# # glance ceph
GLANCE_USER=glance
GLANCE_POOL=images
GLANCE_KEYRING=ceph.client.${GLANCE_USER}.keyring
sed --quiet -i -E \
    -e '/(ceph_glance_keyring|ceph_glance_user|ceph_glance_pool_name)\s*:.*/!p' \
    -e "\$aceph_glance_keyring: \"${GLANCE_KEYRING}\""  \
    -e "\$aceph_glance_user: \"${GLANCE_USER}\""  \
    -e "\$aceph_glance_pool_name: \"${GLANCE_POOL}\""  \
    /etc/kolla/globals.yml
cfg_file=/etc/kolla/config/glance.conf
mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
[GLOBAL]
show_image_direct_url = True
EOF
# # cinder ceph
CINDER_USER=cinder
CINDER_POOL=volumes
CINDER_KEYRING=ceph.client.${CINDER_USER}.keyring
CINDER_USER_BACKUP=cinder-backup
CINDER_POOL_BACKUP=backups
CINDER_KEYRING_BACKUP=ceph.client.${CINDER_USER_BACKUP}.keyring
sed --quiet -i -E \
    -e '/(ceph_cinder_keyring|ceph_cinder_user|ceph_cinder_pool_name|ceph_cinder_backup_keyring|ceph_cinder_backup_user|ceph_cinder_backup_pool_name)\s*:.*/!p' \
    -e "\$aceph_cinder_keyring: \"${CINDER_KEYRING}\""  \
    -e "\$aceph_cinder_user: \"${CINDER_USER}\""  \
    -e "\$aceph_cinder_pool_name: \"${CINDER_POOL}\""  \
    -e "\$aceph_cinder_backup_keyring: \"${CINDER_KEYRING_BACKUP}\""  \
    -e "\$aceph_cinder_backup_user: \"${CINDER_USER_BACKUP}\""  \
    -e "\$aceph_cinder_backup_pool_name: \"${CINDER_POOL_BACKUP}\""  \
    /etc/kolla/globals.yml
# # nova ceph
NOVA_USER=nova
NOVA_POOL=vms
NOVA_KEYRING=ceph.client.${NOVA_USER}.keyring
# ceph_nova_user`` (by default it's the same as ``ceph_cinder_user``)
sed --quiet -i -E \
    -e '/(ceph_cinder_keyring|ceph_nova_keyring|ceph_nova_user|ceph_nova_pool_name)\s*:.*/!p' \
    -e "\$aceph_cinder_keyring: \"${CINDER_KEYRING}\""  \
    -e "\$aceph_nova_keyring: \"${NOVA_KEYRING}\""  \
    -e "\$aceph_nova_user: \"${NOVA_USER}\""  \
    -e "\$aceph_nova_pool_name: \"${NOVA_POOL}\""  \
    /etc/kolla/globals.yml
grep '^[^#]' /etc/kolla/globals.yml

cat <<EOF
# https://docs.openstack.org/kolla-ansible/latest/reference/storage/external-ceph-guide.html
cluster=armsite
for p in ${GLANCE_POOL} ${CINDER_POOL} ${CINDER_POOL_BACKUP} ${NOVA_POOL}; do
    ceph ${cluster:+--cluster ${cluster}} osd pool create ${p} 128 && rbd ${cluster:+--cluster ${cluster}} pool init ${p}
done
ceph ${cluster:+--cluster ${cluster}} auth get-or-create client.${GLANCE_USER} mon "profile rbd" osd "profile rbd pool=${GLANCE_POOL}" mgr "profile rbd pool=${GLANCE_POOL}"
ceph ${cluster:+--cluster ${cluster}} auth get-or-create client.${CINDER_USER} mon "profile rbd" osd "profile rbd pool=${CINDER_POOL}, profile rbd pool=${NOVA_POOL}, profile rbd-read-only pool=${GLANCE_POOL}" mgr "profile rbd pool=${CINDER_POOL}, profile rbd pool=${NOVA_POOL}"
ceph ${cluster:+--cluster ${cluster}} auth get-or-create client.${CINDER_USER_BACKUP} mon "profile rbd" osd "profile rbd pool=${CINDER_POOL_BACKUP}" mgr "profile rbd pool=${CINDER_POOL_BACKUP}"
ceph ${cluster:+--cluster ${cluster}} auth get-or-create client.${NOVA_USER} mon "profile rbd" osd "profile rbd pool=${NOVA_POOL}" mgr "profile rbd pool=${NOVA_POOL}"
for p in ${GLANCE_USER} ${CINDER_USER} ${CINDER_USER_BACKUP} ${NOVA_USER}; do
    ceph ${cluster:+--cluster ${cluster}} auth get-or-create client.${p} | tee ${cluster:-ceph}.client.${p}.keyring
done
EOF

cat <<EOF
cat <<EO_GLOBALS >> /etc/kolla/globals.yml
glance_ceph_backends:
  - name: "rbd"
    type: "rbd"
    cluster: "ceph"
    enabled: "{{ glance_backend_ceph | bool }}"
  - name: "another-rbd"
    type: "rbd"
    cluster: "rbd1"
    enabled: "{{ glance_backend_ceph | bool }}"
cinder_ceph_backends:
  - name: "rbd-1"
    cluster: "ceph"
    enabled: "{{ cinder_backend_ceph | bool }}"
  - name: "rbd-2"
    cluster: "rbd2"
    availability_zone: "az2"
    enabled: "{{ cinder_backend_ceph | bool }}"
EO_GLOBALS
EOF

cat <<EOF
cat ceph.conf > /etc/kolla/config/glance/ceph.conf
cat ceph.conf > /etc/kolla/config/cinder/ceph.conf
cat ceph.conf > /etc/kolla/config/nova/ceph.conf
cat ceph.conf > /etc/kolla/config/zun/zun-compute/ceph.conf
cat ceph.client.glance.keyring        > /etc/kolla/config/glance/ceph.client.glance.keyring
cat ceph.client.cinder.keyring        > /etc/kolla/config/cinder/cinder-volume/ceph.client.cinder.keyring
cat ceph.client.cinder.keyring        > /etc/kolla/config/cinder/cinder-backup/ceph.client.cinder.keyring
cat ceph.client.cinder-backup.keyring > /etc/kolla/config/cinder/cinder-backup/ceph.client.cinder-backup.keyring
cat ceph.client.cinder.keyring        > /etc/kolla/config/nova/ceph.client.cinder.keyring
cat ceph.client.cinder.keyring        > /etc/kolla/config/zun/zun-compute/ceph.client.cinder.keyring
cat ceph.client.nova.keyring          > /etc/kolla/config/nova/ceph.client.nova.keyring
EOF
cat <<EOF
# https://docs.ceph.com/en/latest/rbd/rbd-openstack/
# https://docs.openstack.org/kolla-ansible/latest/reference/storage/external-ceph-guide.html
Gnocchi: 资源索引服务
    Configuring Gnocchi for Ceph includes following steps:
    Configure Ceph authentication details in /etc/kolla/globals.yml:
    ceph_gnocchi_keyring
    (default: ceph.client.gnocchi.keyring)
    ceph_gnocchi_user (default: gnocchi)
    ceph_gnocchi_pool_name (default: gnocchi)
    Copy Ceph configuration file to /etc/kolla/config/gnocchi/ceph.conf
    Copy Ceph keyring to /etc/kolla/config/gnocchi/<ceph_gnocchi_keyring>
Manila: 共享文件服务
    Configuring Manila for Ceph includes following steps:
    Configure CephFS backend by setting enable_manila_backend_cephfs_native to true
    Configure Ceph authentication details in /etc/kolla/globals.yml:
    ceph_manila_keyring (default: ceph.client.manila.keyring)
    ceph_manila_user (default: manila)
    Copy Ceph configuration file to /etc/kolla/config/manila/ceph.conf
    Copy Ceph keyring to /etc/kolla/config/manila/<ceph_manila_keyring>
EOF
# ########################ceph end
cat <<'EXTERN_MYSQL'
# https://docs.openstack.org/kolla-ansible/latest/reference/databases/external-mariadb-guide.html
# Enabling External MariaDB support
# # add MariaDB hosts, all nodes!!!
mariadb_ip=172.16.1.210
mariadb_fqdn=openstack.mydb.local
mariadb_user=dbuser
mariadb_pass=PAssw0rd

crudini --del ${KOLLA_DIR}/multinode "mariadb"
crudini --set ${KOLLA_DIR}/multinode "mariadb" "${mariadb_fqdn}"

# alll nodes must can connect mariadb.
sed --quiet -i -E \
    -e '/\s(openstack.mydb.local)\s*.*/!p' \
    -e "\$a${mariadb_ip} ${mariadb_fqdn}" \
    /etc/hosts

sed --quiet -i -E \
    -e '/(enable_mariadb|database_address|enable_external_mariadb_load_balancer)\s*:.*/!p' \
    -e '$aenable_mariadb: "no"' \
    -e "\$adatabase_address: \"${mariadb_fqdn}\"" \
    -e '$aenable_external_mariadb_load_balancer: "no"' \
    /etc/kolla/globals.yml

sed --quiet -i -E \
    -e '/(use_preconfigured_databases|use_common_mariadb_user|database_user)\s*:.*/!p' \
    -e '$ause_preconfigured_databases: "yes"' \
    -e '$ause_common_mariadb_user: "yes"' \
    -e "\$adatabase_user: \"${mariadb_user}\"" \
    /etc/kolla/globals.yml

cat /etc/hosts
grep -v '^\s*$\|^\s*\#' /etc/kolla/globals.yml
sed -i -r -e "s/([a-z_]{0,}database_password:+)(.*)$/\1 ${mariadb_pass}/gi" /etc/kolla/passwords.yml

create_mysql_db() {
    local db=${1}
    local user=${2}
    local pass=${3}
    echo "Add a User [${user}/${pass}] and Database [${db}] on MariaDB."
    cat <<EOF | mysql ${MYSQL_PASS:+"-uroot -p${MYSQL_PASS}"}
DROP DATABASE IF EXISTS ${db};
CREATE DATABASE ${db} CHARACTER SET utf8;
GRANT ALL PRIVILEGES ON ${db}.* TO '${user}'@'localhost' IDENTIFIED BY '${pass}';
GRANT ALL PRIVILEGES ON ${db}.* TO '${user}'@'%' IDENTIFIED BY '${pass}';
FLUSH PRIVILEGES;
EOF
}
DATABASES=(cinder keystone glance nova nova_api nova_cell0 placement neutron neutron_ml2 heat)
for db in ${DATABASES[@]}; do
    create_mysql_db "${db}" "${mariadb_user}" "${mariadb_pass}"
done

backup: deploy node
    tar cv /etc/kolla | gzip > kolla.bak.tgz
    mysqldump -u root -p --all-databases | gzip > kolla_db.sql.tgz
restore kolla:
    tar xvf kolla.bak.tgz
    deploy OpenStack
    mysql -u root -p < kolla_db.sql

# kolla-ansible -i ${KOLLA_DIR}/multinode reconfigure -t mariadb
# kolla-ansible -i ${KOLLA_DIR}/multinode mariadb_backup
# ls -l /var/lib/docker/volumes/mariadb_backup/_data
EXTERN_MYSQL

kolla-genpwd
# 修改登录密码
sed -i "s/.*keystone_admin_password.*$/keystone_admin_password: ${ADMIN_PASS:-password}/g" /etc/kolla/passwords.yml
grep keystone_admin_password /etc/kolla/passwords.yml #admin和dashboard的密码
# # 各节点依赖安装
# kolla-ansible install-deps # Install Ansible Galaxy requirements, bootstrap-servers will failed
# kolla-ansible -e 'ansible_port=60022' -e "ansible_python_interpreter=${KOLLA_DIR}/venv3/bin/python3" -i ${KOLLA_DIR}/multinode bootstrap-servers
kolla-ansible -e 'ansible_port=60022' -e "ansible_python_interpreter=${KOLLA_DIR}/venv3/bin/python3" -i ${KOLLA_DIR}/multinode prechecks
# # 拉取镜像（可选）
kolla-ansible -i ${KOLLA_DIR}/multinode pull
# # 部署
kolla-ansible -i ${KOLLA_DIR}/multinode deploy
# # 生成 admin-openrc.sh
kolla-ansible -i ${KOLLA_DIR}/multinode post-deploy
# # 单独重新部署节点
# kolla-ansible -i ${KOLLA_DIR}/multinode --limit 172.16.1.211,172.16.1.212 reconfigure
# 增加一个计算节点
kolla-ansible -i ${KOLLA_DIR}/multinode pull --limit 172.16.1.214
kolla-ansible -i ${KOLLA_DIR}/multinode deploy --limit 172.16.1.214
remove_compute_node() {
    local host =$1
    # 删除一个计算节点
    openstack compute service set ${host} nova-compute --disable
    openstack server list --all-projects --host ${host} -f value -c ID | while read server; do
        openstack server migrate --live-migration $server
    done
    kolla-ansible -i ${KOLLA_DIR}/multinode stop --yes-i-really-really-mean-it [ --limit <limit> ]
    openstack network agent list --host ${host} -f value -c ID | while read id; do
        openstack network agent delete $id
    done
    openstack compute service list --os-compute-api-version 2.53 --host ${host} -f value -c ID | while read id; do
        openstack compute service delete --os-compute-api-version 2.53 $id
    done
    kolla-ansible -i ${KOLLA_DIR}/multinode destroy --yes-i-really-really-mean-it --limit ${host}
    # # vim multinode 去掉相关计算节点
}
# Server instances are not automatically balanced onto the new compute nodes.
# It may be helpful to live migrate some server instances onto the new hosts.
# openstack server migrate <server> --live-migration --host <target host> --os-compute-api-version 2.30
source /etc/kolla/admin-openrc.sh
openstack hypervisor list
openstack versions show
echo "Horizon: http://<ctrl_addr>"
echo "Kibana:  http://<ctrl_addr>:5601"
echo "skyline: http://<ctrl_addr>:9999"
# all logs in /var/log/kolla
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
# start manage opnstack
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #
echo "http://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img"
echo "http://download.cirros-cloud.net/0.6.2/cirros-0.6.2-aarch64-disk.img"
source /etc/kolla/admin-openrc.sh
create_flavor() {
    openstack flavor create --id 1 --ram 512 --disk 5 --vcpus 1 m1.tiny
    openstack flavor create --id 2 --ram 2048 --disk 20 --vcpus 1 m1.small
    openstack flavor create --id 3 --ram 4096 --disk 40 --vcpus 2 m1.medium
    openstack flavor create --id 4 --ram 8192 --disk 80 --vcpus 4 m1.large
    openstack flavor create --id 5 --ram 16384 --disk 160 --vcpus 8 m1.xlarge
}
create_pubnet() {
    local net_name=${1}
    local bool_enable_port_security=${2:-false}
    local name_server=${3:-}
    local net_start=${4:-172.16.3.9}
    local net_end=${5:-172.16.3.19}
    local subnet=${6:-172.16.0.0/21}
    local gateway=${7:-172.16.0.1}
    openstack router create ${net_name}-router
    # physnet1 is default kolla provider name
    # docker exec -it neutron_server cat /etc/neutron/plugins/ml2/ml2_conf.ini | grep flat_networks
    openstack network create --share --external --project admin \
        --provider-physical-network physnet1 --provider-network-type flat \
        ${net_name}-net
    ${bool_enable_port_security} && openstack network set --enable-port-security ${net_name}-net || openstack network set --disable-port-security ${net_name}-net
    # --no-dhcp, subnet meta service not started, use config drive for cloud-init
    # openstack server create --config-drive true .. / openstack create image ... --property img_config_drive=mandatory
    openstack subnet create --ip-version 4 --no-dhcp --project admin ${name_server:+--dns-nameserver ${name_server}} \
        --allocation-pool start=${net_start},end=${net_end} --subnet-range ${subnet} --gateway ${gateway} \
        --network ${net_name}-net ${net_name}-subnet
    openstack router set --external-gateway ${net_name}-net ${net_name}-router
    ${bool_enable_port_security} &&  {
        openstack security group rule create --proto icmp default
        openstack security group rule create --proto tcp --dst-port 22 default
        # openstack security group rule create --proto tcp --src-ip 0.0.0.0/0 --dst-port 1:65525 group-name
    }
}
create_image() {
    local img_name=${1}
    local img=${2}
    local arch=${3}
    local bool_dhcp=${4:-false}
    openstack image create "${img_name}" --file ${img} --disk-format qcow2 --container-format bare --public
    ${bool_dhcp} || openstack image set --property img_config_drive=mandatory "${img_name}"
    case "${KVM:-kvm}" in
        kvm)  openstack image set --property hw_architecture=${arch} "${img_name}";;
        qemu)
            case "${arch}" in
                aarch64)
                    openstack image set --property hw_machine_type=virt "${img_name}"
                    openstack image set --property hw_firmware_type=uefi "${img_name}"
                    ;;
                x86_64)  openstack image set --property hw_machine_type=pc "${img_name}";;
            esac
            ;;
    esac
    # # https://docs.openstack.org/glance/latest/admin/useful-image-properties.html
    # # https://docs.openstack.org/ocata/cli-reference/glance-property-keys.html
    echo "img_config_drive=mandatory"
    echo "hw_architecture=    ###kvm full virtualization arch###"
    echo "hw_firmware_type=uefi"
    echo "os_secure_boot=required"
    echo "os_type=linux"
    echo "hw_emulation_architecture=aarch64"
    echo "hw_video_type=virtio"
    echo "hw_video_type (specific to s390x)"
}
create_flavor
create_pubnet "public" "false" "114.114.114.114" "172.16.3.2" "172.16.3.19" "172.16.0.0/21" "172.16.0.1"
create_image "cirros_x86" "${KOLLA_DIR}/cirros-0.6.2-x86_64-disk.img" "x86_64" "true"
create_image "cirros_arm" "${KOLLA_DIR}/cirros-0.6.2-aarch64-disk.img" "aarch64" "false"
# # Import key
[ -f "${KOLLA_DIR}/testkey" ] || ssh-keygen -t ecdsa -N '' -f ${KOLLA_DIR}/testkey
openstack keypair create --public-key ${KOLLA_DIR}/testkey.pub mykey
openstack server create --image "cirros_x86" --flavor m1.tiny --key-name mykey --network public-net demo-x86
openstack server create --image "cirros_arm" --flavor m1.tiny --key-name mykey --network public-net demo-arm
# # # 创建VOLUME one LVM/CEPH虚拟机
# openstack availability zone list
# openstack volume create --image cirros --bootable --size 1 --availability-zone nova test_vol
# openstack volume list
# openstack server create --volume test_vol --flavor m1.tiny --key-name mykey --network ${net_name}-net demo_volume
# # # multi cinder backend!!!
# openstack volume backend pool list
# # +--------------------+
# # | Name               |
# # +--------------------+
# # | c1-lvm@rbd-1#rbd-1 |
# # | c1-lvm@lvm-1#lvm-1 |
# # +--------------------+
# openstack --os-username admin --os-tenant-name admin volume type create lvm
# openstack --os-username admin --os-tenant-name admin volume type set lvm --property volume_backend_name=lvm-1
# openstack --os-username admin --os-tenant-name admin volume type create myceph
# openstack --os-username admin --os-tenant-name admin volume type set myceph --property volume_backend_name=rbd-1
# openstack volume create --image cirros --bootable --size 1 --type lvm test_lvm
# openstack --os-username admin --os-tenant-name admin volume type list --long
# # # quota project
# # 40 instances
# openstack quota set --instances 40 ${PROJECT_ID}
# # 40 cores
# openstack quota set --cores 40 ${PROJECT_ID}
# # 96gb ram
# openstack quota set --ram 96000 ${PROJECT_ID}
cat <<'DEMO'
# 配置超卖
kolla-ansible -i kolla-ansible/ansible/inventory/all-in-one  reconfigure --tags nova
# 指派对外服务ip
openstack floating ip create provider
openstack floating ip list
openstack server add floating ip selfservice-instance-01 10.0.100.227
openstack server list
# # network node check ns
# openstack port list # # router/dhcpd/vm
# netns=$(ip netns list | grep "qrouter" | awk '{print $1}')
# ip netns exec ${netns} /bin/bash
DEMO
cat<<'EOF'
# all logs in /var/log/kolla
# 部署失败
kolla-ansible destroy --yes-i-really-really-mean-it
# 只部署某些组件
kolla-ansible deploy --tags="haproxy"
# 过滤部署某些组件
kolla-ansible deploy --skip-tags="haproxy"
# # mariadb集群出现故障
ansible -i multinode all -m shell -a 'docker stop mariadb'
ansible -i multinode all -m shell -a "sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/g' /var/lib/docker/volumes/mariadb/_data/grastate.dat"
kolla-ansible mariadb_recovery -i multinode
docker ps | grep nova
docker exec -it -u root mariadb /bin/bash
docker exec -it nova_libvirt /bin/bash
docker exec -it fluentd bash
EOF
