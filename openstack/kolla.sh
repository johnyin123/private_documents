# yum -y install python3-devel python3-libselinux libffi-devel git gcc openssl-devel dbus-devel glib2-devel docker
# use kolla, no need install libvirtd
# source ${KOLLA_DIR}/venv3/bin/activate && mkdir -p ~/offline && pip freeze > requirements.txt && pip download -r requirements.txt
# docker images | grep kolla | grep -v local | awk '{print $1,$2}' | while read -r image tag; do
#   newimg=`echo ${image} | cut -d / -f2-`
#   docker tag ${image}:${tag} localhost:4000/${newimg}:${tag}
#   docker push localhost:4000/${newimg}:${tag}
# done
KVM=qemu
KOLLA_DIR=/kolla
OPENSTACK_VER=master
ADMIN_PASS=Admin@2023
insec_registry=10.170.6.105:5000
CONTROLLER=(172.16.1.210)
COMPUTE=(172.16.1.211)
INT_VIP_ADDR=172.16.1.213
HAPROXY=yes
VG_NAME=cindervg
# # # # # # # all (compute/controller) node start
mkdir -p /etc/docker/ && cat > /etc/docker/daemon.json << EOF
{
  "registry-mirrors": [ "https://docker.mirrors.ustc.edu.cn", "http://hub-mirror.c.163.com" ],
  "insecure-registries": [ "quay.io"${insec_registry:+, \"${insec_registry}\"} ],
  "exec-opts": ["native.cgroupdriver=systemd", "native.umask=normal" ],
  "storage-driver": "overlay2",
  "bridge": "none",
  "ip-forward": false,
  "iptables": false
}
EOF
mkdir -p /etc/systemd/system/docker.service.d/ && cat <<EOF > /etc/systemd/system/docker.service.d/kolla.conf
[Service]
MountFlags=shared
EOF
sed --quiet -i -E \
    -e '/(127.0.0.1\s*).*/!p' \
    -e '$a127.0.0.1 localhost' \
    /etc/hosts
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
 <<EOF
pip install --no-index --find-links ${KOLLA_DIR}/pyenv/ --upgrade pip
pip install --no-index --find-links ${KOLLA_DIR}/pyenv/ -r ${KOLLA_DIR}/pyenv/requirements.txt
# # # # all compute nodes ends here
# cd ${KOLLA_DIR} && pip install --no-index --find-links ${KOLLA_DIR}/pyenv/ ./kolla
# cd ${KOLLA_DIR} && pip install --no-index --find-links ${KOLLA_DIR}/pyenv/ ./kolla-ansible
cp -r ${KOLLA_DIR}/venv3/share/kolla-ansible/etc_examples/kolla /etc/
cp ${KOLLA_DIR}/venv3/share/kolla-ansible/ansible/inventory/multinode ${KOLLA_DIR}
EOF
# # # # # # # offline end
# # # # # # # online start
mkdir -p ~/.pip/ && cat <<EOF | tee ~/.pip/pip.conf
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
cp -r ${KOLLA_DIR}/kolla-ansible/etc/kolla /etc/
cp ${KOLLA_DIR}/kolla-ansible/ansible/inventory/* ${KOLLA_DIR}
# # # # # # # online end
mkdir -p /etc/ansible/ && cat <<EOF >/etc/ansible/ansible.cfg
[defaults]
host_key_checking=False
pipelining=True
forks=100
EOF
command -v "crudini" &> /dev/null || pip install crudini
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

# # Deploy All-In-One
# openstack_tag_suffix: "-aarch64"
sed -i -E \
    -e "s/^\s*#*config_strategy\s*:.*/config_strategy: \"COPY_ALWAYS\"/g"   \
    -e "s/^\s*#*kolla_base_distro\s*:.*/kolla_base_distro: \"ubuntu\"/g"    \
    -e "s/^\s*#*network_interface\s*:.*/network_interface: \"eth0\"/g"      \
    -e "s/^\s*#*nova_compute_virt_type\s*:.*/nova_compute_virt_type: \"${KVM}\"/g"       \
    -e "s/^\s*#*openstack_release\s*:.*/openstack_release: \"${OPENSTACK_VER}\"/g"       \
    /etc/kolla/globals.yml
# linuxbridge is *EXPERIMENTAL* in Neutron since Zed
sed --quiet -i -E \
    -e '/(neutron_bridge_name|neutron_external_interface|neutron_plugin_agent)\s*:.*/!p' \
    -e '$aneutron_plugin_agent: "openvswitch"'   \
    -e "\$aneutron_external_interface: \"eth1\"" \
    -e '$aneutron_bridge_name:: "br-ext"'        \
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
    -e "s/^\s*#*enable_cinder_backend_lvm\s*:.*/enable_cinder_backend_lvm: \"yes\"/g"  \
    -e "s/^\s*#*cinder_volume_group\s*:.*/cinder_volume_group: \"${VG_NAME}\"/g"  \
    /etc/kolla/globals.yml
grep '^[^#]' /etc/kolla/globals.yml
# 配置nova文件, virth_type kvm/qemu
mkdir -p /etc/kolla/config/nova && cat <<EOF > /etc/kolla/config/nova/nova-compute.conf
[libvirt]
virt_type = ${KVM}
cpu_mode = none
EOF
# 关闭创建新卷
mkdir -p /etc/kolla/config/horizon/ && cat <<EOF > /etc/kolla/config/horizon/custom_local_settings
LAUNCH_INSTANCE_DEFAULTS = {'create_volume': False,}
EOF
# ########################ceph start
for node in ${COMPUTE[@]}; do
    crudini --set ${KOLLA_DIR}/multinode storage ${node}
done
mkdir -p /etc/kolla/config/glance/ /etc/kolla/config/cinder/cinder-volume/ \
    /etc/kolla/config/cinder/cinder-backup/ /etc/kolla/config/nova/
sed -i -E \
    -e "s/^\s*#*glance_backend_ceph\s*:.*/glance_backend_ceph: \"yes\"/g"  \
    -e "s/^\s*#*cinder_backend_ceph\s*:.*/cinder_backend_ceph: \"yes\"/g"  \
    -e "s/^\s*#*nova_backend_ceph\s*:.*/nova_backend_ceph: \"yes\"/g"  \
    -e "s/^\s*#*gnocchi_backend_storage\s*:.*/gnocchi_backend_storage: \"ceph\"/g"  \
    -e "s/^\s*#*enable_manila_backend_cephfs_native\s*:.*/enable_manila_backend_cephfs_native: \"yes\"/g"  \
    /etc/kolla/globals.yml
# # glance ceph
GLANCE_USER=glance
GLANCE_POOL=images
GLANCE_KEYRING=ceph.client.${GLANCE_USER}.keyring
sed -i -E \
    -e "s/^\s*#*ceph_glance_keyring\s*:.*/ceph_glance_keyring: \"${GLANCE_KEYRING}\"/g"  \
    -e "s/^\s*#*ceph_glance_user\s*:.*/ceph_glance_user: \"${GLANCE_USER}\"/g"  \
    -e "s/^\s*#*ceph_glance_pool_name\s*:.*/ceph_glance_pool_name: \"${GLANCE_POOL}\"/g"  \
    /etc/kolla/globals.yml
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
sed -i -E \
    -e "s/^\s*#*ceph_cinder_keyring\s*:.*/ceph_cinder_keyring: \"${CINDER_KEYRING}\"/g"  \
    -e "s/^\s*#*ceph_nova_keyring\s*:.*/ceph_nova_keyring: \"${NOVA_KEYRING}\"/g"  \
    -e "s/^\s*#*ceph_nova_user\s*:.*/ceph_nova_user: \"${NOVA_USER}\"/g"  \
    -e "s/^\s*#*ceph_nova_pool_name\s*:.*/ceph_nova_pool_name: \"${NOVA_POOL}\"/g"  \
    /etc/kolla/globals.yml
cat <<EOF
# https://docs.openstack.org/kolla-ansible/latest/reference/storage/external-ceph-guide.html
for p in ${GLANCE_POOL} ${CINDER_POOL} ${CINDER_POOL_BACKUP} ${NOVA_POOL}; do
    ceph osd pool create \${p} 128 && rbd pool init \${p}
done
ceph auth get-or-create client.${GLANCE_USER} mon 'profile rbd' osd 'profile rbd pool=${GLANCE_POOL}' mgr 'profile rbd pool=${GLANCE_POOL}'
ceph auth get-or-create client.${CINDER_USER} mon 'profile rbd' osd 'profile rbd pool=${CINDER_POOL}, profile rbd pool=${NOVA_POOL}, profile rbd-read-only pool=${GLANCE_POOL}' mgr 'profile rbd pool=${CINDER_POOL}, profile rbd pool=${NOVA_POOL}'
ceph auth get-or-create client.${CINDER_USER_BACKUP} mon 'profile rbd' osd 'profile rbd pool=${CINDER_POOL_BACKUP}' mgr 'profile rbd pool=${CINDER_POOL_BACKUP}'
ceph auth get-or-create client.${NOVA_USER} mon 'profile rbd' osd 'profile rbd pool=${NOVA_POOL}' mgr 'profile rbd pool=${NOVA_POOL}'
EOF
# /etc/kolla/config/glance/ceph.conf
# /etc/kolla/config/cinder/ceph.conf
# /etc/kolla/config/nova/ceph.conf
# ceph auth get-or-create client.${GLANCE_USER} | ssh {your-glance-api-server} sudo tee /etc/ceph/ceph.client.glance.keyring
# /etc/kolla/config/glance/<ceph_glance_keyring>
# /etc/kolla/config/cinder/cinder-volume/<ceph_cinder_keyring>
# /etc/kolla/config/cinder/cinder-backup/<ceph_cinder_keyring>
# /etc/kolla/config/cinder/cinder-backup/<ceph_cinder_backup_keyring>
# /etc/kolla/config/nova/<ceph_cinder_keyring>
# /etc/kolla/config/nova/<ceph_nova_keyring> (if your Ceph deployment created one)
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

[ -f "${HOME:-~}/.ssh/id_rsa" ] ||  ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa
# ssh -p60022 localhost "true" || echo "ssh-copy-id"
# cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys

# # 各节点依赖安装
# kolla-ansible install-deps # Install Ansible Galaxy requirements, bootstrap-servers will failed
# kolla-ansible -e 'ansible_port=60022' -e "ansible_python_interpreter=${KOLLA_DIR}/venv3/bin/python3" -i ${KOLLA_DIR}/multinode bootstrap-servers
kolla-ansible -e 'ansible_port=60022' -e "ansible_python_interpreter=${KOLLA_DIR}/venv3/bin/python3" -i ${KOLLA_DIR}/multinode prechecks
# 拉取镜像（可选）
kolla-ansible -e 'ansible_port=60022' -e "ansible_python_interpreter=${KOLLA_DIR}/venv3/bin/python3" -i ${KOLLA_DIR}/multinode pull
# 部署
kolla-ansible -e 'ansible_port=60022' -e "ansible_python_interpreter=${KOLLA_DIR}/venv3/bin/python3" -i ${KOLLA_DIR}/multinode deploy
# 生成 admin-openrc.sh
kolla-ansible -e 'ansible_port=60022' -e "ansible_python_interpreter=${KOLLA_DIR}/venv3/bin/python3" -i ${KOLLA_DIR}/multinode post-deploy
cat /etc/kolla/admin-openrc.sh
echo "Horizon: http://<ctrl_addr>"
echo "Kibana:  http://<ctrl_addr>:5601"
# 调整日志
ln -sf /var/lib/docker/volumes/kolla_logs/_data/ /var/log/kolla
cat <<DEMO
source /etc/kolla/admin-openrc.sh
openstack hypervisor list
# # 初始化
cp ${KOLLA_DIR}/kolla-ansible/tools/init-runonce ${KOLLA_DIR} # init env
# cp ${KOLLA_DIR}/venv3/share/kolla-ansible/init-runonce ${KOLLA_DIR}
# 创建 cirros 镜像、网络、子网、路由、安全组、规格、配额等虚拟机资源
CIRROS_RELEASE=${CIRROS_RELEASE:-0.6.1}
ARCH=x86_64
mkdir -p /opt/cache/files/ && touch /opt/cache/files/cirros-${CIRROS_RELEASE}-${ARCH}-disk.img
CIRROS_RELEASE=${CIRROS_RELEASE} \
EXT_NET_CIDR=172.16.3.0/21 \
EXT_NET_RANGE='start=172.16.3.9,end=172.16.3.199' \
EXT_NET_GATEWAY=172.16.0.1 \
${KOLLA_DIR}/init-runonce
# 创建虚拟机
openstack server create --image cirros --flavor m1.tiny --key-name mykey --network demo-net demo1
# # 验证 nova 服务
openstack compute service list
openstack compute agent list
# # 验证 neutron agent 服务
openstack network agent list
docker ps | grep nova
docker exec -it nova_libvirt /bin/bash
DEMO
cat<<EOF
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
