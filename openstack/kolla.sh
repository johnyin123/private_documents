# yum -y install python3-devel python3-libselinux libffi-devel git gcc openssl-devel dbus-devel glib2-devel docker
# use kolla, no need install libvirtd
# source ${KOLLA_DIR}/venv3/bin/activate && mkdir -p ~/offline && pip freeze > requirements.txt && pip download -r requirements.txt
# docker images | grep kolla | grep -v local | awk '{print $1,$2}' | while read -r image tag; do
#   newimg=`echo ${image} | cut -d / -f2-`
#   docker tag ${image}:${tag} localhost:4000/${newimg}:${tag}
#   docker push localhost:4000/${newimg}:${tag}
# done
KVM=qemu
OPENSTACK_VER=master
KOLLA_DIR=/kolla
ADMIN_PASS=Admin@2023
insec_registry=10.170.6.105:5000
CONTROLLER=(172.16.1.210)
COMPUTE=(172.16.1.211 172.16.1.212)
INT_VIP_ADDR=172.16.1.213
HAPROXY=yes
VG_NAME=cindervg
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
sed --quiet -i -E \
    -e '/(127.0.0.1\s*).*/!p' \
    -e '$a127.0.0.1 localhost' \
    /etc/hosts
# # ADD OTHER NODES /etc/hosts
systemctl daemon-reload
systemctl restart docker
systemctl enable docker
# # store node
[ -z "${VG_NAME:-}" ] || {
    command -v "pvcreate" &> /dev/null || yum -y install lvm2
    pvcreate /dev/vdb
    vgcreate ${VG_NAME} /dev/vdb
}
# # # # # # # all (compute/controller) node end
mkdir -p ${KOLLA_DIR} && python3 -m venv ${KOLLA_DIR}/venv3 && source ${KOLLA_DIR}/venv3/bin/activate
# # # # # # # offline start
cat <<EOF
pip install --no-index --find-links ${KOLLA_DIR}/pyenv/ --upgrade pip
pip install --no-index --find-links ${KOLLA_DIR}/pyenv/ -r ${KOLLA_DIR}/pyenv/requirements.txt
# # # # all compute nodes ends here
# cd ${KOLLA_DIR} && pip install --no-index --find-links ${KOLLA_DIR}/pyenv/ ./kolla
# cd ${KOLLA_DIR} && pip install --no-index --find-links ${KOLLA_DIR}/pyenv/ ./kolla-ansible
EOF
# # # # # # # offline end
# # # # # # # online start
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
cp -r ${KOLLA_DIR}/kolla-ansible/etc/kolla /etc/ 2>/dev/null || cp -r ${KOLLA_DIR}/venv3/share/kolla-ansible/etc_examples/kolla /etc/
cp ${KOLLA_DIR}/kolla-ansible/ansible/inventory/* ${KOLLA_DIR} 2>/dev/null || cp ${KOLLA_DIR}/venv3/share/kolla-ansible/ansible/inventory/* ${KOLLA_DIR}
# # # # # # # online end
cfg_file=/etc/ansible/ansible.cfg
mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
[defaults]
host_key_checking=False
pipelining=True
forks=100
EOF
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
# 192.168.122.24 ansible_ssh_user=<ssh-username> ansible_become=True ansible_private_key_file=<path/to/private-key-file>
for node in ${CONTROLLER[@]}; do
    crudini --set ${KOLLA_DIR}/multinode control "${node}"
done
for node in ${COMPUTE[@]}; do
    crudini --set ${KOLLA_DIR}/multinode network "${node}"
    crudini --set ${KOLLA_DIR}/multinode compute "${node}"
    [ -z "${VG_NAME:-}" ] || crudini --set ${KOLLA_DIR}/multinode storage "${node}"
done
crudini --set ${KOLLA_DIR}/multinode storage     # no storage
crudini --set ${KOLLA_DIR}/multinode monitoring  # no monitoring
crudini --set ${KOLLA_DIR}/multinode deployment  "localhost ansible_connection=local"

for node in ${CONTROLLER[@]} ${COMPUTE[@]}; do
    crudini --set ${KOLLA_DIR}/multinode all "${node} uselvm=yes ansible_port=60022 ansible_python_interpreter=${KOLLA_DIR}/venv3/bin/python3"
done
crudini --set ${KOLLA_DIR}/multinode all:vars "uselvm=no"
crudini --set ${KOLLA_DIR}/multinode all:vars "net_if=eth0"
crudini --set ${KOLLA_DIR}/multinode all:vars "virt_type=${KVM:-kvm}"
crudini --set ${KOLLA_DIR}/multinode all:vars "openstack_version=${OPENSTACK_VER:-master}"
crudini --set ${KOLLA_DIR}/multinode all:vars "external_interface=eth1"
# # Deploy All-In-One
# openstack_tag_suffix: "-aarch64"
sed -i -E \
    -e "s/^\s*#*config_strategy\s*:.*/config_strategy: \"COPY_ALWAYS\"/g"   \
    -e "s/^\s*#*kolla_base_distro\s*:.*/kolla_base_distro: \"ubuntu\"/g"    \
    -e "s/^\s*#*network_interface\s*:.*/network_interface: \"{{ net_if }}\"/g"      \
    -e "s/^\s*#*nova_compute_virt_type\s*:.*/nova_compute_virt_type: \"{{ virt_type }}\"/g"       \
    -e "s/^\s*#*openstack_release\s*:.*/openstack_release: \"{{ openstack_version }}\"/g"       \
    /etc/kolla/globals.yml
