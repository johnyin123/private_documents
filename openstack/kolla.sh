# yum -y install python3-devel libffi-devel git gcc openssl-devel dbus-devel glib2-devel docker
# source ${KOLLA_DIR}/venv3/bin/activate && mkdir -p ~/offline && pip freeze > requirements.txt && pip download -r requirements.txt
KVM=qemu
KOLLA_DIR=/kolla
insec_registry=192.168.168.1:5000
cat <<EOF | tee /etc/hosts
127.0.0.1   localhost
192.168.168.150 $(cat /etc/hostname)
EOF
mkdir -p ~/.pip/ && cat <<EOF | tee ~/.pip/pip.conf
[global]
trusted-host = mirrors.aliyun.com
index-url = https://mirrors.aliyun.com/pypi/simple
# index-url = https://pypi.tuna.tsinghua.edu.cn/simple
EOF
mkdir -p ${KOLLA_DIR} && python3 -m venv ${KOLLA_DIR}/venv3 && source ${KOLLA_DIR}/venv3/bin/activate
cat <<EOF
# offline
pip install --no-index --find-links ${KOLLA_DIR}/pyenv/ --upgrade pip
pip install --no-index --find-links ${KOLLA_DIR}/pyenv/ r ${KOLLA_DIR}/pyenv/requirements.txt
cd ${KOLLA_DIR} && pip install --no-index --find-links ${KOLLA_DIR}/pyenv/ ./kolla
cd ${KOLLA_DIR} && pip install --no-index --find-links ${KOLLA_DIR}/pyenv/ ./kolla-ansible
EOF
pip install --upgrade pip
pip install pip-search
pip install 'ansible>=6,<8' dbus-python selinux docker python-openstackclient

# # pip install kolla-ansible kolla
cd ${KOLLA_DIR} && git clone --depth=1 https://github.com/openstack/kolla
cd ${KOLLA_DIR} && git clone --depth=1 https://github.com/openstack/kolla-ansible
cd ${KOLLA_DIR} && pip install ./kolla
cd ${KOLLA_DIR} && pip install ./kolla-ansible

# Install Ansible Galaxy requirements
kolla-ansible install-deps

mkdir -p /etc/ansible/ && cat <<EOF >/etc/ansible/ansible.cfg
[defaults]
host_key_checking=False
pipelining=True
forks=100
EOF