# linuxbridge is *EXPERIMENTAL* in Neutron since Zed
sed --quiet -i -E \
    -e '/(enable_neutron_provider_networks|neutron_bridge_name|neutron_external_interface|neutron_plugin_agenti|enable_neutron_agent_ha)\s*:.*/!p' \
    -e '$aenable_neutron_provider_networks: "yes"' \
    -e '$aneutron_plugin_agent: "openvswitch"'   \
    -e "\$aneutron_external_interface: \"{{ external_interface }}\"" \
    -e '$aenable_neutron_agent_ha: "yes"'        \
    /etc/kolla/globals.yml

[ -z ${insec_registry} ] || sed -i -E \
    -e "s/^\s*#*docker_registry\s*:.*/docker_registry: \"${insec_registry}\"/g"  \
    -e "s/^\s*#*docker_registry_insecure\s*:.*/docker_registry_insecure: \"yes\"/g" \
    -e "s/^\s*#*docker_namespace\s*:.*/docker_namespace: \"kolla\"/g" \
    /etc/kolla/globals.yml

# # Deploy HA Cluster
# simply change three more settings to deploy a HA cluster.
# a free static IP for the external cluster VIP on your local subnet. Make sure to adjust it to match your local subnet.
sed -i -E \
    -e "s/^\s*#*enable_haproxy\s*:.*/enable_haproxy: \"${HAPROXY}\"/g"  \
    -e "s/^\s*#*kolla_internal_vip_address\s*:.*/kolla_internal_vip_address: \"${INT_VIP_ADDR}\"/g"  \
    -e "s/^\s*#*kolla_external_vip_address\s*:.*/kolla_external_vip_address: \"${INT_VIP_ADDR}\"/g"  \
    /etc/kolla/globals.yml
# Block Storage service, use LVM cinder
[ -z "${VG_NAME:-}" ] || sed -i -E \
    -e "s/^\s*#*enable_cinder\s*:.*/enable_cinder: \"yes\"/g"  \
    -e "s/^\s*#*enable_cinder_backup\s*:.*/enable_cinder_backup: \"yes\"/g"  \
    -e "s/^\s*#*enable_cinder_backend_lvm\s*:.*/enable_cinder_backend_lvm: \"{{ uselvm }}\"/g"  \
    -e "s/^\s*#*cinder_volume_group\s*:.*/cinder_volume_group: \"${VG_NAME}\"/g"  \
    /etc/kolla/globals.yml
grep '^[^#]' /etc/kolla/globals.yml
grep -v '^\s*$\|^\s*\#' /etc/kolla/globals.yml
# 配置nova文件, virth_type kvm/qemu
cfg_file=/etc/kolla/config/nova/nova-compute.conf
mkdir -p $(dirname "${cfg_file}") && cat <<EOF > "${cfg_file}"
[libvirt]
virt_type = ${KVM:-kvm}
cpu_mode = none
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
# ########################ceph start
for node in ${COMPUTE[@]}; do
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

sed -i -E \
    -e "s/^\s*#*enable_cinder\s*:.*/enable_cinder: \"yes\"/g"  \
    -e "s/^\s*#*enable_cinder_backup\s*:.*/enable_cinder_backup: \"yes\"/g"  \
    -e "s/^\s*#*glance_backend_ceph\s*:.*/glance_backend_ceph: \"yes\"/g"  \
    -e "s/^\s*#*cinder_backend_ceph\s*:.*/cinder_backend_ceph: \"yes\"/g"  \
    -e "s/^\s*#*nova_backend_ceph\s*:.*/nova_backend_ceph: \"yes\"/g"  \
    /etc/kolla/globals.yml
#    -e "s/^\s*#*gnocchi_backend_storage\s*:.*/gnocchi_backend_storage: \"ceph\"/g"  \
#    -e "s/^\s*#*enable_manila_backend_cephfs_native\s*:.*/enable_manila_backend_cephfs_native: \"yes\"/g"  \
# # glance ceph
GLANCE_USER=glance
GLANCE_POOL=images
GLANCE_KEYRING=ceph.client.${GLANCE_USER}.keyring
sed -i -E \
    -e "s/^\s*#*ceph_glance_keyring\s*:.*/ceph_glance_keyring: \"${GLANCE_KEYRING}\"/g"  \
    -e "s/^\s*#*ceph_glance_user\s*:.*/ceph_glance_user: \"${GLANCE_USER}\"/g"  \
    -e "s/^\s*#*ceph_glance_pool_name\s*:.*/ceph_glance_pool_name: \"${GLANCE_POOL}\"/g"  \
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
sed -i -E \
    -e "s/^\s*#*ceph_cinder_keyring\s*:.*/ceph_cinder_keyring: \"${CINDER_KEYRING}\"/g"  \
    -e "s/^\s*#*ceph_cinder_user\s*:.*/ceph_cinder_user: \"${CINDER_USER}\"/g"  \
    -e "s/^\s*#*ceph_cinder_pool_name\s*:.*/ceph_cinder_pool_name: \"${CINDER_POOL}\"/g"  \
    -e "s/^\s*#*ceph_cinder_backup_keyring\s*:.*/ceph_cinder_backup_keyring: \"${CINDER_KEYRING_BACKUP}\"/g"  \
    -e "s/^\s*#*ceph_cinder_backup_user\s*:.*/ceph_cinder_backup_user: \"${CINDER_USER_BACKUP}\"/g"  \
    -e "s/^\s*#*ceph_cinder_backup_pool_name\s*:.*/ceph_cinder_backup_pool_name: \"${CINDER_POOL_BACKUP}\"/g"  \
    /etc/kolla/globals.yml
# # nova ceph
NOVA_USER=nova
NOVA_POOL=vms
NOVA_KEYRING=ceph.client.${NOVA_USER}.keyring
# ceph_nova_user`` (by default it's the same as ``ceph_cinder_user``)
sed -i -E \
    -e "s/^\s*#*ceph_cinder_keyring\s*:.*/ceph_cinder_keyring: \"${CINDER_KEYRING}\"/g"  \
    -e "s/^\s*#*ceph_nova_keyring\s*:.*/ceph_nova_keyring: \"${NOVA_KEYRING}\"/g"  \
    -e "s/^\s*#*ceph_nova_user\s*:.*/ceph_nova_user: \"${NOVA_USER}\"/g"  \
    -e "s/^\s*#*ceph_nova_pool_name\s*:.*/ceph_nova_pool_name: \"${NOVA_POOL}\"/g"  \
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
    ceph ${cluster:+--cluster ${cluster}} auth get-or-create client.${p} | tee ceph.client.${p}.keyring
done
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