# globals.yml、password.yml
cp -r ${KOLLA_DIR}/kolla-ansible/etc/kolla /etc/
cp ${KOLLA_DIR}/kolla-ansible/ansible/inventory/* ${KOLLA_DIR}
# cp -r ${KOLLA_DIR}/venv3/share/kolla-ansible/etc_examples/kolla /etc/
# cp ${KOLLA_DIR}/venv3/share/kolla-ansible/ansible/inventory/multinode ${KOLLA_DIR}

command -v "crudini" &> /dev/null || pip install crudini
crudini --del ${KOLLA_DIR}/multinode control
crudini --del ${KOLLA_DIR}/multinode network
crudini --del ${KOLLA_DIR}/multinode compute
crudini --del ${KOLLA_DIR}/multinode monitoring
crudini --del ${KOLLA_DIR}/multinode storage
crudini --del ${KOLLA_DIR}/multinode deployment
crudini --set ${KOLLA_DIR}/multinode control     "srv150 ansible_python_interpreter=${KOLLA_DIR}/venv3/bin/python3"
crudini --set ${KOLLA_DIR}/multinode network     "srv150"
crudini --set ${KOLLA_DIR}/multinode compute     "srv150"
crudini --set ${KOLLA_DIR}/multinode monitoring  "srv150"
crudini --set ${KOLLA_DIR}/multinode storage     "srv150"
crudini --set ${KOLLA_DIR}/multinode deployment  "localhost ansible_connection=local"

cat <<EOF > /etc/kolla/globals.yml
---
config_strategy: "COPY_ALWAYS"
### Docker options ######################################## 
# Valid options are [ docker, podman ]
kolla_container_engine: docker
docker_namespace: "kolla"
${insec_registry:+docker_registry: \"${insec_registry}\"}
docker_registry_insecure: "yes"
### Kolla options  ########################################
kolla_base_distro: "ubuntu"
kolla_install_type: "source"
# If openstack_release is not specified, using the version number information contained in the kolla-ansible package.
# openstack_release: "zed"
node_custom_config: "/etc/kolla/config"
### keepalived options ########################################
# keepalived_virtual_router_id: "51"
enable_haproxy: "no"
# All-In-One without haproxy and keepalived(enable_haproxy: "no")
# kolla_internal_vip_address is "network_interface: eth0" address
kolla_internal_vip_address: "192.168.168.150"
EOF
cat <<EOF >> /etc/kolla/globals.yml
### OpenStack options ########################################
# Enable core OpenStack services. This includes: glance, keystone, neutron, nova, heat, and horizon.
enable_openstack_core: "yes"
enable_mariadb: "yes"
enable_memcached: "no"
enable_ceilometer: "yes"
enable_gnocchi: "yes"
enable_heat: "yes"
enable_nova_ssh: "yes"
# qemu, kvm, vmware, xenapi
nova_compute_virt_type: "${KVM}"
nova_console: "novnc"
EOF
cat <<EOF >> /etc/kolla/globals.yml
### Neutron - Networking Options  ########################################
enable_neutron: "yes"
network_interface: "eth0"
neutron_external_interface: "eth1"
enable_neutron_dvr: "no"
enable_neutron_qos: "no"
enable_neutron_agent_ha: "no"
enable_neutron_provider_networks: "no"
neutron_plugin_agent: "openvswitch"
neutron_tenant_network_types: "vxlan,vlan,flat"
neutron_ipam_driver: "internal"
enable_neutron_packet_logging: "no"
api_interface: "{{ network_interface }}"
storage_interface: "{{ network_interface }}"
cluster_interface: "{{ network_interface }}"
tunnel_interface: "{{ network_interface }}"
dns_interface: "{{ network_interface }}"
EOF
cat <<EOF >> /etc/kolla/globals.yml
# use LVM cinder
enable_cinder: "yes"
enable_cinder_backup: "yes"
enable_cinder_backend_lvm: "yes"
cinder_volume_group: "cinder-volumes"
EOF
command -v "pvcreate" &> /dev/null || yum -y install lvm2
pvcreate /dev/vdb
vgcreate cinder-volumes /dev/vdb
cat <<EOF
# https://docs.ceph.com/en/latest/rbd/rbd-openstack/
enable_cinder: "yes"
enable_ceph: "no"
enable_cinder_backend_iscsi: "no"
enable_cinder_backend_lvm: "no"
enable_cinder_backup: "yes"
cinder_backup_driver: "ceph"
cinder_backend_ceph: "yes"
glance_backend_ceph: "yes"
EOF
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
# 创建ceph配置
cat <<EOF > /etc/kolla/config/ceph.conf
[global]
osd pool default size = 3
osd pool default min size = 2
mon_clock_drift_allowed = 2
osd_pool_default_pg_num = 8
osd_pool_default_pgp_num = 8
mon clock drift warn backoff = 30
EOF

kolla-genpwd
# 修改登录密码
sed -i "s/.*keystone_admin_password.*$/keystone_admin_password: Admin@2023/g" /etc/kolla/passwords.yml
grep keystone_admin_password /etc/kolla/passwords.yml #admin和dashboard的密码

# 部署前检查（可选）
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
systemctl restart docker
systemctl enable docker
[ -f "${HOME:-~}/.ssh/id_rsa" ] ||  ssh-keygen -t rsa -P '' -f ~/.ssh/id_rsa
# ssh -p60022 localhost "true" || echo "ssh-copy-id"
# cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys
kolla-ansible -e 'ansible_port=60022' -e "ansible_python_interpreter=${KOLLA_DIR}/venv3/bin/python3" -i ${KOLLA_DIR}/multinode prechecks
# 拉取镜像（可选）
kolla-ansible -e 'ansible_port=60022' -e "ansible_python_interpreter=${KOLLA_DIR}/venv3/bin/python3" -i ${KOLLA_DIR}/multinode pull
# 各节点依赖安装
kolla-ansible -e 'ansible_port=60022' -e "ansible_python_interpreter=${KOLLA_DIR}/venv3/bin/python3" -i ${KOLLA_DIR}/multinode bootstrap-servers
# 部署
kolla-ansible -e 'ansible_port=60022' -e "ansible_python_interpreter=${KOLLA_DIR}/venv3/bin/python3" -i ${KOLLA_DIR}/multinode deploy
# 生成 admin-openrc.sh
kolla-ansible -e 'ansible_port=60022' -e "ansible_python_interpreter=${KOLLA_DIR}/venv3/bin/python3" -i ${KOLLA_DIR}/multinode post-deploy
cat /etc/kolla/admin-openrc.sh
curl http://192.168.168.150
# 调整日志
ln -sf /var/lib/docker/volumes/kolla_logs/_data/ /var/log/kolla
cat <<DEMO
source /etc/kolla/admin-openrc.sh  
openstack server create --image cirros --flavor m1.tiny --key-name mykey --network demo-net demo1
openstack network create --external --provider-physical-network physnet1 --provider-network-type flat public
openstack subnet create --no-dhcp --allocation-pool 'start=192.168.50.10,end=192.168.50.100' --network public --subnet-range 192.168.50.0/24 --gateway 192.168.50.1 public-subnet
openstack network create --provider-network-type vxlan demo-net
openstack subnet create --subnet-range 10.0.0.0/24 --network demo-net --gateway 10.0.0.1 --dns-nameserver 8.8.8.8 demo-subnet
openstack router create demo-router
openstack router add subnet demo-router demo-subnet
openstack router set --external-gateway public demo-router
neutron net-list

DEMO
cat<<EOF
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
ansible -i multinode all  -m shell -a 'docker stop mariadb'
ansible -i multinode all -m shell -a "sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/g' /var/lib/docker/volumes/mariadb/_data/grastate.dat"
kolla-ansible mariadb_recovery -i multinode
# 减少controller（控制）节点
# vim multinode 去掉相关控制节点
kolla-ansible deploy -i multinode
# 减少compute（计算）节点
openstack compute service list
openstack compute service delete ID
# vim multinode 去掉相关计算节点
EOF
# 运行 init-runonce
init-runonce参考
cd /usr/share/kolla-ansible
vim init-runonce
./init-runonce
# # 清除 iptables 规则
iptables -F; iptables -X; iptables -Z
# # 清除上次部署
kolla-ansible destroy -i multinode --yes-i-really-really-mean-it
# # rabbitmq异常
# 先重启所有节点rabbitmq（多适用于关机导致的异常）
ansible -i multinode all -m shell -a 'docker restart rabbitmq'
# 如果重启节点没用，再删除并重新部署所有节点rabbitmq（多适用于部署时出现的异常）
ansible -i multinode all -m shell -a 'docker rm -f rabbitmq'
ansible -i multinode all -m shell -a 'docker volume rm rabbitmq'
ansible -i multinode all -m shell -a 'rm -rf /etc/kolla/rabbitmq'
kolla-ansible deploy -i multinode
# # nova_libvirt异常
ansible -i multinode all -m shell -a 'rm -rf /var/run/libvirtd.pid;docker restart nova_libvirt nova_compute'