kolla-genpwd
# 修改登录密码
sed -i "s/.*keystone_admin_password.*$/keystone_admin_password: ${ADMIN_PASS}/g" /etc/kolla/passwords.yml
grep keystone_admin_password /etc/kolla/passwords.yml #admin和dashboard的密码

[ -f "${HOME:-~}/.ssh/id_rsa" ] || ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa
echo "echo '$(cat ~/.ssh/id_rsa.pub)' >> ~/.ssh/authorized_keys"
# ssh -p60022 localhost "true" || echo "ssh-copy-id"
# cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

# # 各节点依赖安装
# kolla-ansible install-deps # Install Ansible Galaxy requirements, bootstrap-servers will failed
# kolla-ansible -e 'ansible_port=60022' -e "ansible_python_interpreter=${KOLLA_DIR}/venv3/bin/python3" -i ${KOLLA_DIR}/multinode bootstrap-servers
kolla-ansible -e 'ansible_port=60022' -e "ansible_python_interpreter=${KOLLA_DIR}/venv3/bin/python3" -i ${KOLLA_DIR}/multinode prechecks
# # 拉取镜像（可选）
kolla-ansible -e 'ansible_port=60022' -e "ansible_python_interpreter=${KOLLA_DIR}/venv3/bin/python3" -i ${KOLLA_DIR}/multinode pull
# # 部署
kolla-ansible -e 'ansible_port=60022' -e "ansible_python_interpreter=${KOLLA_DIR}/venv3/bin/python3" -i ${KOLLA_DIR}/multinode deploy
# # 生成 admin-openrc.sh
kolla-ansible -e 'ansible_port=60022' -e "ansible_python_interpreter=${KOLLA_DIR}/venv3/bin/python3" -i ${KOLLA_DIR}/multinode post-deploy
# # 单独重新部署节点
# kolla-ansible -e 'ansible_port=60022' -e "ansible_python_interpreter=${KOLLA_DIR}/venv3/bin/python3" -i ${KOLLA_DIR}/multinode --limit 172.16.1.211 reconfigure
cat /etc/kolla/admin-openrc.sh
echo "Horizon: http://<ctrl_addr>"
echo "Kibana:  http://<ctrl_addr>:5601"
# 调整日志
# docker exec -it fluentd bash
# all logs in /var/log/kolla
cat <<'EOF_INIT' > myinit_once.sh
#!/usr/bin/env bash
name_server=
img="cirros.img"
net_name=public
echo "http://download.cirros-cloud.net/0.6.2/cirros-0.6.2-x86_64-disk.img"
echo "http://download.cirros-cloud.net/0.6.2/cirros-0.6.2-aarch64-disk.img"
source /etc/kolla/admin-openrc.sh
verify() {
    echo "============== VERIFY: Verify Neutron installation"
    openstack extension list --network
    openstack network agent list
    echo "============== VERIFY: Verify Nova Installation"
    echo "============== VERIFY: List service components to verify successful launch and registration of each process"
    openstack compute service list
    openstack catalog list
    openstack image list
    echo "============== VERIFY: verify glance installation"
    openstack image list
    echo "============== VERIFY: Verify Keystone Installation"
    openstack project list
    openstack user list
    openstack service list
    openstack role list
    openstack endpoint list
    echo "============== VERIFY: openstack service list"
    openstack service list
    echo "============== VERIFY: openstack compute service list"
    openstack compute service list|| true
    echo "============== VERIFY: openstack network agent list"
    openstack network agent list || true
    echo "============== VERIFY: openstack network list"
    openstack network list || true
    echo "============== VERIFY: openstack subnet list"
    openstack subnet list || true
    echo "============== VERIFY: openstack image list"
    openstack image list || true
    echo "============== VERIFY: openstack flavor list"
    openstack flavor list || true
    echo "============== VERIFY: openstack extension list --network"
    openstack hypervisor list || true
    openstack volume service list
    openstack volume backend pool list
}
openstack flavor create --id 1 --ram 512 --disk 1 --vcpus 1 m1.tiny
openstack flavor create --id 2 --ram 2048 --disk 20 --vcpus 1 m1.small
openstack flavor create --id 3 --ram 4096 --disk 40 --vcpus 2 m1.medium
openstack flavor create --id 4 --ram 8192 --disk 80 --vcpus 4 m1.large
openstack flavor create --id 5 --ram 16384 --disk 160 --vcpus 8 m1.xlarge

openstack image show "cirros" 2>/dev/null || \
    openstack image create "cirros" --file ${img} --disk-format qcow2 --container-format bare --public

openstack router create ${net_name}-router

# physnet1 is default kolla provider name
# docker exec -it neutron_server cat /etc/neutron/plugins/ml2/ml2_conf.ini | grep flat_networks
# --disable-port-security \
openstack network create --share --external \
    --project admin \
    --provider-physical-network physnet1 \
    --provider-network-type flat ${net_name}-net

# --no-dhcp, subnet meta service not work?
openstack subnet create --ip-version 4 \
    --project admin \
    --network ${net_name}-net \
    ${name_server:+--dns-nameserver ${name_server}} \
    --allocation-pool start=172.16.3.9,end=172.16.3.19 \
    --subnet-range 172.16.0.0/21 \
    --gateway 172.16.0.1 ${net_name}-subnet

openstack router set --external-gateway ${net_name}-net ${net_name}-router

# # Import key
[ -f "testkey" ] || ssh-keygen -t ecdsa -N '' -f testkey
openstack keypair create --public-key testkey.pub mykey
# 建立安全策略
openstack security group rule create --proto icmp default
openstack security group rule create --proto tcp --dst-port 22 default
# openstack security group rule create --proto tcp --src-ip 0.0.0.0/0 --dst-port 1:65525 group-name
# openstack security group rule create --proto udp --src-ip 0.0.0.0/0 --dst-port 1:65525 group-name
# openstack security group rule create --proto icmp --src-ip 0.0.0.0/0 group-name
# # 创建虚拟机
openstack server create --image cirros --flavor m1.tiny --key-name mykey --network ${net_name}-net demo1

# # 创建VOLUME one LVM/CEPH虚拟机
openstack availability zone list
openstack volume create --image cirros --bootable --size 1 --availability-zone nova test_vol
openstack volume list
openstack server create --volume test_vol --flavor m1.tiny --key-name mykey --network ${net_name}-net demo_volume
# # multi cinder backend!!!
openstack volume backend pool list
# +--------------------+
# | Name               |
# +--------------------+
# | c1-lvm@rbd-1#rbd-1 |
# | c1-lvm@lvm-1#lvm-1 |
# +--------------------+
openstack --os-username admin --os-tenant-name admin volume type create lvm
openstack --os-username admin --os-tenant-name admin volume type set lvm --property volume_backend_name=lvm-1
openstack --os-username admin --os-tenant-name admin volume type create myceph
openstack --os-username admin --os-tenant-name admin volume type set myceph --property volume_backend_name=rbd-1
openstack volume create --image cirros --bootable --size 1 --type lvm test_lvm
openstack --os-username admin --os-tenant-name admin volume type list --long
# # # quota project
# # 40 instances
# openstack quota set --instances 40 ${PROJECT_ID}
# # 40 cores
# openstack quota set --cores 40 ${PROJECT_ID}
# # 96gb ram
# openstack quota set --ram 96000 ${PROJECT_ID}
verify
EOF_INIT
cat <<'DEMO'
# 查看openstack相关信息
openstack service list
openstack compute service list
openstack volume service list
openstack network agent list
openstack hypervisor list
# 建立provider network
openstack network create --share --external --provider-physical-network physnet1 --provider-network-type flat provider
openstack subnet create --network provider --allocation-pool start=192.168.100.221,end=192.168.100.230 --dns-nameserver 114.114.114.114 --gateway 192.168.100.1 --subnet-range 192.168.100.0/24 provider
# 建立selfservice network
openstack network create selfservice
openstack subnet create --network selfservice --dns-nameserver 114.114.114.114 --gateway 192.168.240.1 --subnet-range 192.168.240.0/24 selfservice
# 建立虚拟路由
openstack router create router
# 连接内外网络
openstack router add subnet router selfservice
openstack router set router --external-gateway provider
openstack port list
# 建立sshkey
openstack keypair create --public-key ~/.ssh/id_rsa.pub mykey
# 建立安全策略
openstack security group rule create --proto icmp default
openstack security group rule create --proto tcp --dst-port 22 default
# 建立虚拟机
openstack server create --flavor m1.nano --image cirros-0.5.2-x86_64 --nic net-id=fe172dec-0522-472a-aed4-da70f6c269a6 --security-group default --key-name mykey  provider-instance-01
openstack server create --flavor m1.nano --image cirros-0.5.2-x86_64 --nic net-id=c30c5057-607d-4736-acc9-31927cc9a22c --security-group default --key-name mykey  selfservice-instance-01
# 指派对外服务ip
openstack floating ip create provider
openstack floating ip list
openstack server add floating ip selfservice-instance-01 10.0.100.227
openstack server list
# 私有云映射方法
iptables -t nat -A PREROUTING -i eth0 -p tcp --dport 1022 -j DNAT --to 192.168.122.231:22
iptables -t nat -D PREROUTING -i eth0 -p tcp --dport 1022 -j DNAT --to 192.168.122.231:22

# # network node check ns
# openstack port list # # router/dhcpd/vm
# netns=$(ip netns list | grep "qrouter" | awk '{print $1}')
# ip netns exec ${netns} /bin/bash
# # # 初始化
# cp ${KOLLA_DIR}/kolla-ansible/tools/init-runonce ${KOLLA_DIR} # init env
# # cp ${KOLLA_DIR}/venv3/share/kolla-ansible/init-runonce ${KOLLA_DIR}
# # 创建 cirros 镜像、网络、子网、路由、安全组、规格、配额等虚拟机资源
# CIRROS_RELEASE=${CIRROS_RELEASE:-0.6.1}
# ARCH=x86_64
# mkdir -p /opt/cache/files/ && touch /opt/cache/files/cirros-${CIRROS_RELEASE}-${ARCH}-disk.img
# CIRROS_RELEASE=${CIRROS_RELEASE} \
# EXT_NET_CIDR=172.16.0.0/21 \
# EXT_NET_RANGE='start=172.16.3.9,end=172.16.3.199' \
# EXT_NET_GATEWAY=172.16.0.1 \
# ${KOLLA_DIR}/init-runonce
# # 验证 nova 服务
openstack compute service list
openstack compute agent list
# # 验证 neutron agent 服务
openstack network agent list
docker ps | grep nova
docker exec -it nova_libvirt /bin/bash
DEMO
cat<<EOF
docker exec -it fluentd bash
# all logs in /var/log/kolla
# 增加一个计算节点
kolla-ansible  -i  inventory/multinode bootstrap-servers --limit compute02
kolla-ansible  -i  inventory/multinode pull --limit compute02
kolla-ansible  -i  inventory/multinode deploy --limit compute02
# 删除一个计算节点
kolla-ansible -i inventory/multinode destroy --limit compute02 --yes-i-really-really-mean-it
openstack  compute service list
openstack  compute service delete  <compute ID>
openstack  network agent list
openstack  network agent delete  <ID>
# # vim multinode 去掉相关计算节点
# 部署失败
kolla-ansible destroy --yes-i-really-really-mean-it
# 只部署某些组件
kolla-ansible deploy --tags="haproxy"
# 过滤部署某些组件
kolla-ansible deploy --skip-tags="haproxy"
# # kolla-ansible自带工具
# 可用于从系统中移除部署的容器
/usr/local/share/kolla-ansible/tools/cleanup-containers
#可用于移除由于残余网络变化引发的docker启动的neutron-agents主机
/usr/local/share/kolla-ansible/tools/cleanup-host
#可用于从本地缓存中移除所有的docker image
/usr/local/share/kolla-ansible/tools/cleanup-images
# # mariadb集群出现故障
ansible -i multinode all -m shell -a 'docker stop mariadb'
ansible -i multinode all -m shell -a "sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/g' /var/lib/docker/volumes/mariadb/_data/grastate.dat"
kolla-ansible mariadb_recovery -i multinode
EOF
